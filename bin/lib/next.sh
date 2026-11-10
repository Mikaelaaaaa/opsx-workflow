#!/usr/bin/env bash
# opsx next：feature session（opsx dispatch --feature）的主 change 開了 MR、停在等合併時，
# 印同 feature 下一個還沒開 MR 的主 change 該跑的指令 `/<stage> <主>`；沒有、或這張不是 session 代管，印 none。
# references/continue.md 的 babysit 那一站叫它。驗收：specs/session-dispatch/spec.md「session 做完一個主 change 接下一個」。

opsx_next() {
  [ $# -eq 0 ] || die "next: 用法 opsx next（在卡的 branch 上跑）"
  local top slug repo
  top="$(git_toplevel)"
  [ -n "$top" ] || die "next: 不在 git repo 裡"
  slug="$(slug_from_branch "$(git_branch)")"
  [ -n "$slug" ] || die "next: branch '$(git_branch)' 對不到卡（要 {action}/{slug}/{user}）"
  repo="$(basename "$top")"
  local cards c stage
  cards="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/chain.py" siblings "$top" "$repo" "$slug" "$OPSX_STATE_DIR/dispatch.json")" || exit 2
  for c in $cards; do
    stage="$(stage_name "$top" "$c")"
    case "$stage" in babysit|archive|split) continue ;; esac
    say "/$stage $c"
    return 0
  done
  say none
}
