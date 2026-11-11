#!/usr/bin/env bash
# opsx relaunch <slug> [--repo <top>]：pane 裡的 claude 丟了 dispatch 給的參數（herdr 還原 pane、手動 resume）時，
# /exit 後用 dispatch 同一套參數 --resume 原 session，再送回目前那一站。主殼 relaunch-cmd D1–D5。
# 失敗一律大聲報、pane 留著給人看；不改走 stop 加 dispatch，那會開新 session、丟掉原本的 context。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/route.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/launch.sh"

opsx_relaunch() {
  local slug="" top=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --*) die "relaunch: 不認得的選項 $1" ;;
      *) [ -z "$slug" ] && slug="$1" || die "relaunch: 多餘的參數 $1"; shift ;;
    esac
  done
  [ -n "$slug" ] || die "relaunch: 要給 slug"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "relaunch: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  local repo; repo="$(basename "$top")"
  command -v herdr >/dev/null || die "relaunch: 找不到 herdr"
  refuse_if_handed "$repo" "$slug" relaunch

  # 成員卡（via @<feature>）與 fan-out 子卡（via <父卡>）沒有自己的 agent：重開代管它的 pane（session 或父卡的條目），
  # 對它代管的每張卡送話。fan-out 時父卡已經歸檔，所以不要求父卡的目錄
  local route name via key="$repo/$slug"
  route="$(card_route "$repo" "$slug")" || die "relaunch: 讀不懂 dispatch.json"
  name="${route%%$'\t'*}"; via="${route#*$'\t'}"
  [ -z "$via" ] || key="$repo/$via"
  local entry pane model mode drive_pid
  entry="$(OPSX_KEY="$key" OPSX_ASKED="$repo/$slug" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
d = jsonfile.load(sys.argv[1]); key = os.environ["OPSX_KEY"]; asked = os.environ["OPSX_ASKED"]
e = d.get(key)
if e is None:
    sys.exit("relaunch: %s 沒派過（dispatch.json 沒有 %s）" % (asked, key))
if e.get("mode") == "stopped":
    sys.exit("relaunch: %s 已經 stopped，pane 不在了；要重開用 opsx dispatch" % key)
if e.get("agent") != "claude":
    sys.exit("relaunch: 只支援 claude，%s 記的 agent 是 %s" % (key, e.get("agent")))
missing = [k for k in ("pane", "model", "mode") if not e.get(k)]
if missing:
    sys.exit("relaunch: %s 缺 %s，組不出 dispatch 的啟動參數" % (key, "、".join(missing)))
print("\t".join([e["pane"], e["model"], e["mode"], str(e.get("drive_pid") or "")]))
PY
)" || exit 2
  IFS=$'\t' read -r pane model mode drive_pid <<< "$entry"

  # session id 只在 claude 還活著時拿得到（/exit 之後就沒了），而且 agent list 只能用 pane_id 對
  local agents sid
  agents="$(herdr agent list 2>&1)" || die "relaunch: herdr agent list 失敗：$agents"
  sid="$(OPSX_AGENTS="$agents" OPSX_PANE="$pane" "$OPSX_PY" -I - <<'PY'
import json, os, sys
pane = os.environ["OPSX_PANE"]
try:
    agents = json.loads(os.environ["OPSX_AGENTS"])["result"]["agents"]
except (json.JSONDecodeError, KeyError, TypeError) as e:
    sys.exit("relaunch: herdr agent list 讀不懂（%s）" % e)
hit = [a for a in agents if a.get("pane_id") == pane]
if not hit:
    sys.exit("relaunch: herdr agent list 裡沒有 pane %s 的 agent，拿不到 session id；到 pane 看" % pane)
status = hit[0].get("agent_status")
if status not in ("idle", "blocked"):
    sys.exit("relaunch: pane %s 的 agent 是 %s，只對 idle 或 blocked 動手" % (pane, status))
session = hit[0].get("agent_session")
if not session or not session.get("value"):
    sys.exit("relaunch: pane %s 的 agent 沒有 agent_session，拿不到 session id" % pane)
print(session["value"])
PY
)" || exit 2

  # 送哪一站先算好：算不出來就在送鍵之前停。單卡送 /<stage> <slug>；代管的卡照 send_to_session 的格式，每張沒停的一句
  local d="$top/openspec/changes/$slug" members m stage prompts=()
  [ -d "$d" ] || die "relaunch: 沒有這張卡：$d"
  if [ -z "$via" ]; then members="$slug"
  else
    members="$(OPSX_REPO="$repo" OPSX_VIA="$via" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
d = jsonfile.load(sys.argv[1]); repo = os.environ["OPSX_REPO"]
for k, v in d.items():
    if k.startswith(repo + "/") and v.get("via") == os.environ["OPSX_VIA"] and v.get("mode") != "stopped":
        print(k.split("/", 1)[1])
PY
)" || exit 2
    [ -n "$members" ] || die "relaunch: $key 代管的卡都 stopped 了，沒有要送的那一站"
  fi
  for m in $members; do
    if [ ! -d "$top/openspec/changes/$m" ]; then
      # session 自己 /archive 的成員條目不會被標 stopped，略過；不在也沒歸檔才停，否則 stage_name 印 explore，等於對它送 /explore
      if compgen -G "$top/openspec/changes/archive/????-??-??-$m" >/dev/null; then continue; fi
      die "relaunch: $key 代管的 $repo/$m 沒有卡目錄、也不在 archive/，dispatch.json 還記著它沒停"
    fi
    stage="$(stage_name "$top" "$m")"
    case "$stage" in explore|grill|propose|apply|review|pr|babysit) ;; *) die "relaunch: $repo/$m 現在的階段是 ${stage:-（算不出來）}，沒有可送的那一站" ;; esac
    if [ -z "$via" ]; then prompts+=("/opsx-workflow:$stage $m"); else prompts+=("[$m] /opsx-workflow:$stage $m"); fi
  done
  [ "${#prompts[@]}" -gt 0 ] || die "relaunch: $key 代管的卡都已歸檔，沒有要送的那一站"

  # 參數也在送鍵、kill drive 之前組好：寫 settings 失敗（例如 grants.toml 壞了）時 set -e 在這裡就停
  launch_args claude "$model" "$mode" "$repo" "$name" "$top"
  local -a args=("${LAUNCH_ARGS[@]}")

  # 標記從這裡到結束都在；die 也會經過 EXIT
  relaunch_mark "$key" set
  trap "relaunch_mark $(printf '%q' "$key") clear" EXIT

  # drive 在 claude 退出的空窗收到 agent_not_found 會叫 coordinate，coordinate 就把 pane 收掉重派：/exit 前先停它
  if [ -n "$drive_pid" ] && kill -0 "$drive_pid" 2>/dev/null; then
    kill "$drive_pid" || die "relaunch: drive pid $drive_pid kill 不掉，沒送任何鍵"
    say "relaunch: drive pid $drive_pid 已 kill"
  fi
  [ -z "$drive_pid" ] || relaunch_mark "$key" "unset-drive:$drive_pid"

  local out
  out="$(herdr pane send-keys "$pane" esc 2>&1)" || relaunch_fail "$d" "$pane" "send-keys esc 失敗：$out"
  out="$(herdr pane send-text "$pane" /exit 2>&1)" || relaunch_fail "$d" "$pane" "send-text /exit 失敗：$out"
  out="$(herdr pane send-keys "$pane" enter 2>&1)" || relaunch_fail "$d" "$pane" "send-keys enter 失敗：$out"

  # 跟 dispatch 一樣只重試 agent_pane_busy（/exit 後 shell 還沒回到提示字元），但失敗時不關 tab：那是原本的 pane
  local try=1
  until out="$(herdr agent start "$name" --kind claude --pane "$pane" -- --resume "$sid" "${args[@]}" 2>&1)"; do
    case "$out" in
      *agent_pane_busy*) if [ "$try" -lt 6 ]; then try=$((try + 1)); sleep "${OPSX_DISPATCH_RETRY_SLEEP:-1}"; continue; fi ;;
    esac
    relaunch_fail "$d" "$pane" "herdr agent start 失敗（第 ${try} 次）：$out"
  done

  local p
  for p in "${prompts[@]}"; do
    out="$(herdr agent prompt "$name" "$p" 2>&1)" || relaunch_fail "$d" "$pane" "herdr agent prompt「${p}」失敗：$out"
  done
  log_row "$d" 你 已指派 "relaunch：pane ${pane} 接回 session ${sid}，送 ${prompts[*]}" "claude · ${mode} · ${model}"
  say "relaunch: $repo/$slug → pane $pane 接回 session ${sid}，送 ${prompts[*]}"

  # 跟 dispatch 一樣：代管多張卡的 pane 不起 drive；pid 由 drive 自己登記
  if [ -z "$via" ] && [ "$mode" = autopilot ]; then
    local drivelog="$OPSX_STATE_DIR/drive-$repo-$slug.log"
    [ ! -L "$drivelog" ] || relaunch_fail "$d" "$pane" "refuse to write through symlink: ${drivelog}（pane 已接回，drive 沒起）"
    ( trap '' HUP; exec bash "$OPSX_ROOT/bin/opsx" drive "$slug" --repo "$top" ) < /dev/null >> "$drivelog" 2>&1 &
    say "relaunch: drive 跑起來了（pid $!），log 在 $drivelog"
  fi
}

# 送鍵之後的失敗：pane 可能停在 shell 或半開的 claude，印畫面給人接手、卡上記一列，pane 不關
relaunch_fail() { # <card dir> <pane> <原因>
  local screen
  # pane 已壞時 pane read 會失敗，當成沒輸出，不讓診斷蓋掉原本的錯誤
  screen="$(herdr pane read "$2" 2>/dev/null | tail -20)" || screen=""
  [ -n "${screen//[[:space:]]/}" ] || screen="pane 沒有任何輸出"
  log_row "$1" 你 已指派 "relaunch 失敗：$3" "pane $2"
  die "relaunch: $3
pane $2 留著沒關，到 pane 手動處理。pane 畫面（最後 20 行）：
${screen}"
}

# <repo/slug、repo/@feature 或 repo/<父卡>> set|clear|unset-drive:<pid>：寫或清 dispatch.json 條目的 relaunching_at；
# set 兼當鎖：十分鐘內已有標記就拒絕（同一個 pane 的兩次 relaunch 會交錯送鍵），更舊的當成被 kill 的 relaunch 留下的殘留。
# unset-drive 清掉被 kill 的 drive 的 pid（被 kill 的 drive 跑不到自己的 unregister），pid 已經換人就不動
relaunch_mark() {
  OPSX_KEY="$1" OPSX_OP="$2" OPSX_AT="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import datetime, os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
def put(d):
    e = d[os.environ["OPSX_KEY"]]
    op = os.environ["OPSX_OP"]
    if op == "set":
        prev = e.get("relaunching_at")
        at = datetime.datetime.fromisoformat(os.environ["OPSX_AT"])
        if prev and at - datetime.datetime.fromisoformat(prev) < datetime.timedelta(minutes=10):
            sys.exit("relaunch: %s 已經有一個 relaunch 在跑（%s 起），沒送任何鍵；十分鐘後標記還在就是殘留，可以再跑" % (os.environ["OPSX_KEY"], prev))
        e["relaunching_at"] = os.environ["OPSX_AT"]
    elif op == "clear":
        e.pop("relaunching_at", None)
    elif op.startswith("unset-drive:"):
        if str(e.get("drive_pid")) == op.split(":", 1)[1]:
            e["drive_pid"] = None
    else:
        sys.exit("relaunch_mark: 不認得的操作 %s" % op)
jsonfile.update(sys.argv[1], put)
PY
}
