#!/usr/bin/env bash
# skills/babysit/SKILL.md：threads-only 的 push wave 之後、回覆之前照 pr 步 5c 重產邏輯表並編輯同一則留言；
# check、merge 與沒 push 的輪次不重產。skill 是文字，只能檢查 skill 寫了什麼。對應 openspec/changes/pr-logic-map/specs/pr-logic-map。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/babysit/SKILL.md"
assert_file "$SK"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }

# 步 8 一段：從 `8. ` 那行到 `9. ` 那行之前
STEP="$FX/step8"
awk '/^8\. /{on=1} /^9\. /{on=0} on' "$SK" > "$STEP"
[ -s "$STEP" ] || fail "skills/babysit/SKILL.md 沒有步 8"

# --- 重產照 pr 步 5c，不複製指令；編輯 report.md 記的那則 ---
assert_fixed '../pr/SKILL.md' "$STEP"
assert_fixed 'step 5c' "$STEP"
assert_fixed '## 邏輯表' "$STEP"
assert_fixed 'openspec/changes/<slug>/logic-map.md' "$STEP"
! grep -qF 'gh pr comment' "$STEP" || fail "babysit 複製了 5c 的指令"

# --- 順序：push wave 之後、回覆之前 ---
python3 -I - "$STEP" <<'PY' || fail "重產不在 push wave 與回覆之間"
import sys
text = open(sys.argv[1], encoding="utf-8").read()
push = text.index("Push that wave")
regen = text.index("regenerate the logic map")
reply = text.index("On GitLab, reply")
if not push < regen < reply:
    sys.exit("順序：push=%d regen=%d reply=%d" % (push, regen, reply))
PY

# --- 沒有 ## 邏輯表 時走新開 ---
assert_fixed 'no `## 邏輯表` line' "$STEP"
assert_fixed 'post a new comment' "$STEP"

# --- 不重產的情況（Scenario「沒有 push 不重產」）---
assert_fixed 'Only a `threads-only` run that pushed' "$STEP"
for k in '`check`' '`merge <sha>`' 'did not push'; do
  grep -F 'never regenerate it' "$STEP" | grep -qF -- "$k" || fail "不重產清單缺 $k"
done
