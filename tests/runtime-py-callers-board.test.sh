#!/usr/bin/env bash
# 看板 server 與 TUI 的 herdr argv 由 bin/lib/runtime.py 產生，原始碼只留 pane zoom 一處直接寫。
# 驗收：specs/agent-runtime/spec.md「原始碼不直接寫 herdr argv」（看板）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCAN="$OPSX_ROOT/tests/herdr_argv_scan.py"
# runtime-module D3：zoom 沒有對象，不經 runtime。比對字面值內容，不比行號
ALLOWED="['herdr', 'pane', 'zoom', '--current', '--toggle']"

# --- 掃描器本身 ---
T="$FX/scan"; mkdir -p "$T"
printf '%s\n' 'r = run(["herdr", "agent", "read", pane], 10, env)' > "$T/bad.py"
printf '%s\n' 'return [ "herdr" , "agent", "focus", name]' > "$T/spaced.py"
printf '%s\n' "r = run(['herdr', 'agent', 'read', pane])" > "$T/single.py"
printf '%s\n' 'argv = [' '    "herdr", "agent", "focus", name]' > "$T/multiline.py"
printf '%s\n' 'argv = ("herdr", "agent", "focus", name)' > "$T/tuple.py"
printf '%s\n' 'ZOOM_ARGV = ["herdr", "pane", "zoom", "--current", "--toggle"]' 'argv = runtime.focus(agent=name)' > "$T/ok.py"
[ -n "$(python3 -I "$SCAN" "$T/bad.py")" ] || fail "掃描器抓不到 [\"herdr\", …]"
[ -n "$(python3 -I "$SCAN" "$T/spaced.py")" ] || fail "掃描器抓不到帶空白的 [ \"herdr\" , …]"
[ -n "$(python3 -I "$SCAN" "$T/single.py")" ] || fail "掃描器抓不到單引號 ['herdr', …]"
[ -n "$(python3 -I "$SCAN" "$T/multiline.py")" ] || fail "掃描器抓不到跨行的 list"
[ -n "$(python3 -I "$SCAN" "$T/tuple.py")" ] || fail "掃描器抓不到 tuple"
assert_eq "$(python3 -I "$SCAN" "$T/ok.py" | grep -vcF -- "$ALLOWED" || true)" 0 "掃描器誤報 runtime 呼叫"

# --- 真實檔案 ---
python3 -I "$SCAN" "$OPSX_ROOT/herdr-board/server.py" "$OPSX_ROOT/herdr-board/tui_model.py" > "$FX/hits"
assert_eq "$(grep -cF -- "$ALLOWED" "$FX/hits" || true)" 1 "tui_model.py 的 ZOOM_ARGV 要留著直接寫：$(cat "$FX/hits")"
assert_eq "$(grep -vcF -- "$ALLOWED" "$FX/hits" || true)" 0 "看板還有直接寫的 herdr argv，改用 bin/lib/runtime.py：$(cat "$FX/hits")"

echo "ok runtime-py-callers-board"
