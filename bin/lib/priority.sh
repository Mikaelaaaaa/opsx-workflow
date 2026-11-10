#!/usr/bin/env bash
# opsx priority <slug> [--repo <top>]：印 `<P0|P1|P2>\t<理由>`；算不出來退出 1。
# opsx priority <slug> --set <P0|P1|P2> --reason <理由> [--repo <top>]：使用者覆寫，寫 inbox frontmatter、記 decisions.tsv。
# 計算在 priority.py。specs/opsx-priority/spec.md。

opsx_priority() {
  local slug="" top="" level="" reason="" setting=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --set) setting=1; level="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      --*) die "priority: 不認得的選項 $1" ;;
      *) [ -z "$slug" ] && slug="$1" || die "priority: 多餘的參數 $1"; shift ;;
    esac
  done
  [ -n "$slug" ] || die "priority: 用法 opsx priority <slug> [--set <P0|P1|P2> --reason <理由>] [--repo <top>]"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "priority: 不在 git repo 裡，或給 --repo"
  top="$(opsx_repo_top "$top")"
  if [ -z "$setting" ]; then
    "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/priority.py" get "$top" "$slug" || exit 1
    return
  fi
  local d="$top/openspec/changes/$slug"
  [ -f "$d/inbox.md" ] || die "priority: 沒有這張卡的 inbox.md：$d" 1
  "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/priority.py" set "$d/inbox.md" "$level" "$reason" || exit 1
  log_row "$d" 你 已決定 "等級改 ${level}：${reason}"
  say "priority: $slug → $level"
}
