#!/usr/bin/env bash
# 看板 server 與 TUI 的 herdr argv 由 bin/lib/runtime.py 產生，原始碼只留 pane zoom 一處直接寫。
# 驗收：specs/agent-runtime/spec.md「原始碼不直接寫 herdr argv」（看板）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# runtime-module D3：zoom 沒有對象，不經 runtime。比對行內容，不比行號
ALLOWED='ZOOM_ARGV = ["herdr", "pane", "zoom", "--current", "--toggle"]'

herdr_argv_hits() { # <file>
  grep -nE -- '\[[[:space:]]*"herdr"[[:space:]]*,' "$1" | grep -vF -- "$ALLOWED" || true
}

# --- 掃描器本身 ---
T="$FX/scan"; mkdir -p "$T"
printf '%s\n' 'r = run(["herdr", "agent", "read", pane], 10, env)' > "$T/bad.py"
printf '%s\n' 'return [ "herdr" , "agent", "focus", name]' > "$T/spaced.py"
printf '%s\n' "$ALLOWED" 'argv = runtime.focus(agent=name)' > "$T/ok.py"
[ -n "$(herdr_argv_hits "$T/bad.py")" ] || fail "掃描器抓不到 [\"herdr\", …]"
[ -n "$(herdr_argv_hits "$T/spaced.py")" ] || fail "掃描器抓不到帶空白的 [ \"herdr\" , …]"
[ -z "$(herdr_argv_hits "$T/ok.py")" ] || fail "掃描器誤報 ZOOM_ARGV 或 runtime 呼叫: $(herdr_argv_hits "$T/ok.py")"

# --- 真實檔案 ---
bad=""
for f in herdr-board/server.py herdr-board/tui_model.py; do
  h="$(herdr_argv_hits "$OPSX_ROOT/$f")"; [ -z "$h" ] || bad+="$f:
$h
"
done
[ -z "$bad" ] || fail "看板還有直接寫的 herdr argv，改用 bin/lib/runtime.py：
$bad"
grep -qF -- "$ALLOWED" "$OPSX_ROOT/herdr-board/tui_model.py" || fail "tui_model.py 找不到 ZOOM_ARGV 那一行"
