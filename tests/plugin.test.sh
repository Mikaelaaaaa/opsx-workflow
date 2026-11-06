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
assert p[0]["placement"] == "split", p[0]
assert p[0]["title"] == "opsx", p[0]   # open-pane.sh 靠這個 label 認出已開的看板 pane
assert os.path.exists(os.path.join(root, p[0]["command"][-1])), p[0]["command"]
PY

# --- open-pane.sh：本 tab 沒有看板 pane 就在按鍵的 pane 右邊開 split，有就 focus 它 ---
panes() { # panes <tab_id 有 opsx pane 的 tab>：寫一份 herdr pane list，w1:t1 有按鍵的 pane w1:p2
  printf '{"id":"cli:pane:list","result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t1","workspace_id":"w1"},{"label":"tsk","pane_id":"w1:p5","tab_id":"w1:t1","workspace_id":"w1"},{"label":"opsx","pane_id":"w1:p7","tab_id":"%s","workspace_id":"w1"}],"type":"pane_list"}}\n' "$1" > "$FX/panes.json"
}
open_pane() { HERDR_BIN_PATH="$FX/fakebin/herdr" HERDR_PANE_ID=w1:p2 HERDR_TAB_ID=w1:t1 HERDR_WORKSPACE_ID=w1 OPSX_TEST_HERDR_PANES="$FX/panes.json" bash "$OPSX_ROOT/herdr-board/scripts/open-pane.sh" 2>&1; }
SPLIT="plugin pane open --plugin opsx-board --entrypoint board --placement split --direction right --target-pane w1:p2 --focus"

panes w1:t9; : > "$OPSX_FAKE_LOG"   # 看板 pane 只在別的 tab
out="$(open_pane)"; assert_eq "$?" 0 "open-pane 沒開過: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "pane list --workspace w1
$SPLIT" "本 tab 沒有看板 pane：開 split"

panes w1:t1; : > "$OPSX_FAKE_LOG"
out="$(open_pane)"; assert_eq "$?" 0 "open-pane 已開: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "pane list --workspace w1
plugin pane focus w1:p7" "本 tab 已有看板 pane：只 focus"

for v in HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID; do
  : > "$OPSX_FAKE_LOG"
  out="$(HERDR_BIN_PATH="$FX/fakebin/herdr" HERDR_PANE_ID=w1:p2 HERDR_TAB_ID=w1:t1 HERDR_WORKSPACE_ID=w1 env -u "$v" bash "$OPSX_ROOT/herdr-board/scripts/open-pane.sh" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || fail "缺 $v 要失敗"
  echo "$out" | grep -q "$v" || fail "缺 $v 的錯誤要寫出變數名: $out"
  assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "缺 $v 不該叫 herdr"
done
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
