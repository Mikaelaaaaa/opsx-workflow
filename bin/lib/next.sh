#!/usr/bin/env bash
# opsx next：feature session（opsx dispatch --feature）的主 change 開了 MR、停在等合併時，
# 印同 feature 下一個還沒開 MR 的主 change 該跑的指令 `/<stage> <主>`；沒有、或不在 session 的 worktree 裡，印 none。
# session 由所在 worktree 名找（<top>/.claude/worktrees/<feature> 對 dispatch.json 的 <repo>/@<feature>），不解析 branch：
# 舊形 PR 的 branch 第二段是 PR 名，對不到卡。推法同 hooks/_lib.sh 的 wt_name。
# references/continue.md 的 babysit 那一站叫它。驗收：specs/session-dispatch/spec.md「session 做完一個主 change 接下一個」。

opsx_next() {
  [ $# -eq 0 ] || die "next: 用法 opsx next（在 feature session 的 worktree 裡跑）"
  local top wt feature repo
  top="$(git_toplevel)"
  [ -n "$top" ] || die "next: 不在 git repo 裡"
  wt="$(cd "$(git_worktree_top)" && pwd -P)"
  [ "${wt%/*}" = "$top/.claude/worktrees" ] || { say none; return 0; }
  feature="${wt##*/}"
  repo="$(basename "$top")"
  local cards c stage
  cards="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/chain.py" siblings "$top" "$repo" "$feature" "$OPSX_STATE_DIR/dispatch.json")" || exit 2
  for c in $cards; do
    stage="$(stage_name "$top" "$c")"
    case "$stage" in babysit|archive|split) continue ;; esac
    say "/$stage $c"
    return 0
  done
  say none
}
