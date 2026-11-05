#!/usr/bin/env bash
# herdr action open-board：起看板 server（已在跑就不重起）+ 開瀏覽器帶 token。herdr-board 5.1、specs/board-plugin。
#   server：python3 herdr-board/server.py --port ${OPSX_BOARD_PORT}（預設 8791），pid 在 $OPSX_STATE_DIR/board.pid，log 在 board.log
#   token：server 第一次啟動寫 $OPSX_STATE_DIR/board-token；拼進 URL，頁面讀一次存 sessionStorage 後抹掉
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
state="${OPSX_STATE_DIR:-$HOME/.local/state/opsx}"
port="${OPSX_BOARD_PORT:-8791}"
url="http://127.0.0.1:${port}/"
mkdir -p "$state"
pidfile="$state/board.pid"; logfile="$state/board.log"

alive() { # server 活著且是我們的：pid 在、healthz 通
  local pid; pid="$(cat "$pidfile" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && curl -sf --max-time 1 "${url}healthz" >/dev/null 2>&1
}

if ! alive; then
  rm -f "$pidfile"
  nohup python3 -I "$root/herdr-board/server.py" --port "$port" --state "$state" >>"$logfile" 2>&1 &
  printf '%s\n' "$!" > "$pidfile"
  for _ in $(seq 1 50); do
    curl -sf --max-time 1 "${url}healthz" >/dev/null 2>&1 && break
    kill -0 "$(cat "$pidfile")" 2>/dev/null || { echo "opsx board: server 起不來，看 $logfile" >&2; tail -n 20 "$logfile" >&2 || true; exit 1; }
    sleep 0.1
  done
  curl -sf --max-time 1 "${url}healthz" >/dev/null 2>&1 || { echo "opsx board: server 10 秒內沒回應，看 $logfile" >&2; exit 1; }
fi

token="$(cat "$state/board-token" 2>/dev/null || true)"
open_url="$url"; [ -n "$token" ] && open_url="${url}?token=${token}"
if command -v open >/dev/null 2>&1; then open "$open_url"
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$open_url"
else echo "opsx board: 自己開 $open_url"; fi
echo "opsx 看板：${url}（server pid $(cat "$pidfile")，log ${logfile}）"
