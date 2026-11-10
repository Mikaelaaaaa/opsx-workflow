#!/usr/bin/env bash
# 第二級授權動作的合法值只有 grantactions.py 一份；閘門 hook 的 level2 呼叫要與它一致。
# 驗收：specs/grant-action/spec.md（第二級授權動作的合法值只有一份定義）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
HOOK="$OPSX_ROOT/hooks/opsx-grant-gate.sh"

# 每個 level2 呼叫的第一個字；函式定義是 level2() {，後面沒有空白，不會被抽到
calls_of() { grep -oE 'level2 +[^ (]+' "$1" | awk '{print $2}'; }
# 不是純小寫字母的動作字（連字號、數字、變數、引號），代表這份檢查看不懂那個呼叫
bad_calls_of() { calls_of "$1" | grep -vE '^[a-z]+$' || true; }

hook_actions="$(calls_of "$HOOK" | sort -u | tr '\n' ' ')"
[ -n "$hook_actions" ] || fail "hook 裡抽不到任何 level2 呼叫"
case " $hook_actions" in *" env "*) ;; *) fail "抽到的動作要含 env：$hook_actions" ;; esac
assert_eq "$(bad_calls_of "$HOOK")" "" "hook 裡每個 level2 動作都要是純小寫字母"

py_actions="$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import grantactions
print(" ".join(sorted(grantactions.ACTIONS)))')"
assert_eq "${hook_actions% }" "$py_actions" "hook 的 level2 動作集合要等於 grantactions.ACTIONS"
assert_eq "$(printf '%s' "$py_actions" | wc -w | tr -d ' ')" 8 "八個動作"

# 抽取要抓得到壞呼叫：帶連字號、數字、變數的動作字，不能被默默略過
BAD="$FX/hook-bad.sh"; cp "$HOOK" "$BAD"
printf 'level2 db-seed "seed"\nlevel2 npm2 "x"\nlevel2 "$act" "dyn"\n' >> "$BAD"
assert_eq "$(bad_calls_of "$BAD" | wc -l | tr -d ' ')" 3 "三個壞呼叫都要被抓到"

# 抽屜的授權按鈕要看 waiting.options 才畫：沒有授權選項的 gate（merge、表外 action）不能出現必失敗的按鈕
WEB="$OPSX_ROOT/herdr-board/web/index.html"
for opt in '這次' '這張卡' '這個 repo 永遠'; do
  grep -qF "has('${opt}')" "$WEB" || fail "抽屜的授權按鈕要依 options 含「${opt}」才畫"
done
grep -qF "w.action==='merge'" "$WEB" && fail "抽屜不該再用 action==='merge' 決定按鈕，改看 options"
echo ok
