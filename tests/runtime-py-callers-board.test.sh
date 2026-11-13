#!/usr/bin/env bash
# 看板 server 與 TUI 的 herdr argv 由 bin/lib/runtime.py 產生，原始碼只留 tui_model.py 的 pane zoom 一處直接寫。
# 驗收：specs/agent-runtime/spec.md「原始碼不直接寫 herdr argv」（看板）
# 掃描器本身的自測在 tests/runtime-py-callers.test.sh。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCAN="$OPSX_ROOT/tests/herdr_argv_scan.py"
# runtime-module D3：zoom 沒有對象，不經 runtime。比對檔名與字面值內容，不比行號
ALLOW="tui_model.py=['herdr', 'pane', 'zoom', '--current', '--toggle']"

# tui.py 跑 subprocess，tui_model.py 產生 argv，兩個都算 TUI
python3 -I "$SCAN" --allow "$ALLOW" "$OPSX_ROOT/herdr-board/server.py" "$OPSX_ROOT/herdr-board/tui_model.py" "$OPSX_ROOT/herdr-board/tui.py" > "$FX/out" 2>&1 \
  || fail "看板只准 tui_model.py 的 ZOOM_ARGV 直接寫 herdr argv，其他改用 bin/lib/runtime.py：$(cat "$FX/out")"

echo "ok runtime-py-callers-board"
