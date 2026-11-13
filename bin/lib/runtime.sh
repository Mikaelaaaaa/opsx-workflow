#!/usr/bin/env bash
# agent runtime：呼叫者只說「對哪個 agent 做哪個動作」，herdr 的 argv、agent 名與 pane 的查法只寫在這裡。
# 對象是卡片身分 <repo>/<slug>（feature session 是 <repo>/@<feature>，也就是 dispatch.json 的 key），
# 或 --agent <名>：不是卡的 agent（協調者），不讀 dispatch.json。由 common.sh 在檔尾 source。
# 這裡只放 Orca 版也做得出來的動作；process-info、report-metadata、zoom、plugin、rename 等 herdr 專屬子指令由呼叫者直接下。

# 解析對象：設 RT_WHO（訊息用）、RT_NAME、RT_PANE、RT_TAB，RT_ARGC 是吃掉的參數個數。
# 名字的規則跟 route.sh 的 card_route 相同：條目的 herdr_name，沒有就是 key 的最後一段去掉 @。
runtime_target() { # <卡片身分> | --agent <名>
  RT_PANE=""; RT_TAB=""
  case "${1:-}" in
    --agent)
      [ -n "${2:-}" ] || { warn "runtime: --agent 後面要有 agent 名"; return 2; }
      RT_WHO="$2"; RT_NAME="$2"; RT_ARGC=2; return 0 ;;
    */*) ;;
    *) warn "runtime: 對象要是卡片身分 <repo>/<slug> 或 --agent <名>，收到：${1:-（空）}"; return 2 ;;
  esac
  RT_WHO="$1"; RT_ARGC=1
  local row
  row="$(OPSX_KEY="$1" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
except FileNotFoundError:
    d = {}
key = os.environ["OPSX_KEY"]
e = d.get(key) or {}
print("\x1f".join([e.get("herdr_name") or key.rsplit("/", 1)[1].removeprefix("@"), e.get("pane") or "", e.get("tab") or ""]))
PY
)" || return 2
  IFS=$'\x1f' read -r RT_NAME RT_PANE RT_TAB <<< "$row"
}

runtime_need() { # <pane|tab> <值>
  [ -z "$2" ] || return 0
  warn "runtime: ${RT_WHO} 在 dispatch.json 沒有 $1（還沒派出去，或對象是 --agent），不送 herdr"
  return 2
}

runtime_prompt() { # <對象> <一行>
  runtime_target "$@" || return; shift "$RT_ARGC"
  herdr agent prompt "$RT_NAME" "$1"
}

# 不給 --lines 讀 pane 原文（bash 呼叫者自己 tail）；給了讀 agent 的文字畫面（python 呼叫者的形式）
runtime_read() { # <對象> [--lines <N>]
  runtime_target "$@" || return; shift "$RT_ARGC"
  runtime_need pane "$RT_PANE" || return
  case "$#:${1:-}" in
    0:) herdr pane read "$RT_PANE" ;;
    2:--lines) herdr agent read "$RT_PANE" --lines "$2" --format text ;;
    *) warn "runtime_read: ${RT_WHO} 只收 --lines <N>，收到：$*"; return 2 ;;
  esac
}

runtime_get() { # <對象>
  runtime_target "$@" || return
  herdr agent get "$RT_NAME"
}

runtime_list() {
  herdr agent list
}

# 選項照呼叫者給的順序送出
runtime_wait() { # <對象> [--until <狀態>] [--timeout <毫秒>]
  runtime_target "$@" || return; shift "$RT_ARGC"
  local opts=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --until|--timeout)
        [ $# -ge 2 ] || { warn "runtime_wait: ${RT_WHO} 的 $1 後面要有值"; return 2; }
        opts+=("$1" "$2"); shift 2 ;;
      *) warn "runtime_wait: ${RT_WHO} 不認得的參數 $1（只收 --until、--timeout）"; return 2 ;;
    esac
  done
  herdr agent wait "$RT_NAME" ${opts[@]+"${opts[@]}"}
}

runtime_focus() { # <對象>
  runtime_target "$@" || return
  herdr agent focus "$RT_NAME"
}

# exit 是 relaunch 用的 /exit 序列（esc、/exit、enter），任一步失敗就停在那一步
runtime_close() { # <對象> pane|tab|exit
  runtime_target "$@" || return; shift "$RT_ARGC"
  case "${1:-}" in
    pane) runtime_need pane "$RT_PANE" || return; herdr pane close "$RT_PANE" ;;
    tab) runtime_need tab "$RT_TAB" || return; herdr tab close "$RT_TAB" ;;
    exit) runtime_need pane "$RT_PANE" || return
      herdr pane send-keys "$RT_PANE" esc && herdr pane send-text "$RT_PANE" /exit && herdr pane send-keys "$RT_PANE" enter ;;
    *) warn "runtime_close: ${RT_WHO} 的關法只有 pane、tab、exit，收到：${1:-（空）}"; return 2 ;;
  esac
}

runtime_notify() { # <標題> <內文> [--sound <名>]
  case "$#:${3:-}" in
    2:) herdr notification show "$1" --body "$2" ;;
    4:--sound) herdr notification show "$1" --body "$2" --sound "$4" ;;
    *) warn "runtime_notify: 標題與內文之後只收 --sound <名>，收到：${*:3}"; return 2 ;;
  esac
}

# 開 agent：在 workspace 開一個 tab，在它的 root pane 起 agent。workspace 三選一：
#   --workspace-id <id>；--workspace-label <label>（workspace list 換 id，沒有這個 label 就列出現有的並結束）；
#   --workspace-create <label> <cwd>（開新的 workspace）。--on-workspace-created <函式名> 只配 --workspace-create：
#   新 id 拿到就以 <label> <id> 呼叫它，在開 tab 之前，呼叫者在這裡記下新 workspace；它失敗就結束、不開 tab。
# 成功設 RUNTIME_PANE、RUNTIME_TAB、RUNTIME_WORKSPACE_ID。agent 名只從卡片身分推、不讀 dispatch.json：
# 派工時舊條目的 herdr_name 是上一次派工的（續接改名、feature 成員），新的 agent 用卡自己的名字。
# shell 還沒到 prompt 時 herdr 回 agent_pane_busy，同一個 pane 最多試六次；起不來就收掉剛開的 tab（不留空 tab 給人收）並結束。
# 名字已被占用（agent_name_taken）時收掉 tab、把另一個的位置放進 HERDR_TAKEN_AT、回 3：該怎麼說由呼叫者決定。
runtime_open() { # <對象> --kind <kind> <workspace 旗標> --cwd <dir> --label <tab label> [-- agent 參數…]
  local who name kind="" cwd="" label="" ws_id="" ws_label="" ws_create="" ws_create_cwd="" on_created="" nws=0 tabjson pane tab out try=1 screen
  case "${1:-}" in
    --agent) [ -n "${2:-}" ] || die "runtime_open: --agent 後面要有 agent 名"; who="$2"; name="$2"; shift 2 ;;
    */*) who="$1"; name="${1##*/}"; name="${name#@}"; shift ;;
    *) die "runtime_open: 對象要是卡片身分 <repo>/<slug> 或 --agent <名>，收到：${1:-（空）}" ;;
  esac
  while [ $# -gt 0 ]; do
    case "$1" in
      --workspace-create) [ $# -ge 3 ] || die "${who}: runtime_open 的 --workspace-create 後面要有 <label> <cwd>" ;;
      --kind|--cwd|--label|--workspace-id|--workspace-label|--on-workspace-created) [ $# -ge 2 ] || die "${who}: runtime_open 的 $1 後面要有值" ;;
    esac
    case "$1" in
      --kind) kind="$2"; shift 2 ;;
      --cwd) cwd="$2"; shift 2 ;;
      --label) label="$2"; shift 2 ;;
      --workspace-id) ws_id="$2"; nws=$((nws + 1)); shift 2 ;;
      --workspace-label) ws_label="$2"; nws=$((nws + 1)); shift 2 ;;
      --workspace-create) ws_create="$2"; ws_create_cwd="$3"; nws=$((nws + 1)); shift 3 ;;
      --on-workspace-created) on_created="$2"; shift 2 ;;
      --) shift; break ;;
      *) die "${who}: runtime_open 不認得的參數 $1" ;;
    esac
  done
  [ "$nws" -eq 1 ] || die "${who}: runtime_open 要剛好一個 --workspace-id、--workspace-label 或 --workspace-create"
  [ -n "$kind" ] && [ -n "$cwd" ] && [ -n "$label" ] || die "${who}: runtime_open 要有 --kind、--cwd、--label"
  [ -z "$on_created" ] || [ -n "$ws_create" ] || die "${who}: runtime_open 的 --on-workspace-created 只配 --workspace-create"

  if [ -n "$ws_label" ]; then
    ws_id="$(OPSX_WSJSON="$(herdr workspace list 2>/dev/null || true)" OPSX_WS="$ws_label" OPSX_WHO="$who" "$OPSX_PY" -I - <<'PY'
import json, os, sys
want, who = os.environ["OPSX_WS"], os.environ["OPSX_WHO"]
try:
    wss = json.loads(os.environ["OPSX_WSJSON"] or "null")["result"]["workspaces"]   # heredoc 占了 stdin，JSON 走環境變數
except (json.JSONDecodeError, KeyError, TypeError) as e:
    sys.exit("%s: herdr workspace list 讀不懂（%s）；在 herdr pane 裡跑嗎？" % (who, e))
hit = [w for w in wss if w.get("workspace_id") == want or w.get("label") == want]
if not hit:
    sys.exit("%s: herdr 沒有 workspace「%s」（現有：%s）。改 workspaces.toml 成其中一個 label，或先在 herdr 建一個叫 %s 的 workspace"
             % (who, want, "、".join(str(w.get("label")) for w in wss) or "無", want))
print(hit[0]["workspace_id"])
PY
)" || exit 2
  elif [ -n "$ws_create" ]; then
    ws_id="$(herdr workspace create --label "$ws_create" --cwd "$ws_create_cwd" --no-focus 2>/dev/null | jq -r '.result.workspace.workspace_id // .result.workspace_id // .result.workspace // empty' 2>/dev/null || true)"
    [ -n "$ws_id" ] || die "${who}: herdr workspace create 沒回 workspace id"
    [ -z "$on_created" ] || "$on_created" "$ws_create" "$ws_id" || die "${who}: 新 workspace ${ws_create}（${ws_id}）已開，${on_created} 失敗，不開 tab"
  fi

  # 真格式：result.root_pane.pane_id（w1:pE）、result.tab.tab_id（w1:tB）。沒有 tab id 就不起 agent：失敗時會關不掉剛開的 tab
  tabjson="$(herdr tab create --workspace "$ws_id" --cwd "$cwd" --label "$label" --no-focus)"
  pane="$(printf '%s' "$tabjson" | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null || true)"
  tab="$(printf '%s' "$tabjson" | jq -r '.result.tab.tab_id // empty' 2>/dev/null || true)"
  [ -n "$pane" ] && [ -n "$tab" ] || die "${who}: herdr tab create 沒回 root_pane 或 tab id：$tabjson"

  until out="$(herdr agent start "$name" --kind "$kind" --pane "$pane" -- "$@" 2>&1)"; do
    case "$out" in
      *agent_pane_busy*)
        if [ "$try" -lt 6 ]; then try=$((try + 1)); sleep "${OPSX_DISPATCH_RETRY_SLEEP:-1}"; continue; fi
        # pane 已壞時 pane read 會失敗，當成沒輸出，不讓診斷擋住錯誤回報
        screen="$(herdr pane read "$pane" 2>/dev/null | tail -20)" || screen=""
        [ -n "${screen//[[:space:]]/}" ] || screen="pane 沒有任何輸出"
        # 間隔可以是小數（sleep 吃 0.5），shell 算術只吃整數
        out="${out}
新 pane 的 shell 超過 $(awk -v n="$((try - 1))" -v s="${OPSX_DISPATCH_RETRY_SLEEP:-1}" 'BEGIN { print n * s }') 秒沒有出現提示字元，可能是 shell 啟動卡住。常見原因：pyenv 鎖檔 ~/.pyenv/shims/.pyenv-shim 殘留（opsx init --check 會檢查）
pane 畫面：
${screen}" ;;
      *agent_name_taken*)
        HERDR_TAKEN_AT="$(printf '%s' "$out" | grep -oE '(workspace_id|tab_id|pane_id|status)=[^ "]*' | tr '\n' ' ')"
        herdr tab close "$tab" >/dev/null 2>&1 || true
        return 3 ;;
      *agent_not_ready*)
        # Claude Code 在沒信任過的目錄先問 trust，herdr 判成 blocked；名字已記下，按 Yes 等到 idle 就等於 start 成功
        if herdr pane wait-output --match "trust this folder" --timeout 3000 "$pane" >/dev/null 2>&1; then
          herdr pane send-keys "$pane" down enter >/dev/null
          if herdr agent wait "$name" --until idle --timeout 60000 >/dev/null 2>&1; then break; fi
          out="trust 按了但 agent 沒到 idle"
        else
          out="${out}
pane 畫面：
$(herdr pane read "$pane" 2>/dev/null | tail -20)"
        fi ;;
    esac
    herdr tab close "$tab" >/dev/null 2>&1 || true
    die "${who}: herdr agent start 失敗（第 ${try} 次）：${out}"
  done
  RUNTIME_PANE="$pane"; RUNTIME_TAB="$tab"; RUNTIME_WORKSPACE_ID="$ws_id"
}

# 回報一行給協調者 session。送不出去（它不在、herdr 掛了）記 coordinator.log 並回 1；成功回 0。
coordinator_say() { # <一行>
  local err
  err="$(runtime_prompt --agent "$COORDINATOR_AGENT" "$1" 2>&1 >/dev/null)" && return 0
  printf '%s ?? 回報 %s 送不出去：%s\n' "$(now_iso)" "$COORDINATOR_AGENT" "$(printf '%s' "$err" | head -c 200 | tr '\n' ' ')" | opsx_append "$OPSX_STATE_DIR/coordinator.log" || true
  return 1
}
