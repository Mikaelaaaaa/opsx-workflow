#!/usr/bin/env bash
# babysit 遇到衝突與 stale base 自己把 main 合進 PR 分支解，只有語意矛盾才開 gate。
# 對應 babysit-merge-main 的 specs/babysit-conflict-resolve。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SKILL="$OPSX_ROOT/skills/babysit/SKILL.md"
assert_file "$SKILL"
# 每一步在 SKILL.md 裡是一行，拆成單獨的檔案，斷言才落在對的那一步
grep '^1\. ' "$SKILL" > "$FX/step1"
grep '^5\. ' "$SKILL" > "$FX/step5"
grep '^7\. ' "$SKILL" > "$FX/step7"
grep '^10\. ' "$SKILL" > "$FX/step10"

# 衝突自己合 main 解
assert_grep "git fetch <remote>" "$FX/step5"
assert_grep "git merge <remote>/main" "$FX/step5"
# gitlab 為主的 repo 裡 origin 只是鏡像，remote 照 pr 步 1 選
assert_not_grep "origin/main" "$FX/step5"
assert_grep "the way the \`pr\` skill's step 1 does" "$FX/step5"
assert_grep "\`gitlab\`" "$FX/step5"
assert_not_grep "report rather than resolve" "$SKILL"
assert_not_grep "Say which branch needs the rebase" "$SKILL"
assert_grep "commits and pushes" "$FX/step1"
# 步 4 不 rebase、不 force-push 保留
assert_grep "No base retarget, rebase, stack-wide submit, or force-push" "$SKILL"

# 禁止整檔取一邊
assert_grep "hunk by hunk" "$FX/step5"
assert_grep "Never settle a file with \`git checkout --ours\` or \`git checkout --theirs\`" "$FX/step5"

# 合併收尾不開編輯器；沒衝突時 git merge 已經自己 commit，不再收尾
assert_grep "finish the merge with \`git commit --no-edit\`" "$FX/step5"
assert_grep "the merge has already committed itself" "$FX/step5"

# 推送：有 upstream 不帶參數，沒有就 -u；閘門只認 refspec 目標，不再拿分支名當理由
assert_grep "\`git push\` when the branch has an upstream" "$FX/step5"
assert_grep "\`git push -u <remote> <branch>\` when it has none" "$FX/step5"
assert_not_grep "misread" "$FX/step5"
assert_grep "level-two" "$FX/step5"
assert_grep "UNKNOWN" "$FX/step5"
assert_grep "do not poll" "$FX/step5"

# 語意矛盾才開 gate
assert_grep "only when the two sides contradict each other" "$FX/step5"

# 合併後轉紅補 commit
assert_grep "red-first" "$FX/step5"
# 有衝突跟沒衝突兩條路都要全套綠才推
assert_grep "Whether or not git reported a conflict, push only when the full suite is green" "$FX/step5"

# stale base 合 main
assert_grep "git merge-base --is-ancestor" "$FX/step7"
assert_grep "merge main as in step 5" "$FX/step7"
assert_not_grep "needing a rebase" "$SKILL"

# merge 模式衝突寫 gate
assert_grep "do not resolve it in this mode" "$FX/step10"
assert_grep "run babysit to resolve the conflict" "$FX/step10"
assert_grep "press merge again" "$FX/step10"

# 上游紀錄：UPSTREAM.md 的 babysit 那一列記下合 main
grep '^| `skills/babysit/SKILL.md`' "$OPSX_ROOT/UPSTREAM.md" > "$FX/upstream_row"
assert_grep "合 main" "$FX/upstream_row"
