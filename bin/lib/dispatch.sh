#!/usr/bin/env bash
# opsx dispatch <slug> --agent claude|codex --model <id> --mode interactive|autopilot|drive --kind <kind> [--repo <path>]
# 把一張卡派出去：worktree → herdr tab（在 repo 掛的 workspace）→ agent start → 第一句 prompt → dispatch.json。
# 要求檔 §3.6「派」、§3.6 自主程度表、§3.1。herdr 的每個呼叫都可以被 PATH 上的假 herdr 取代（tests/fakes）。

opsx_dispatch() {
  local slug="" agent=claude model="" mode=autopilot kind="" top=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --mode) mode="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --repo) top="$2"; shift 2 ;;
      --*) die "dispatch: 不認得的選項 $1" ;;
      *) [ -z "$slug" ] && slug="$1" || die "dispatch: 多餘的參數 $1"; shift ;;
    esac
  done
  [ -n "$slug" ] || die "dispatch: 要給 slug"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "dispatch: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  case "$agent" in claude|codex) ;; *) die "dispatch: --agent 只收 claude|codex" ;; esac
  case "$mode" in interactive|autopilot|drive) ;; *) die "dispatch: --mode 只收 interactive|autopilot|drive" ;; esac
  local d="$top/openspec/changes/$slug" repo; repo="$(basename "$top")"
  [ -d "$d" ] || die "dispatch: 沒有這張卡：$d"
  printf '%s' "$slug" | grep -qE '^[a-z][a-z0-9_-]{0,31}$' || die "dispatch: slug 要符合 [a-z][a-z0-9_-]{0,31}（herdr agent 名）：$slug"
  command -v herdr >/dev/null || die "dispatch: 找不到 herdr"
  ensure_dir "$OPSX_STATE_DIR"

  # kind：沒給就從 .openspec.yaml 讀，再沒有 → dev；寫回 .openspec.yaml
  if [ -z "$kind" ]; then kind="$(st_card_kind "$d")"; kind="${kind:-dev}"; fi
  case "$kind" in dev|bug-fix|refactoring|perf|experiment|ops|chore) ;; *) die "dispatch: kind 不在七種裡：$kind" ;; esac
  if grep -q '^kind:' "$d/.openspec.yaml" 2>/dev/null; then
    sed -i '' "s/^kind:.*/kind: $kind/" "$d/.openspec.yaml" 2>/dev/null || sed -i "s/^kind:.*/kind: $kind/" "$d/.openspec.yaml"
  else printf 'kind: %s\n' "$kind" >> "$d/.openspec.yaml"; fi

  # model：沒給就照 kind
  if [ -z "$model" ]; then
    if [ "$agent" = codex ]; then model=gpt-5
    else case "$kind" in dev|refactoring|perf|experiment) model=claude-opus-5-5 ;; *) model=claude-sonnet-5-5 ;; esac; fi
  fi

  # branch：workplan 有就用，沒有就 {type}/{slug}/{user}
  local branch; branch="$(workplan_branch "$top" "$slug")"
  if [ -z "$branch" ]; then
    local t=feat; case "$kind" in bug-fix) t=fix ;; refactoring) t=refactor ;; ops|chore) t=chore ;; esac
    branch="$t/$slug/${OPSX_USER:-$(git -C "$top" config user.name 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]')}"
  fi

  # worktree：一卡一棵
  local wt="$top/.claude/worktrees/$slug"
  if [ ! -d "$wt" ]; then
    ensure_dir "$top/.claude/worktrees"
    if git -C "$top" show-ref --verify --quiet "refs/heads/$branch"; then git -C "$top" worktree add -q "$wt" "$branch"
    else git -C "$top" worktree add -q "$wt" -b "$branch"; fi
  fi

  # workspace：workspaces.toml 有就用，沒有就開一個以 repo 命名並記下來
  local ws; ws="$(workspace_for "$repo")"
  if [ -z "$ws" ]; then
    ws="$(herdr workspace create --label "$repo" --cwd "$top" --no-focus 2>/dev/null | jq -r '.result.workspace // empty' 2>/dev/null || true)"
    [ -n "$ws" ] || die "dispatch: herdr workspace create 沒回 workspace id"
    printf '"%s" = "%s"\n' "$repo" "$ws" >> "$OPSX_STATE_DIR/workspaces.toml"
    say "dispatch: 新 workspace ${ws}（${repo}）記進 workspaces.toml"
  fi

  # pane：在那個 workspace 開一個 tab
  local tabjson pane tab
  tabjson="$(herdr tab create --workspace "$ws" --cwd "$wt" --label "$slug" --no-focus)"
  pane="$(printf '%s' "$tabjson" | jq -r '.result.root_pane // empty' 2>/dev/null || true)"
  tab="$(printf '%s' "$tabjson" | jq -r '.result.tab // empty' 2>/dev/null || true)"
  [ -n "$pane" ] || die "dispatch: herdr tab create 沒回 root_pane：$tabjson"

  # agent 啟動參數（自動 / 開到可合併 才帶 permission 設定）
  local -a aargs=()
  if [ "$agent" = claude ]; then
    aargs+=(--model "$model")
    if [ "$mode" != interactive ]; then
      local settings="$OPSX_STATE_DIR/settings/$repo-$slug.json"; ensure_dir "$(dirname "$settings")"
      write_settings "$settings" "$repo"
      aargs+=(--permission-mode acceptEdits --settings "$settings")
    fi
  else
    if [ "$mode" = interactive ]; then aargs+=(-a on-request -s workspace-write); else aargs+=(-a never -s workspace-write); fi
  fi
  herdr agent start "$slug" --kind "$agent" --pane "$pane" -- "${aargs[@]}" >/dev/null

  # dispatch.json
  OPSX_KEY="$repo/$slug" OPSX_WS="$ws" OPSX_TAB="$tab" OPSX_PANE="$pane" OPSX_AGENT="$agent" OPSX_MODEL="$model" OPSX_MODE="$mode" OPSX_KIND="$kind" OPSX_WT="$wt" OPSX_BR="$branch" OPSX_AT="$(now_iso)" \
  python3 -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import json,os,sys
p=sys.argv[1]
try: d=json.load(open(p))
except (FileNotFoundError,json.JSONDecodeError): d={}
e=os.environ
d[e["OPSX_KEY"]]={"workspace":e["OPSX_WS"],"tab":e["OPSX_TAB"],"pane":e["OPSX_PANE"],"agent":e["OPSX_AGENT"],"model":e["OPSX_MODEL"],
  "mode":e["OPSX_MODE"],"kind":e["OPSX_KIND"],"worktree":e["OPSX_WT"],"branch":e["OPSX_BR"],"grants":[],"started_at":e["OPSX_AT"],"drive_pid":None}
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PY

  # 第一句：照狀態
  local first; first="$(stage_name "$top" "$slug")"
  case "$first" in explore|grill|propose|apply|review|pr|babysit) ;; *) first=explore ;; esac
  herdr agent prompt "$slug" "/$first $slug" >/dev/null
  printf '%s\t%s\t%s\n' "$(now_iso)" "指派給 ${agent}（${mode} · ${model}），第一句 /${first}" "dispatched" >> "$d/decisions.tsv"
  say "dispatch: $repo/$slug → $agent $model · $mode · kind $kind · $ws $pane · 第一句 /$first"

  if [ "$mode" = drive ]; then
    nohup bash "$OPSX_ROOT/bin/opsx" drive "$slug" --repo "$top" >> "$OPSX_STATE_DIR/drive-$repo-$slug.log" 2>&1 &
    local pid=$!
    OPSX_KEY="$repo/$slug" OPSX_PID="$pid" python3 -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import json,os,sys
p=sys.argv[1]; d=json.load(open(p)); d[os.environ["OPSX_KEY"]]["drive_pid"]=int(os.environ["OPSX_PID"]); json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PY
    say "dispatch: drive.sh 跑起來了（pid ${pid}），log 在 $OPSX_STATE_DIR/drive-$repo-$slug.log"
  fi
}

workplan_branch() { # <top> <slug> → branch 或空
  [ -f "$1/openspec/workplan.yaml" ] || return 0
  awk -v s="$2" '$0 ~ "name: *"s"$"{f=1;next} f && /branch:/{sub(/.*branch: */,""); print; exit} f && /^ *- name:/{exit}' "$1/openspec/workplan.yaml"
}
workspace_for() { # <repo> → workspace id 或空
  [ -f "$OPSX_STATE_DIR/workspaces.toml" ] || return 0
  OPSX_REPO="$1" python3 -I - "$OPSX_STATE_DIR/workspaces.toml" <<'PY'
import os,sys,tomllib
try: print(tomllib.load(open(sys.argv[1],"rb")).get("repos",{}).get(os.environ["OPSX_REPO"],""))
except Exception: print("")
PY
}
write_settings() { # <file> <repo>：直接做那級 allow，永遠要人那級 deny；repo 永遠的授權也進 allow
  OPSX_REPO="$2" OPSX_SD="$OPSX_STATE_DIR" python3 -I - "$1" <<'PY'
import json,os,sys,tomllib
sd=os.environ["OPSX_SD"]; repo=os.environ["OPSX_REPO"]
allow=["Read","Edit","Write","Glob","Grep","Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git add:*)","Bash(git commit:*)","Bash(git checkout:*)","Bash(git worktree:*)",
       "Bash(pnpm test:*)","Bash(pnpm vitest:*)","Bash(pnpm build:*)","Bash(pnpm lint:*)","Bash(pnpm typecheck:*)","Bash(npx vitest:*)","Bash(pytest:*)","Bash(uv run:*)","Bash(ruff:*)","Bash(go test:*)",
       "Bash(openspec:*)","Bash(opsx:*)","Bash(ls:*)","Bash(cat:*)","Bash(grep:*)","Bash(rg:*)","Bash(find:*)","Bash(node:*)","Bash(python3:*)"]
deny=["Bash(git push --force:*)","Bash(git push -f:*)","Bash(glab mr merge:*)","Bash(gh pr merge:*)","Bash(deploy.sh:*)","Bash(sops:*)","Bash(rm -rf /:*)"]
try:
    g=tomllib.load(open(os.path.join(sd,"grants.toml"),"rb")).get("repos",{}).get(repo,{})
    if g.get("push"): allow.append("Bash(git push:*)")
    if g.get("mr"): allow+=["Bash(glab mr create:*)","Bash(glab mr update:*)","Bash(gh pr create:*)","Bash(gh pr edit:*)"]
    if g.get("migrate"): allow+=["Bash(pnpm db:migrate:*)","Bash(alembic upgrade:*)"]
except FileNotFoundError: pass
json.dump({"permissions":{"allow":allow,"deny":deny}},open(sys.argv[1],"w"),indent=2)
PY
}
