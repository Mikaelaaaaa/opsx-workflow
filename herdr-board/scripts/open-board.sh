#!/usr/bin/env bash
# herdr action open-board：起看板 server（已在跑就不重起）+ 開瀏覽器帶 token。herdr-board 5.1、specs/board-plugin。
#   server：python3 herdr-board/server.py --port ${OPSX_BOARD_PORT}（預設 8791），pid 在 $OPSX_STATE_DIR/board-<port>.pid（每個 port 一份），log 在 board.log
#   token：server 第一次啟動寫 $OPSX_STATE_DIR/board-token；拼進 URL，頁面讀一次存 sessionStorage 後抹掉
#   用法：open-board.sh [<repo>/<slug>]，給了就在同一個 fragment 加 card=，網頁開頁後展開那張卡
set -euo pipefail
card="${1:-}"
# 參數錯不起 server，所以先驗
# slug 照 collect 列出的目錄名收，不套 herdr agent 名的 32 字上限；兩段都會經 quote 編碼
if [ -n "$card" ] && ! [[ "$card" =~ ^[^/]+/[^/]+$ ]]; then
  echo "opsx board: 參數要是 <repo>/<slug>，收到 [$card]" >&2; exit 1
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
state="${OPSX_STATE_DIR:-$HOME/.local/state/opsx}"
port="${OPSX_BOARD_PORT:-8791}"
url="http://127.0.0.1:${port}/"
mkdir -p "$state"
pidfile="$state/board-${port}.pid"; logfile="$state/board.log"

alive() { # server 活著且是我們的：pid 在、healthz 回的是 opsx-board、token 檔還在（token 被刪就重起，不然新 tab 永遠 401）
  local pid; pid="$(cat "$pidfile" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ -s "$state/board-token" ] \
    && curl -sf --max-time 1 "${url}healthz" 2>/dev/null | grep -q '"app": *"opsx-board"'
}

# 兩個 workspace 同時按 open-board：只有一個能進啟動段（mkdir 是原子的）；另一個等它起好
lock="$state/board.lock"
for _ in $(seq 1 100); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
trap 'rmdir "$lock" 2>/dev/null' EXIT
if ! alive; then
  pid="$(cat "$pidfile" 2>/dev/null || true)"; [ -n "$pid" ] && kill "$pid" 2>/dev/null || true   # token 不見或 healthz 不對：重起
  rm -f "$pidfile"
  ( trap '' HUP; exec python3 -I "$root/herdr-board/server.py" --port "$port" --state "$state" ) </dev/null >>"$logfile" 2>&1 &
  printf '%s\n' "$!" > "$pidfile"
  for _ in $(seq 1 50); do
    curl -sf --max-time 1 "${url}healthz" >/dev/null 2>&1 && break
    kill -0 "$(cat "$pidfile")" 2>/dev/null || { echo "opsx board: server 起不來，看 ${logfile}" >&2; tail -n 20 "$logfile" >&2 || true; exit 1; }
    sleep 0.1
  done
  curl -sf --max-time 1 "${url}healthz" >/dev/null 2>&1 || { echo "opsx board: server 10 秒內沒回應，看 ${logfile}" >&2; exit 1; }
fi

token="$(cat "$state/board-token" 2>/dev/null || true)"
frag=()   # fragment 不進 server log、不進 Referer
[ -n "$token" ] && frag+=("token=${token}")
[ -n "$card" ] && frag+=("card=$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$card")")
open_url="$url"; [ ${#frag[@]} -gt 0 ] && open_url="${url}#$(IFS='&'; printf '%s' "${frag[*]}")"

orca_fail() { # orca_fail <步驟> <orca stdout>：不退回系統瀏覽器，免得看板開在使用者沒在看的地方
  echo "opsx board: orca $1 失敗，沒有改用系統瀏覽器" >&2
  [ -n "$2" ] && printf '%s\n' "$2" >&2
  cat "$orca_err" >&2; rm -f "$orca_err"; exit 1
}
# 只有 Orca terminal 有 ORCA_TERMINAL_HANDLE；tab create 不收 --focus，要拿 browserPageId 再 tab switch
if [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then
  orca_err="$state/orca-tab.err"   # 拿著 board.lock，同時只有一支 open-board 寫它
  # Orca 的 Electron 殼成功時也在 stderr 印 codesign 雜訊，JSON 只從 stdout 讀
  created="$(orca tab create --url "$open_url" --json 2>"$orca_err")" || orca_fail "tab create" "$created"
  page="$(python3 -I -c '
import json, sys
d = json.loads(sys.argv[1])
if "browserPageId" not in d.get("result", {}):
    sys.exit("orca tab create 回的 JSON 沒有 result.browserPageId")
print(d["result"]["browserPageId"])
' "$created")" || orca_fail "tab create" "$created"
  switched="$(orca tab switch --page "$page" --focus 2>"$orca_err")" || orca_fail "tab switch" "$switched"
  rm -f "$orca_err"
elif command -v open >/dev/null 2>&1; then open "$open_url"
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$open_url"
else echo "opsx board: 沒有 open 或 xdg-open，自己開 $open_url" >&2; exit 1; fi
echo "opsx 看板：${url}（server pid $(cat "$pidfile")，log ${logfile}）"
