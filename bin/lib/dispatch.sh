#!/usr/bin/env bash
# opsx dispatch <slug> --agent claude|codex --model <id> --mode interactive|autopilot|drive --kind <kind> [--repo <path>]
# 把一張卡派出去：開 worktree，在 repo 掛的 workspace 開 herdr tab，agent start，送第一句 prompt，記進 dispatch.json。
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

  # herdr agent 只認名字（agent start <name>），新卡的名字 = slug。還在跑的條目用的 herdr 名（herdr_name，沒有就是它的 slug）
  # 跟這個 slug 一樣時，prompt 會送錯人，所以拒絕；代管卡的 herdr 名是協調它的 pane
  OPSX_KEY="$repo/$slug" OPSX_SLUG="$slug" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY' || exit 2
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
d = jsonfile.load(sys.argv[1]); me = os.environ["OPSX_KEY"]; slug = os.environ["OPSX_SLUG"]
mine = d.get(me)
if mine and mine.get("mode") != "stopped":
    sys.exit("dispatch: %s 已經派出去了，在 %s · %s · %s（%s 起）。要換人先 opsx stop %s" % (me, mine.get("workspace"), mine.get("tab"), mine.get("pane"), mine.get("started_at"), slug))
clash = [k for k, v in d.items() if k != me and v.get("mode") != "stopped" and (v.get("herdr_name") or k.split("/", 1)[1]) == slug]
if clash:
    sys.exit("dispatch: herdr agent 名字就是 slug，而 %s 還在跑、用的 herdr 名也是 %s，herdr agent prompt 會送錯 agent。先 opsx stop 那張，或把這張卡改名" % ("、".join(clash), slug))
PY

  # kind：沒給就從 .openspec.yaml 讀，再沒有就是 dev；寫回 .openspec.yaml
  if [ -z "$kind" ]; then kind="$(st_card_kind "$d")"; kind="${kind:-dev}"; fi
  case "$kind" in dev|bug-fix|refactoring|perf|experiment|ops|chore) ;; *) die "dispatch: kind 不在七種裡：$kind" ;; esac
  if grep -q '^kind:' "$d/.openspec.yaml" 2>/dev/null; then
    sed -i '' "s/^kind:.*/kind: $kind/" "$d/.openspec.yaml" 2>/dev/null || sed -i "s/^kind:.*/kind: $kind/" "$d/.openspec.yaml"
  else printf 'kind: %s\n' "$kind" >> "$d/.openspec.yaml"; fi

  # model：沒給就照 kind
  [ -n "$model" ] || model="$(default_model "$agent" "$kind")"

  # branch：workplan 有就用，沒有就 {type}/{slug}/{user}
  local branch; branch="$(workplan_branch "$top" "$slug")"
  if [ -z "$branch" ]; then
    local t=feat; case "$kind" in bug-fix) t=fix ;; refactoring) t=refactor ;; ops|chore) t=chore ;; esac
    local user="${OPSX_USER:-$(git -C "$top" config user.name 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]')}"
    # git 沒設身分時 user.name 是占位字「Your Name」，會變成 feat/<slug>/your-name
    case "$user" in ""|your-name) die "dispatch: 分支尾巴沒有名字：OPSX_USER 沒設，git config user.name 是「$(git -C "$top" config user.name 2>/dev/null)」。設 OPSX_USER，或在這個 repo git config user.name" ;; esac
    branch="$t/$slug/$user"
  fi

  # worktree：一卡一棵
  local wt="$top/.claude/worktrees/$slug"
  if [ ! -d "$wt" ]; then
    ensure_dir "$top/.claude/worktrees"
    if git -C "$top" show-ref --verify --quiet "refs/heads/$branch"; then git -C "$top" worktree add -q "$wt" "$branch"
    else git -C "$top" worktree add -q "$wt" -b "$branch"; fi
  fi

  # workspace：workspaces.toml 記的是 label（人看的，例 agnetory-ai），herdr 的 tab create 只吃 id（w1），
  # 所以用 `herdr workspace list`（result.workspaces[].{label,workspace_id}，2026-11-06 實跑）換；沒掛就開一個以 repo 為 label 的
  local ws ws_id; ws="$(workspace_for "$repo")"
  if [ -n "$ws" ]; then
    ws_id="$(OPSX_WSJSON="$(herdr workspace list 2>/dev/null || true)" OPSX_WS="$ws" "$OPSX_PY" -I - <<'PY'
import json, os, sys
want = os.environ["OPSX_WS"]
try:
    wss = json.loads(os.environ["OPSX_WSJSON"] or "null")["result"]["workspaces"]   # heredoc 占了 stdin，JSON 走環境變數
except (json.JSONDecodeError, KeyError, TypeError) as e:
    sys.exit("dispatch: herdr workspace list 讀不懂（%s）；在 herdr pane 裡跑嗎？" % e)
hit = [w for w in wss if w.get("workspace_id") == want or w.get("label") == want]
if not hit:
    sys.exit("dispatch: herdr 沒有 workspace「%s」（現有：%s）。改 workspaces.toml 成其中一個 label，或先在 herdr 建一個叫 %s 的 workspace"
             % (want, "、".join(str(w.get("label")) for w in wss) or "無", want))
print(hit[0]["workspace_id"])
PY
)" || exit 2
  else
    ws="$repo"
    ws_id="$(herdr workspace create --label "$repo" --cwd "$top" --no-focus 2>/dev/null | jq -r '.result.workspace.workspace_id // .result.workspace_id // .result.workspace // empty' 2>/dev/null || true)"
    [ -n "$ws_id" ] || die "dispatch: herdr workspace create 沒回 workspace id"
    grep -q '^\[repos\]' "$OPSX_STATE_DIR/workspaces.toml" 2>/dev/null || printf '\n[repos]\n' >> "$OPSX_STATE_DIR/workspaces.toml"   # 第二台機器沒跑過 init 時檔案是空的
    printf '"%s" = "%s"\n' "$repo" "$ws" >> "$OPSX_STATE_DIR/workspaces.toml"
    say "dispatch: 新 workspace ${ws}（${ws_id}）記進 workspaces.toml"
  fi

  # pane：在那個 workspace 開一個 tab。真格式：result.root_pane.pane_id（w1:pE）、result.tab.tab_id（w1:tB）
  local tabjson pane tab
  tabjson="$(herdr tab create --workspace "$ws_id" --cwd "$wt" --label "$slug" --no-focus)"
  pane="$(printf '%s' "$tabjson" | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null || true)"
  tab="$(printf '%s' "$tabjson" | jq -r '.result.tab.tab_id // empty' 2>/dev/null || true)"
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
    # Claude Code 的沙盒只准寫 working directories；卡的檔在主 repo 的 openspec/（worktree 裡沒有），hook 消耗 once 與 status 鏡像寫 state dir
    aargs+=(--add-dir "$top/openspec" --add-dir "$OPSX_STATE_DIR")
  else
    if [ "$mode" = interactive ]; then aargs+=(-a on-request -s workspace-write); else aargs+=(-a never -s workspace-write); fi
  fi
  # 剛開的 pane 的 shell 還沒到 prompt 時 herdr 回 agent_pane_busy，同一個 pane 最多試六次；起不來就收掉剛開的 tab，不留空 tab 給人收
  local out try=1
  until out="$(herdr agent start "$slug" --kind "$agent" --pane "$pane" -- "${aargs[@]}" 2>&1)"; do
    case "$out" in
      *agent_pane_busy*) if [ "$try" -lt 6 ]; then try=$((try + 1)); sleep "${OPSX_DISPATCH_RETRY_SLEEP:-1}"; continue; fi ;;
      *agent_name_taken*)
        # dispatch.json 沒記著（手動開的、或 stop 時 pane 沒關成）但 herdr 還有同名 agent：指出它在哪
        out="herdr 已經有叫 ${slug} 的 agent，dispatch.json 沒記：$(printf '%s' "$out" | grep -oE '(workspace_id|tab_id|pane_id|status)=[^ "]*' | tr '\n' ' ')。關掉那個 pane 再派" ;;
      *agent_not_ready*)
        # Claude Code 在沒信任過的目錄（每棵新 worktree）先問 trust，herdr 判成 blocked；名字已記下，按 Yes 等到 idle 就等於 start 成功
        if herdr pane wait-output --match "trust this folder" --timeout 3000 "$pane" >/dev/null 2>&1; then
          herdr pane send-keys "$pane" down enter >/dev/null
          if herdr agent wait "$slug" --until idle --timeout 60000 >/dev/null 2>&1; then break; fi
          out="trust 按了但 agent 沒到 idle"
        else
          out="${out}
pane 畫面：
$(herdr pane read "$pane" 2>/dev/null | tail -20)"
        fi ;;
    esac
    herdr tab close "$tab" >/dev/null 2>&1 || true
    die "dispatch: herdr agent start 失敗（第 ${try} 次）：${out}"
  done

  # dispatch.json
  OPSX_KEY="$repo/$slug" OPSX_WS="$ws" OPSX_WSID="$ws_id" OPSX_TAB="$tab" OPSX_PANE="$pane" OPSX_AGENT="$agent" OPSX_MODEL="$model" OPSX_MODE="$mode" OPSX_KIND="$kind" OPSX_WT="$wt" OPSX_BR="$branch" OPSX_AT="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" \
  "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
e = os.environ
def put(d):
    d[e["OPSX_KEY"]] = {"workspace": e["OPSX_WS"], "workspace_id": e["OPSX_WSID"], "tab": e["OPSX_TAB"], "pane": e["OPSX_PANE"], "agent": e["OPSX_AGENT"],
                        "model": e["OPSX_MODEL"], "mode": e["OPSX_MODE"], "kind": e["OPSX_KIND"], "worktree": e["OPSX_WT"], "branch": e["OPSX_BR"],
                        "grants": [], "once": [], "started_at": e["OPSX_AT"], "drive_pid": None}
jsonfile.update(sys.argv[1], put)
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
    OPSX_KEY="$repo/$slug" OPSX_PID="$pid" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
def put(d): d[os.environ["OPSX_KEY"]]["drive_pid"] = int(os.environ["OPSX_PID"])
jsonfile.update(sys.argv[1], put)
PY
    say "dispatch: drive.sh 跑起來了（pid ${pid}），log 在 $OPSX_STATE_DIR/drive-$repo-$slug.log"
  fi
}

workplan_branch() { # <top> <slug>：印 workplan 裡這張卡的 branch，沒有就空
  [ -f "$1/openspec/workplan.yaml" ] || return 0
  awk -v s="$2" '$0 ~ "name: *"s"$"{f=1;next} f && /branch:/{sub(/.*branch: */,""); print; exit} f && /^ *- name:/{exit}' "$1/openspec/workplan.yaml"
}
workspace_for() { # <repo>：印 workspaces.toml 記的 label（或 id），沒有就空
  [ -f "$OPSX_STATE_DIR/workspaces.toml" ] || return 0
  OPSX_REPO="$1" "$OPSX_PY" -I - "$OPSX_STATE_DIR/workspaces.toml" <<'PY'
import os, sys, tomllib
try:
    print(tomllib.load(open(sys.argv[1], "rb")).get("repos", {}).get(os.environ["OPSX_REPO"], ""))
except tomllib.TOMLDecodeError as e:
    sys.exit("dispatch: workspaces.toml 壞了：%s" % e)
PY
}
write_settings() { # <file> <repo>：直接做那級 allow，永遠要人那級 deny；repo 永遠的授權也進 allow
  OPSX_REPO="$2" OPSX_SD="$OPSX_STATE_DIR" "$OPSX_PY" -I - "$1" <<'PY'
import json,os,sys,tomllib
sd=os.environ["OPSX_SD"]; repo=os.environ["OPSX_REPO"]
allow=["Read","Edit","Write","Glob","Grep","Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git add:*)","Bash(git commit:*)","Bash(git checkout:*)","Bash(git worktree:*)",
       "Bash(pnpm test:*)","Bash(pnpm vitest:*)","Bash(pnpm build:*)","Bash(pnpm lint:*)","Bash(pnpm typecheck:*)","Bash(npx vitest:*)","Bash(pytest:*)","Bash(uv run:*)","Bash(ruff:*)","Bash(go test:*)",
       "Bash(openspec:*)","Bash(opsx:*)","Bash(ls:*)","Bash(cat:*)","Bash(grep:*)","Bash(rg:*)","Bash(find:*)","Bash(node:*)","Bash(python3:*)"]
# merge 不在 deny：settings 的 deny 蓋得過 hook 的放行，所以 merge 交給 opsx-grant-gate.sh 的 merge_gate 單獨把關；
# 放進 allow 是為了閘門放行那一次不再跳 Claude Code 自己的權限框。
allow += ["Bash(glab mr merge:*)", "Bash(gh pr merge:*)"]
deny=["Bash(git push --force:*)","Bash(git push -f:*)","Bash(deploy.sh:*)","Bash(sops:*)","Bash(rm -rf /:*)"]
try:
    g=tomllib.load(open(os.path.join(sd,"grants.toml"),"rb")).get("repos",{}).get(repo,{})
    if g.get("push"): allow.append("Bash(git push:*)")
    if g.get("mr"): allow+=["Bash(glab mr create:*)","Bash(glab mr update:*)","Bash(gh pr create:*)","Bash(gh pr edit:*)"]
    if g.get("migrate"): allow+=["Bash(pnpm db:migrate:*)","Bash(alembic upgrade:*)"]
except FileNotFoundError: pass
json.dump({"permissions":{"allow":allow,"deny":deny}},open(sys.argv[1],"w"),indent=2)
PY
}
