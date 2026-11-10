#!/usr/bin/env bash
# 第二級授權動作的合法值只有 grantactions.py 一份；閘門 hook 的 level2 呼叫要與它一致。
# 驗收：specs/grant-action/spec.md（第二級授權動作的合法值只有一份定義）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# level2 <動作> "<label>" 的呼叫；函式定義是 level2() {，不會被抽到
hook_actions="$(grep -oE 'level2 [a-z]+ "' "$OPSX_ROOT/hooks/opsx-grant-gate.sh" | cut -d' ' -f2 | sort -u | tr '\n' ' ')"
[ -n "$hook_actions" ] || fail "hook 裡抽不到任何 level2 呼叫"
case " $hook_actions" in *" env "*) ;; *) fail "抽到的動作要含 env：$hook_actions" ;; esac

py_actions="$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import grantactions
print(" ".join(sorted(grantactions.ACTIONS)))')"
assert_eq "${hook_actions% }" "$py_actions" "hook 的 level2 動作集合要等於 grantactions.ACTIONS"
assert_eq "$(printf '%s' "$py_actions" | wc -w | tr -d ' ')" 8 "八個動作"
echo ok
