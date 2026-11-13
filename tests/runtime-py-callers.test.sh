#!/usr/bin/env bash
# 協調者與 reap 的 herdr argv 由 runtime.py 產生：原始碼裡以 "herdr" 開頭的 list 或 tuple 字面值只剩 pane process-info 一處。
# 驗收：openspec/changes/runtime-py-callers/subs/runtime-coordinate/specs/agent-runtime/spec.md「原始碼不直接寫 herdr argv」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCAN="$OPSX_ROOT/tests/herdr_argv_scan.py"
# runtime-module D3：process-info 是 herdr 專屬，留著直接呼叫。比對字面值內容，不比行號
ALLOWED="['herdr', 'pane', 'process-info', '--pane', pane]"

# --- 掃描器本身 ---
T="$FX/scan"; mkdir -p "$T"
printf '%s\n' "r = run(['herdr', 'agent', 'read', pane])" > "$T/single.py"
printf '%s\n' 'argv = [' '    "herdr", "pane", "close", pane]' > "$T/multiline.py"
printf '%s\n' 'argv = ("herdr", "agent", "prompt", name, text)' > "$T/tuple.py"
printf '%s\n' 'herdr = [e for e in errs if e["source"] == "herdr"]' 'x = runtime.prompt(text, agent=name)' > "$T/ok.py"
[ -n "$(python3 -I "$SCAN" "$T/single.py")" ] || fail "掃描器抓不到單引號 ['herdr', …]"
[ -n "$(python3 -I "$SCAN" "$T/multiline.py")" ] || fail "掃描器抓不到跨行的 list"
[ -n "$(python3 -I "$SCAN" "$T/tuple.py")" ] || fail "掃描器抓不到 tuple"
assert_eq "$(python3 -I "$SCAN" "$T/ok.py")" "" "掃描器把 == \"herdr\" 或 runtime 呼叫當成 argv"

# --- 真實檔案 ---
python3 -I "$SCAN" "$OPSX_ROOT/bin/lib/coordinate.py" "$OPSX_ROOT/bin/lib/reap.py" > "$FX/hits"
assert_eq "$(grep -cF -- "$ALLOWED" "$FX/hits" || true)" 1 "coordinate.py 的 pane process-info 要留著直接呼叫：$(cat "$FX/hits")"
assert_eq "$(grep -vcF -- "$ALLOWED" "$FX/hits" || true)" 0 "只准 pane process-info 直接寫 herdr argv：$(cat "$FX/hits")"

echo "ok runtime-py-callers"
