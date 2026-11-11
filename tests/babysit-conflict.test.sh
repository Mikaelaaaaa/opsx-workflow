#!/usr/bin/env bash
# babysit 遇到衝突與 stale base 自己把 main 合進 PR 分支解，只有語意矛盾才開 gate。
# 對應 babysit-merge-main 的 specs/babysit-conflict-resolve（「上游紀錄」由 upstream-note 子 change 測）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SKILL="$OPSX_ROOT/skills/babysit/SKILL.md"
assert_file "$SKILL"
# 每一步在 SKILL.md 裡是一行，拆成單獨的檔案，斷言才落在對的那一步
grep '^1\. ' "$SKILL" > "$FX/step1"
grep '^5\. ' "$SKILL" > "$FX/step5"
grep '^7\. ' "$SKILL" > "$FX/step7"
grep '^10\. ' "$SKILL" > "$FX/step10"

# 衝突自己合 main 解
assert_grep "git fetch" "$FX/step5"
assert_grep "git merge origin/main" "$FX/step5"
assert_not_grep "report rather than resolve" "$SKILL"
assert_not_grep "Say which branch needs the rebase" "$SKILL"
assert_grep "commits and pushes" "$FX/step1"
# 步 4 不 rebase、不 force-push 保留
assert_grep "No base retarget, rebase, stack-wide submit, or force-push" "$SKILL"

# 禁止整檔取一邊
assert_grep "hunk by hunk" "$FX/step5"
assert_grep "git checkout --ours" "$FX/step5"
assert_grep "\-\-theirs" "$FX/step5"

# 合併收尾不開編輯器
assert_grep "git commit --no-edit" "$FX/step5"

# 推送不帶參數：說明原因、沒授權寫 gate、UNKNOWN 不輪詢
assert_grep "bare \`git push\`" "$FX/step5"
assert_grep "\-main" "$FX/step5"
assert_grep "push to main" "$FX/step5"
assert_grep "level-two" "$FX/step5"
assert_grep "UNKNOWN" "$FX/step5"
assert_grep "do not poll" "$FX/step5"

# 語意矛盾才開 gate
assert_grep "only when the two sides contradict each other" "$FX/step5"

# 合併後轉紅補 commit
assert_grep "turns red" "$FX/step5"
assert_grep "red-first" "$FX/step5"
assert_grep "push only when the full suite is green" "$FX/step5"

# stale base 合 main
assert_grep "git merge-base --is-ancestor" "$FX/step7"
assert_grep "merge main as in step 5" "$FX/step7"
assert_not_grep "needing a rebase" "$SKILL"

# merge 模式衝突寫 gate
assert_grep "conflict" "$FX/step10"
assert_grep "run babysit to resolve the conflict" "$FX/step10"
assert_grep "press merge again" "$FX/step10"
