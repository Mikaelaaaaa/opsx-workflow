#!/usr/bin/env bash
# opsx stack <主> <子> <sha>：在主 change 的 PR 分支上 cherry-pick 子 change 的 commit，成功就勾主殼 tasks.md 那一項（以反引號包的子 change 名對到）。
# 退出 0 疊好；2 拒絕（不在 PR 分支、依賴還沒疊、sha 或子 change 不對），歷史不動；
# 3 衝突：已 cherry-pick --abort，主殼 decisions.tsv 記一行，session 在 PR 分支上自己重做這個子 change。
# 不在衝突標記上手解：subagent 的測試是在舊基底上綠的。驗收：specs/subchange-stack/spec.md。

opsx_stack() {
  [ $# -eq 3 ] || die "stack: 用法 opsx stack <主> <子> <sha>"
  local main="$1" sub="$2" sha="$3" top
  top="$(git_toplevel)"
  [ -n "$top" ] || die "stack: 不在 git repo 裡"
  local d="$top/openspec/changes/$main"
  [ -f "$d/tasks.md" ] || die "stack: 主殼沒有 tasks.md：$d"
  local branch; branch="$(wp_pr_field "$top" "$main" branch)"
  [ -n "$branch" ] || die "stack: workplan 沒有主 change $main 的 branch"
  [ "$(git_branch)" = "$branch" ] || die "stack: 要在 PR 分支 $branch 上跑，現在在 $(git_branch)"

  local deps dep missing=""
  deps="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/chain.py" deps "$top" "$main" "$sub")" || exit 2
  for dep in $deps; do
    task_line "$d/tasks.md" "$dep" '\[x\]' || missing="$missing $dep"
  done
  [ -z "$missing" ] || die "stack: $sub 依賴的子 change 還沒疊回：${missing# }"
  task_line "$d/tasks.md" "$sub" '\[ \]' || die "stack: 主殼 tasks.md 沒有未勾的「\`$sub\`」那一項"
  git cat-file -e "$sha^{commit}" 2>/dev/null || die "stack: 沒有這個 commit：$sha"
  [ -z "$(git status --porcelain)" ] || die "stack: $branch 有未 commit 的改動，先收乾淨再疊"

  if ! git cherry-pick "$sha" >/dev/null 2>&1; then
    local conflicts; conflicts="$(git diff --name-only --diff-filter=U | tr '\n' ' ')"
    git cherry-pick --abort >/dev/null 2>&1 || true
    [ -n "$conflicts" ] || die "stack: cherry-pick $sha 失敗，不是衝突（空 commit 或 git 錯誤）；歷史沒動"
    log_row "$d" session 已決定 "$sub 疊回衝突，改由 session 在 PR 分支重做" "衝突檔：${conflicts% }；$sha"
    say "stack: ${sub} 疊回衝突（${conflicts% }），已 abort；在 ${branch} 上自己重做 ${sub}"
    exit 3
  fi

  local tmp="$d/tasks.md.stack.tmp"
  awk -v s="\`$sub\`" '!done && /^[[:space:]]*- \[ \] / && index($0, s) { sub(/- \[ \] /, "- [x] "); done = 1 } { print }' "$d/tasks.md" > "$tmp" && mv "$tmp" "$d/tasks.md"
  say "stack: ${sub} 疊回 ${branch}（$(git rev-parse --short HEAD)），主殼 tasks.md 已勾"
}

task_line() { # <tasks.md> <子> <勾的樣子，regex>：有這個子 change 的那一項而且是這個勾法
  grep -qE "^[[:space:]]*- $3 .*\`$2\`" "$1"
}
