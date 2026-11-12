#!/usr/bin/env bash
# 起背景程序不能靠 nohup（agent 沙盒的 pane 裡它一律失敗）。
# 驗收：specs/background-launch/spec.md
# 四個呼叫點的行為（drive、coordinate kick、board server、hook 起 drive）由 dispatch、coordinate、plugin、hooks 測試驗：
# lib.sh 讓每個測試的 PATH 最前面都是一律失敗的 tests/fakes/nohup，呼叫點只要還用 nohup，走到它的測試就紅。
# 這支驗假 nohup 本身，並掃那些測試走不到的呼叫點。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# lib.sh 把假 nohup 放在 PATH 最前面，且一律失敗
assert_eq "$(command -v nohup)" "$FX/failbin/nohup" "測試裡的 nohup 要是假的"
out="$(nohup true 2>&1)"; rc=$?
assert_eq "$rc" 1 "假 nohup 要失敗"
assert_eq "$out" "nohup: can't detach from console"

# 程式碼裡不能有 nohup 呼叫（註解不算）。
# bin/lib/cmdsegments.py 不在內：它只解析指令字串，把 nohup 當前綴剝掉，閘門才認得 `nohup git push origin main`，不起程序。
nohup_sites() { # <根目錄>
  grep -rInwE '^[^#]*nohup' "$1/bin" "$1/hooks" "$1/herdr-board" --exclude-dir=tests | grep -vF "$1/bin/lib/cmdsegments.py:" || true
}

# 排除只有 cmdsegments.py 一個檔：別的檔案新增 nohup 呼叫，掃描要紅，而且不指 cmdsegments.py
SCAN_FX="$FX/scan"; mkdir -p "$SCAN_FX/bin/lib" "$SCAN_FX/hooks" "$SCAN_FX/herdr-board"
printf 'COMMAND_PREFIXES = ("exec", "nohup")\n' > "$SCAN_FX/bin/lib/cmdsegments.py"
assert_eq "$(nohup_sites "$SCAN_FX")" "" "只有 cmdsegments.py 含 nohup：掃描要過"
printf 'nohup drive >> log 2>&1 &\n' > "$SCAN_FX/bin/other.sh"
fixture_hits="$(nohup_sites "$SCAN_FX")"
case "$fixture_hits" in *"bin/other.sh:1:"*) ;; *) fail "別的檔案的 nohup 呼叫要被掃到：$fixture_hits" ;; esac
case "$fixture_hits" in *cmdsegments*) fail "掃描不該指 cmdsegments.py：$fixture_hits" ;; esac

sites="$(nohup_sites "$OPSX_ROOT")"
[ -z "$sites" ] || fail "這些地方還在用 nohup：
$sites"
echo ok
