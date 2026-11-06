#!/usr/bin/env bash
# herdr plugin：manifest 可讀、open-board.sh 起 server 一次並開瀏覽器、init --global 做 herdr plugin link。
# 驗收：specs/board-plugin/spec.md「herdr plugin manifest」「open-board action」（herdr-board 5.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin" "$OPSX_STATE_DIR"
printf '#!/usr/bin/env bash\nexec bash "%s/herdr" "$@"\n' "$FAKES" > "$FX/fakebin/herdr"
printf '#!/usr/bin/env bash\nprintf "open %%s\\n" "$*" >> "%s"\n' "$FX/open.log" > "$FX/fakebin/open"   # 假的 macOS open
printf '#!/usr/bin/env bash\nprintf "xdg-open %%s\\n" "$*" >> "%s"\n' "$FX/open.log" > "$FX/fakebin/xdg-open"
chmod +x "$FX/fakebin/"*
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"; : > "$FX/open.log"
trap 'kill "$(cat "$OPSX_STATE_DIR/board.pid" 2>/dev/null)" 2>/dev/null; rm -rf "$FX"' EXIT   # 斷言失敗也要把 server 收掉

# --- manifest ---
python3 -I - "$OPSX_ROOT" <<'PY' || fail "manifest"
import os, sys, tomllib
root = sys.argv[1]
m = tomllib.load(open(os.path.join(root, "herdr-plugin.toml"), "rb"))
assert m["id"] == "opsx-board", m["id"]
a = [x for x in m["actions"] if x["id"] == "open-board"]; assert a, m["actions"]
assert os.path.exists(os.path.join(root, a[0]["command"][-1])), a[0]["command"]
b = [x for x in m["actions"] if x["id"] == "open-pane"]; assert b, m["actions"]
assert os.path.exists(os.path.join(root, b[0]["command"][-1])), b[0]["command"]
p = [x for x in m["panes"] if x["id"] == "board"]; assert p, m["panes"]
assert p[0]["placement"] == "overlay", p[0]
assert os.path.exists(os.path.join(root, p[0]["command"][-1])), p[0]["command"]
PY

# --- open-pane.sh：只叫 herdr 開 overlay pane，用 HERDR_BIN_PATH 給的 herdr ---
: > "$OPSX_FAKE_LOG"
out="$(HERDR_BIN_PATH="$FX/fakebin/herdr" bash "$OPSX_ROOT/herdr-board/scripts/open-pane.sh" 2>&1)"; assert_eq "$?" 0 "open-pane: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "plugin pane open --plugin opsx-board --entrypoint board --placement overlay --focus" "open-pane 的 herdr 呼叫"
: > "$OPSX_FAKE_LOG"

# --- open-board.sh：第一次起 server + 開瀏覽器；第二次只開瀏覽器 ---
port=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
export OPSX_BOARD_PORT="$port" HERDR_PANE_ID=p1 HERDR_TAB_ID=t1 HERDR_WORKSPACE_ID=w1
out="$(bash "$OPSX_ROOT/herdr-board/scripts/open-board.sh" 2>&1)"; rc=$?; assert_eq "$rc" 0 "open-board 第一次: $out"
assert_file "$OPSX_STATE_DIR/board.pid"; pid1="$(cat "$OPSX_STATE_DIR/board.pid")"
kill -0 "$pid1" || fail "server 沒在跑（pid ${pid1}）"
tok="$(cat "$OPSX_STATE_DIR/board-token")"
assert_grep "http://127.0.0.1:$port/#token=$tok" "$FX/open.log"   # fragment，不進 log / Referer
curl -sf "http://127.0.0.1:$port/healthz" | grep -q '"app": *"opsx-board"' || fail "healthz 要說自己是 opsx-board"
curl -sf "http://127.0.0.1:$port/healthz" >/dev/null || fail "healthz 不通"
out="$(bash "$OPSX_ROOT/herdr-board/scripts/open-board.sh" 2>&1)"; assert_eq "$?" 0 "open-board 第二次: $out"
assert_eq "$(cat "$OPSX_STATE_DIR/board.pid")" "$pid1" "第二次不該換 pid"
assert_eq "$(grep -c '^open ' "$FX/open.log" || true)" 2 "兩次都要開瀏覽器"
assert_eq "$(grep -c '^listening' "$OPSX_STATE_DIR/board.log" || true)" 1 "只該起過一支 server（沙盒不能 pgrep，數 log 的 listening 行）"
# --- token 檔被刪 → 下一次 open-board 重起 server，新 token ---
rm -f "$OPSX_STATE_DIR/board-token"
out="$(bash "$OPSX_ROOT/herdr-board/scripts/open-board.sh" 2>&1)"; assert_eq "$?" 0 "open-board 第三次: $out"
[ "$(cat "$OPSX_STATE_DIR/board.pid")" != "$pid1" ] || fail "token 不見了要重起 server"
assert_file "$OPSX_STATE_DIR/board-token"
# --- opsx stop --board 關掉它 ---
pid2="$(cat "$OPSX_STATE_DIR/board.pid")"
out="$(opsx stop --board 2>&1)"; assert_eq "$?" 0 "stop --board: $out"
sleep 0.3; kill -0 "$pid2" 2>/dev/null && fail "stop --board 後 server 還活著"
assert_no_file "$OPSX_STATE_DIR/board.pid"
out="$(opsx stop --board 2>&1)"; assert_eq "$?" 0 "stop --board 第二次要是 no-op: $out"

# --- init --global 做 herdr plugin link（herdr 在 PATH 上才做；已掛就不再 link）---
out="$(opsx init --global 2>&1)"; assert_eq "$?" 0 "init --global: $out"
assert_grep "^plugin link $OPSX_ROOT\$" "$OPSX_FAKE_LOG"
printf '[{"plugin_id":"opsx-board"}]\n' > "$FX/plugin-list.json"; export OPSX_TEST_HERDR_PLUGINS="$FX/plugin-list.json"; : > "$OPSX_FAKE_LOG"
out="$(opsx init --global 2>&1)"; assert_eq "$?" 0; echo "$out" | grep -q '已掛' || fail "已掛要說已掛: $out
log: $(cat "$OPSX_FAKE_LOG")"; assert_not_grep '^plugin link' "$OPSX_FAKE_LOG"
echo ok
