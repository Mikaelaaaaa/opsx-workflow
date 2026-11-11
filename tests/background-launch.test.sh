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

# 程式碼裡不能有 nohup 呼叫（註解不算）
sites="$(grep -rInwE '^[^#]*nohup' "$OPSX_ROOT/bin" "$OPSX_ROOT/hooks" "$OPSX_ROOT/herdr-board" --exclude-dir=tests || true)"
[ -z "$sites" ] || fail "這些地方還在用 nohup：
$sites"
echo ok
