#!/usr/bin/env bash
# gate type 的同義詞表：整值全等、去前後空白、英文不分大小寫；表外與沒寫都是 None。
# 驗收：specs/gate-type/spec.md（gate type 只有兩個合法值）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

norm() { # <raw> → normalize 的結果（None 印成 None）
  OPSX_RAW="$1" OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import gatetype
print(gatetype.normalize(os.environ["OPSX_RAW"]))'
}

assert_eq "$(norm approval)" approval
assert_eq "$(norm decision)" decision
assert_eq "$(norm authorization)" approval "同義詞 authorization"
assert_eq "$(norm 授權)" approval
assert_eq "$(norm 等待授權)" approval
assert_eq "$(norm 等待決定)" decision
assert_eq "$(norm 決定)" decision
assert_eq "$(norm '  Approval  ')" approval "去前後空白、英文不分大小寫"
assert_eq "$(norm approval-ish)" None "看起來像但不在表內"
assert_eq "$(norm 'approval decision')" None "不做子字串比對"
assert_eq "$(norm '')" None "沒寫 type"
echo ok
