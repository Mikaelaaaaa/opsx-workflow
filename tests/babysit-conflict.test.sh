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
# 只有 check 合 main；threads-only 照步 1 什麼都不動
assert_grep "In \`check\` mode, resolve a conflict yourself" "$FX/step5"
assert_grep "in \`threads-only\` mode, report the conflict and leave the branch alone" "$FX/step5"
# gitlab 為主的 repo 裡 origin 只是鏡像，remote 照 pr 步 1 選
assert_not_grep "origin/main" "$FX/step5"
assert_grep "the way the \`pr\` skill's step 1 does" "$FX/step5"
assert_grep "\`gitlab\` in Agentory-AI and Agentory-Infrastructure, where \`origin\` is only a mirror" "$FX/step5"
assert_not_grep "report rather than resolve" "$SKILL"
assert_not_grep "Say which branch needs the rebase" "$SKILL"
assert_grep "commits and pushes" "$FX/step1"
# 步 4 不 rebase、不 force-push 保留
assert_grep "No base retarget, rebase, stack-wide submit, or force-push" "$SKILL"

# 禁止整檔取一邊
assert_grep "hunk by hunk" "$FX/step5"
assert_grep "Never settle a file with \`git checkout --ours\` or \`git checkout --theirs\`" "$FX/step5"

# 合併收尾不開編輯器，只在有衝突時收尾；沒衝突時 git merge 已經自己 commit
assert_grep "When git reports a conflict, resolve the conflict markers hunk by hunk" "$FX/step5"
assert_grep "stage each resolved file by name and finish the merge with \`git commit --no-edit\`" "$FX/step5"
assert_grep "when git reports no conflict, the merge has already committed itself and there is nothing to finish" "$FX/step5"

# 推送：有 upstream 不帶參數，沒有就 -u；沒授權寫 gate；UNKNOWN 照實回報不輪詢
assert_grep "\`git push\` when the branch has an upstream" "$FX/step5"
assert_grep "\`git push -u <remote> <branch>\` when it has none" "$FX/step5"
assert_grep "A push without a grant is a level-two action, so write a gate for it" "$FX/step5"
assert_grep "when GitHub reports mergeable as \`UNKNOWN\` right after the push, report it as it is and do not poll" "$FX/step5"

# 語意矛盾才開 gate
assert_grep "only when the two sides contradict each other" "$FX/step5"

# 合併後轉紅：只補合併本身弄紅的；main 上也紅、相依套件或環境的錯、補不綠都寫 gate
assert_grep "first run the failing test on \`<remote>/main\` alone" "$FX/step5"
assert_grep "only a failure the merge itself caused gets aligning commits on the branch, each with red-first evidence" "$FX/step5"
assert_grep "When the test also fails on \`<remote>/main\`, when the failure comes from a dependency or the environment, or when the suite is still red after aligning, write a gate" "$FX/step5"
assert_grep "the merge commit stays local and unpushed" "$FX/step5"
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
