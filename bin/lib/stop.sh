#!/usr/bin/env bash
# opsx stop <slug> [--repo <top>]：板上的「停止」。kill drive 迴圈、關掉 pane、dispatch.json 標 stopped。
# worktree 和 branch 留著（重派會重用）。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/route.sh"

opsx_stop() {
  local slug="" top="" board=""
  while [ $# -gt 0 ]; do
    case "$1" in --repo) top="$2"; shift 2 ;; --board) board=1; shift ;; *) [ -z "$slug" ] && slug="$1" || die "stop: 多餘的參數 $1"; shift ;; esac
  done
  if [ -n "$board" ]; then stop_board; return; fi
  [ -n "$slug" ] || die "stop: 要給 slug（或 --board 關看板 server）"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "stop: 不在 git repo 裡，或給 --repo"
  local repo; repo="$(basename "$(cd "$top" && pwd -P)")"
  local f="$OPSX_STATE_DIR/dispatch.json"
  refuse_if_handed "$repo" "$slug" stop
  [ -f "$f" ] || die "stop: 沒有 dispatch.json"
  local entry; entry="$(OPSX_KEY="$repo/$slug" "$OPSX_PY" -I -c 'import json,os,sys;d=json.load(open(sys.argv[1]));print(json.dumps(d.get(os.environ["OPSX_KEY"],{})))' "$f")"
  [ "$entry" != "{}" ] || die "stop: $repo/$slug 沒派過"
  local pid pane; pid="$(printf '%s' "$entry" | jq -r '.drive_pid // empty')"; pane="$(printf '%s' "$entry" | jq -r '.pane // empty')"
  local route name via; route="$(card_route "$repo" "$slug")" || die "stop: 讀不懂 dispatch.json"; name="${route%%$'\t'*}"; via="${route#*$'\t'}"
  if [ -n "$via" ]; then
    # 代管卡跟兄弟卡共用 pane，關 pane 會連兄弟一起停：只請 pane 停掉這張的 subagent（grill D4）
    if herdr agent prompt "$name" "[$slug] stop" >/dev/null 2>&1; then say "stop: 已請 $name 的 pane 停掉 $slug 的 subagent，pane 不關"
    else say "stop: 送不到 ${name}，$slug 照樣標 stopped；它的 subagent 可能還在跑，到 pane $pane 看"; fi
  else
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; say "stop: drive pid $pid 已 kill"; fi
    if [ -n "$pane" ]; then herdr pane close "$pane" >/dev/null 2>&1 && say "stop: pane $pane 關了" || say "stop: pane $pane 關不掉（可能已經不在）"; fi
  fi
  OPSX_KEY="$repo/$slug" OPSX_AT="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$f" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
def put(d):
    e = d[os.environ["OPSX_KEY"]]; e["mode"] = "stopped"; e["drive_pid"] = None; e["stopped_at"] = os.environ["OPSX_AT"]
jsonfile.update(sys.argv[1], put)
PY
  log_row "$top/openspec/changes/$slug" 你 已停止 停止
  say "stop: $repo/$slug 標 stopped"
}

# opsx stop --board：關看板 server（open-board.sh 起的，pid 在 board-<port>.pid，port 取 OPSX_BOARD_PORT，預設 8791）。
# 舊版的單一 board.pid 也一併關掉清掉。design Risks「server 被留著跑」。
stop_board() {
  local port="${OPSX_BOARD_PORT:-8791}" pidfile found=""
  for pidfile in "$OPSX_STATE_DIR/board-${port}.pid" "$OPSX_STATE_DIR/board.pid"; do
    [ -f "$pidfile" ] || continue
    found=1; stop_board_pidfile "$pidfile"
  done
  [ -n "$found" ] || say "stop --board: 沒有 $OPSX_STATE_DIR/board-${port}.pid，server 沒在跑"
}

stop_board_pidfile() {
  local pidfile="$1" pid
  pid="$(cat "$pidfile")"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then kill "$pid" && say "stop --board: server pid ${pid} 已 kill（${pidfile##*/}）"
  else say "stop --board: pid ${pid:-?} 已經不在，只清 ${pidfile##*/}"; fi
  rm -f "$pidfile"
}
