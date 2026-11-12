#!/usr/bin/env bash
# opsx dispatch <slug> --agent claude|codex --model <id> --mode interactive|autopilot --kind <kind> [--repo <path>]
# opsx dispatch --feature <feature> [--only <卡,…>] --agent … --mode …：一個 session 代管 workplan 一個 feature 現在能開工的主 change；
#   --only 只交出列出的卡，第一句照列出的順序給第一張（coordinate 用它濾掉 P2、把 P0 排前面）
# 把一張卡派出去：開 worktree，在 repo 掛的 workspace 開 herdr tab，agent start，送第一句 prompt，記進 dispatch.json。
# 要求檔 §3.6「派」、§3.6 自主程度表、§3.1。herdr 的每個呼叫都可以被 PATH 上的假 herdr 取代（tests/fakes）。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/note.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/agents-md.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/launch.sh"

opsx_dispatch() {
  local slug="" agent=claude model="" mode=autopilot kind="" top="" feature="" plan="" note="" has_note="" only=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --feature) feature="$2"; shift 2 ;;
      --only) only="$2"; shift 2 ;;
      --note) has_note=1; note="$(note_oneline "$2")"; shift 2 ;;
      --agent) agent="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --mode) mode="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --repo) top="$2"; shift 2 ;;
      --*) die "dispatch: 不認得的選項 $1" ;;
      *) [ -z "$slug" ] && slug="$1" || die "dispatch: 多餘的參數 $1"; shift ;;
    esac
  done
  if [ -n "$feature" ]; then
    [ -z "$slug" ] || die "dispatch: slug 與 --feature 只能給一個"
    slug="$feature"   # herdr agent 名、worktree、tab 都用 feature 名
  fi
  [ -z "$only" ] || [ -n "$feature" ] || die "dispatch: --only 只能跟 --feature 一起用"
  [ -n "$slug" ] || die "dispatch: 要給 slug"
  [ -z "$has_note" ] || [ -n "$note" ] || die "dispatch: --note 壓成一行後是空的"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "dispatch: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  case "$agent" in claude|codex) ;; *) die "dispatch: --agent 只收 claude|codex" ;; esac
  case "$mode" in interactive|autopilot) ;; drive) mode=autopilot ;; *) die "dispatch: --mode 只收 interactive|autopilot（drive 是 autopilot 的舊名）" ;; esac
  printf '%s' "$slug" | grep -qE '^[a-z][a-z0-9_-]{0,31}$' || die "dispatch: slug 要符合 [a-z][a-z0-9_-]{0,31}（herdr agent 名）：$slug"
  local card="$slug" repo; repo="$(basename "$top")"
  command -v herdr >/dev/null || die "dispatch: 找不到 herdr"
  ensure_dir "$OPSX_STATE_DIR"

  # herdr agent 只認名字（agent start <name>），新卡的名字 = slug。還在跑的條目用的 herdr 名（herdr_name，沒有就是它的 slug）
  # 跟這個 slug 一樣時，prompt 會送錯人，所以拒絕；代管卡的 herdr 名是協調它的 pane。
  # 單一續接交出去的條目（herdr 名已改成子卡、列在 handed_to 裡）只是紀錄，不算；fan-out 的父卡 pane 還活著、名字還是父卡，照算。
  # feature session 自己的條目是 <repo>/@<feature>，pane 活不活只看它：它還活著就算成員全停了，herdr 上 feature 名的 agent 也還在；
  # 它停了，同 repo 成員條目（via @<feature>）的 agent 也跟著不在，不算撞名
  local me_key="$repo/$slug"
  [ -z "$feature" ] || me_key="$repo/@$feature"
  OPSX_KEY="$me_key" OPSX_SLUG="$slug" OPSX_FEATURE="$feature" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY' || exit 2
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import chain, jsonfile
d = jsonfile.load(sys.argv[1]); me = os.environ["OPSX_KEY"]; slug = os.environ["OPSX_SLUG"]; feature = os.environ["OPSX_FEATURE"]
mine = d.get(me)
if mine and (chain.session_alive(mine) if feature else mine.get("mode") != "stopped"):
    sys.exit("dispatch: %s 已經派出去了，在 %s · %s · %s（%s 起）。要換人先 opsx stop %s" % (me, mine.get("workspace"), mine.get("tab"), mine.get("pane"), mine.get("started_at"), me.split("/", 1)[1]))
members = {k for k, v in d.items() if feature and k.startswith(me.split("/", 1)[0] + "/") and v.get("via") == "@" + feature}
clash = [k for k, v in d.items() if k != me and k not in members and v.get("mode") != "stopped" and (v.get("herdr_name") or k.split("/", 1)[1]) not in (v.get("handed_to") or []) and (v.get("herdr_name") or k.split("/", 1)[1]) == slug]
if clash:
    sys.exit("dispatch: herdr agent 名字就是 slug，而 %s 還在跑、用的 herdr 名也是 %s，herdr agent prompt 會送錯 agent。先 opsx stop 那張，或把這張卡改名" % ("、".join(clash), slug))
PY

  if [ -n "$feature" ]; then
    plan="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/chain.py" feature "$top" "$feature")" || exit 2
    # 這個 session 的成員條目（via @<feature>）是 stopped 就是人停的：不寫它的條目、不給它第一句。feature_plan 只管 workplan 上能不能開工
    plan="$(OPSX_PLAN="$plan" OPSX_ONLY="$only" OPSX_REPO="$repo" OPSX_FEATURE="$feature" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import chain, jsonfile
d = jsonfile.load(sys.argv[1]); e = os.environ
lines = e["OPSX_PLAN"].splitlines()
if e["OPSX_ONLY"]:
    by_slug = {line.split("\t")[0]: line for line in lines}
    want = e["OPSX_ONLY"].split(",")
    missing = [s for s in want if s not in by_slug]
    if missing:
        sys.exit("dispatch: --only 的 %s 不在 feature「%s」現在能開工的主 change（%s）裡"
                 % ("、".join(missing), e["OPSX_FEATURE"], "、".join(by_slug)))
    lines = [by_slug[s] for s in want]
keep, held = [], []
for line in lines:
    entry = d.get("%s/%s" % (e["OPSX_REPO"], line.split("\t")[0]))
    (held if chain.human_stopped(entry, e["OPSX_FEATURE"]) else keep).append(line)
if not keep:
    sys.exit("dispatch: feature「%s」能開工的主 change（%s）都被人停了；要接回其中一張用 opsx dispatch <slug>"
             % (e["OPSX_FEATURE"], "、".join(l.split("\t")[0] for l in held)))
print("\n".join(keep))
PY
)" || exit 2
    card="$(printf '%s' "$plan" | head -1 | cut -f1)"
  fi
  local d="$top/openspec/changes/$card"
  [ -d "$d" ] || die "dispatch: 沒有這張卡：$d"
  if [ -z "$feature" ]; then
    # 人停掉的 session 成員卡：session 還活著就交回 session（grill D1），它的 branch 可能正被 session 的 worktree checkout，單卡派會被 git 拒絕
    local session; session="$(OPSX_REPO="$repo" OPSX_SLUG="$slug" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import chain, jsonfile
d = jsonfile.load(sys.argv[1]); repo = os.environ["OPSX_REPO"]
mine = d.get("%s/%s" % (repo, os.environ["OPSX_SLUG"]))
if mine and mine.get("feature"):
    s = d.get("%s/@%s" % (repo, mine["feature"]))
    if s and chain.session_alive(s):
        print(mine["feature"])
PY
)"
    if [ -n "$session" ]; then send_to_session "$top" "$repo" "$slug" "$session" "$note"; return; fi
  fi

  # kind：沒給就從 .openspec.yaml 讀，再沒有就是 dev；寫回 .openspec.yaml
  if [ -z "$kind" ]; then kind="$(st_card_kind "$d")"; kind="${kind:-dev}"; fi
  case "$kind" in dev|bug-fix|refactoring|perf|experiment|ops|chore) ;; *) die "dispatch: kind 不在七種裡：$kind" ;; esac
  if grep -q '^kind:' "$d/.openspec.yaml" 2>/dev/null; then
    sed -i '' "s/^kind:.*/kind: $kind/" "$d/.openspec.yaml" 2>/dev/null || sed -i "s/^kind:.*/kind: $kind/" "$d/.openspec.yaml"
  else printf 'kind: %s\n' "$kind" >> "$d/.openspec.yaml"; fi

  # model：沒給就照 kind
  [ -n "$model" ] || model="$(default_model "$agent" "$kind")"

  # branch：workplan 有就用，沒有就 {type}/{slug}/{user}
  local branch; branch="$(workplan_branch "$top" "$card")"
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
    local used; used="$(git -C "$top" worktree list --porcelain | awk -v b="branch refs/heads/$branch" '/^worktree /{w=substr($0, 10)} $0 == b {print w}')"
    [ -z "$used" ] || die "dispatch: 分支 $branch 已經 checkout 在 ${used}$(held_by "$used")，不另開 worktree。那張卡在做就不用派；沒人在做就先收掉那棵 worktree"
    ensure_dir "$top/.claude/worktrees"
    if git -C "$top" show-ref --verify --quiet "refs/heads/$branch"; then git -C "$top" worktree add -q "$wt" "$branch"
    else
      # 主 checkout 可能不在 main、或還沒 pull 剛合併的依賴：有 remote 的 main 就從 fetch 後的它開。
      # 沒有 remote 追蹤分支的（本機 repo、測試）只能從主 checkout 的 HEAD 開
      local remote start=HEAD; remote="$(primary_remote "$top")"
      if git -C "$top" show-ref --verify --quiet "refs/remotes/$remote/main"; then
        git -C "$top" fetch -q "$remote" || die "dispatch: $top 的 git fetch $remote 失敗，不從舊的 $remote/main 開分支"
        start="$remote/main"
      fi
      git -C "$top" worktree add -q --no-track "$wt" -b "$branch" "$start"
    fi
  fi
  warn_untrusted "$top"
  # codex 沒有 router hook：把同一批規則放進 worktree。worktree 已在也寫（重派可能換模式）
  if [ "$agent" = codex ]; then place_agents_md "$wt" "$mode" || die "dispatch: AGENTS.md 放不進 $wt"; fi

  # workspace：workspaces.toml 記的是 label（人看的，例 acmecorp-ai），開 agent 用 workspace list 換成 id；沒掛就開一個以 repo 為 label 的
  local ws ws_arg; ws="$(workspace_for "$repo")"
  if [ -n "$ws" ]; then
    ws_arg=(--workspace-label "$ws")
  else
    ws="$repo"
    ws_arg=(--workspace-create "$repo" "$top" --on-workspace-created dispatch_record_workspace)
  fi

  launch_args "$agent" "$model" "$mode" "$repo" "$slug" "$top"
  # 名字被占用：dispatch.json 沒記著（手動開的、或 stop 時 pane 沒關成）但 herdr 還有同名 agent，指出它在哪
  runtime_open "$me_key" --kind "$agent" "${ws_arg[@]}" --cwd "$wt" --label "$slug" -- "${LAUNCH_ARGS[@]}" \
    || die "dispatch: herdr agent start 失敗：herdr 已經有叫 ${slug} 的 agent，dispatch.json 沒記：${HERDR_TAKEN_AT}。關掉那個 pane 再派"
  local pane="$RUNTIME_PANE" tab="$RUNTIME_TAB" ws_id="$RUNTIME_WORKSPACE_ID"

  # dispatch.json
  # 一般卡一筆。feature session 另有自己的條目 <repo>/@<feature>（pane 層的欄位），每個能開工的主 change 再各一筆：
  # pane 照抄 session 的，herdr_name / feature 是 feature 名，via 指向 @<feature>
  [ -n "$plan" ] || plan="$card"$'\t'"$branch"$'\t'"$kind"
  local written
  written="$(OPSX_REPO="$repo" OPSX_FEATURE="$feature" OPSX_PLAN="$plan" OPSX_WS="$ws" OPSX_WSID="$ws_id" OPSX_TAB="$tab" OPSX_PANE="$pane" OPSX_AGENT="$agent" OPSX_MODEL="$model" OPSX_MODE="$mode" OPSX_WT="$wt" OPSX_AT="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" \
  "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import chain, jsonfile
e = os.environ
written = []
def put(d):
    repo, feature = e["OPSX_REPO"], e["OPSX_FEATURE"]
    pane_part = {"workspace": e["OPSX_WS"], "workspace_id": e["OPSX_WSID"], "tab": e["OPSX_TAB"], "pane": e["OPSX_PANE"], "agent": e["OPSX_AGENT"],
                 "model": e["OPSX_MODEL"], "mode": e["OPSX_MODE"], "worktree": e["OPSX_WT"], "started_at": e["OPSX_AT"], "drive_pid": None}
    rows = [line.split("\t") for line in e["OPSX_PLAN"].splitlines()]
    if feature:
        # 從判斷人停到這裡，dispatch 開 worktree、等 agent 起來，人可能又在板上停了一張：寫入前再查一次
        rows = [r for r in rows if not chain.human_stopped(d.get("%s/%s" % (repo, r[0])), feature)]
        if not rows:
            return
        d["%s/@%s" % (repo, feature)] = dict(pane_part)
        # 不在這次 plan 裡、沒停的成員（開了 MR 在等合併）也改抄新 pane，collect 才不會拿舊 pane 判它的 agent 不在
        for k, v in d.items():
            if k.startswith(repo + "/") and v.get("via") == "@" + feature and v.get("mode") != "stopped":
                v.update(pane_part)
    for card, branch, kind in rows:
        entry = dict(pane_part, kind=kind, branch=branch, grants=[], once=[])
        if feature:
            entry["herdr_name"] = entry["feature"] = feature
            entry["via"] = "@" + feature
        d["%s/%s" % (repo, card)] = entry
        written.append(card)
jsonfile.update(sys.argv[1], put)
print("\n".join(written))
PY
)" || exit 2
  if [ -z "$written" ]; then
    herdr tab close "$tab" >/dev/null 2>&1 || true
    die "dispatch: feature「${feature}」能開工的主 change 在派工途中都被人停了，tab 已關"
  fi
  card="$(printf '%s\n' "$written" | head -1)"; d="$top/openspec/changes/$card"

  # 第一句：照狀態
  local first; first="$(stage_name "$top" "$card")"
  case "$first" in explore|grill|propose|apply|review|pr|babysit) ;; *) first=explore ;; esac
  # 指示要在 agent 讀到第一句前就在卡上；放在前面每一步之後，失敗的派工不會留下指示，重跑也不會寫兩條
  if [ -n "$note" ]; then note_append "$d" "$note" || die "dispatch: 寫不進 $d/inbox.md 的派工指示，第一句沒送"; fi
  herdr agent prompt "$slug" "/opsx-workflow:$first $card" >/dev/null
  local c via=""
  [ -n "$feature" ] && via="（session ${feature}）"
  for c in $written; do
    log_row "$top/openspec/changes/$c" 你 已指派 "指派給 ${agent}${via}，第一句 /opsx-workflow:${first} ${card}" "${agent} · ${mode} · ${model}"
  done
  say "dispatch: $repo/$slug → $agent $model · $mode · kind $kind · $ws $pane · 第一句 /opsx-workflow:$first $card"

  if [ -n "$feature" ]; then
    # drive 對 herdr agent 名 = 卡名送話；session 代管多張卡，跟 fan-out 的代管卡一樣不起 drive
    say "dispatch: session $feature 代管 $(printf '%s\n' "$written" | tr '\n' ' ')；不起 drive"
  elif [ "$mode" = autopilot ]; then
    # pid 由 drive 自己寫進 dispatch.json（手動 opsx drive 也一樣），這裡只負責起
    local drivelog="$OPSX_STATE_DIR/drive-$repo-$slug.log"
    : | opsx_append "$drivelog" 2>/dev/null || die "dispatch: refuse to write through symlink: ${drivelog}（卡已派出，drive 沒起）"
    ( trap '' HUP; exec "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/safefile.py" exec-append "$drivelog" bash "$OPSX_ROOT/bin/opsx" drive "$slug" --repo "$top" ) < /dev/null > /dev/null 2>&1 &
    say "dispatch: drive 跑起來了（pid $!），log 在 $drivelog"
  fi
}

send_to_session() { # <top> <repo> <slug> <feature> <note>：人停的成員卡交回活著的 session，不開 pane
  local top="$1" repo="$2" slug="$3" feature="$4" note="$5" d="$1/openspec/changes/$3" first
  first="$(stage_name "$top" "$slug")"
  case "$first" in explore|grill|propose|apply|review|pr|babysit) ;; *) die "dispatch: $repo/$slug 現在的階段是 ${first:-（算不出來）}，不能交回 session ${feature}" ;; esac
  if [ -n "$note" ]; then note_append "$d" "$note" || die "dispatch: 寫不進 $d/inbox.md 的派工指示，沒送給 session"; fi
  herdr agent prompt "$feature" "[$slug] /opsx-workflow:$first $slug" >/dev/null || die "dispatch: 送不到 session ${feature}，$repo/$slug 仍是 stopped"
  # 送到了才清 stopped；pane 層的欄位重抄 session 條目，舊 pane 不會被拿去送話
  OPSX_KEY="$repo/$slug" OPSX_SESSION="$repo/@$feature" OPSX_AT="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
def put(d):
    e, s = d[os.environ["OPSX_KEY"]], d[os.environ["OPSX_SESSION"]]
    for k in ("workspace", "workspace_id", "tab", "pane", "worktree", "agent", "model", "mode"):
        e[k] = s[k]
    e["started_at"] = os.environ["OPSX_AT"]
    e.pop("stopped_at", None)
    e.pop("pane_closed_at", None)
jsonfile.update(sys.argv[1], put)
PY
  log_row "$d" 你 已指派 "交回 session ${feature}，送 [${slug}] /opsx-workflow:${first} ${slug}" "session ${feature}"
  say "dispatch: $repo/$slug 交回 session ${feature}，送 [${slug}] /opsx-workflow:${first} ${slug}；不開 pane"
}

workplan_branch() { wp_pr_field "$1" "$2" branch; } # <top> <slug>：印 workplan 裡這張卡所屬 PR 的 branch，沒有就空
held_by() { # <worktree>：印 dispatch.json 裡 worktree 指向它的條目（「（key · pane …）」），沒有就空。兩邊路徑先 realpath 再比
  [ -f "$OPSX_STATE_DIR/dispatch.json" ] || return 0
  OPSX_WT="$1" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
wt = os.path.realpath(os.environ["OPSX_WT"])
hits = ["%s · pane %s" % (k, v.get("pane")) for k, v in jsonfile.load(sys.argv[1]).items() if v.get("worktree") and os.path.realpath(v["worktree"]) == wt]
if hits:
    print("（%s）" % "；".join(hits))
PY
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
# runtime_open 的 --on-workspace-created：新 workspace 一建好就記 label，在開 tab 之前。
# 早於 create 記，create 失敗後每次派工都找不到這個 label；晚到 agent 起來才記，開 agent 失敗一次重派就多開一個同名 workspace
dispatch_record_workspace() { # <label> <workspace id>
  grep -q '^\[repos\]' "$OPSX_STATE_DIR/workspaces.toml" 2>/dev/null || printf '\n[repos]\n' | opsx_append "$OPSX_STATE_DIR/workspaces.toml" || die "dispatch: 寫不進 $OPSX_STATE_DIR/workspaces.toml"   # 第二台機器沒跑過 init 時檔案是空的
  printf '"%s" = "%s"\n' "$1" "$1" | opsx_append "$OPSX_STATE_DIR/workspaces.toml" || die "dispatch: 寫不進 $OPSX_STATE_DIR/workspaces.toml"
  say "dispatch: 新 workspace ${1}（${2}）記進 workspaces.toml"
}
