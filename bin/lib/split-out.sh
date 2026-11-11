#!/usr/bin/env bash
# opsx split-out [--repo <top>] <目標> <id>：把目標卡 inbox.md 裡含 `- id: <id>` 的 ## 併入 段拆回一張獨立的殼，印新 slug。
# 新殼 slug 是 id（被占用時 new_shell 加 -2），inbox.md 跟 opsx new 寫的同形。先建殼再刪段：刪段失敗時新殼已在，資料不會掉。
# 人明確要拆，所以不走併入比對、不看目標的階段。specs/card-auto-merge「拆出來」，new-auto-merge D4。

opsx_split-out() {
  local top="" tgt id dir body rc s
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] || die "split-out: --repo 後面要給 repo 路徑"; top="$2"; shift 2 ;;
      -*) die "split-out: 不認得的選項：$1" ;;
      *) break ;;
    esac
  done
  [ $# -eq 2 ] || die "split-out: 用法 opsx split-out [--repo <top>] <目標> <id>"
  tgt="$1"; id="$2"
  [ -n "$top" ] || top="$(git_toplevel)"
  top="$(opsx_repo_top "$top")"
  dir="$top/openspec/changes/$tgt"
  [ -f "$dir/inbox.md" ] || die "split-out: 目標卡 ${tgt} 沒有 inbox.md（${dir}）"

  body="$(mktemp "${TMPDIR:-/tmp}/opsx-split-out.XXXXXX")"
  trap 'rm -f "$body"' RETURN
  "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/inboxmerge.py" card "$dir" "$id" > "$body" || exit "$?"
  s="$(new_shell "$top" "$id" "$body")"
  rc=0; "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/inboxmerge.py" remove "$dir" "$id" || rc=$?
  [ "$rc" -eq 0 ] || die "split-out: 已建 ${s}，但 ${tgt}/inbox.md 裡含「- id: ${id}」的「## 併入：」段沒刪掉（上面是原因），請手動刪掉那一段" "$rc"
  log_row "$dir" 系統 已決定 "拆出 ${id} 成 ${s}"
  log_row "$top/openspec/changes/$s" 系統 已決定 "從 ${tgt} 拆出（id ${id}）"
  printf '%s\n' "$s"
}
