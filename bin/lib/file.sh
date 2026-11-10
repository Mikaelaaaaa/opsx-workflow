#!/usr/bin/env bash
# opsx file <slug> --repo <path>：把待分類 <state>/unfiled/<slug>.md 搬成 repo 裡的一張殼，內容原樣當 inbox.md。
# repo 已有同名就加 -2；印實際的 slug。unfiled/<slug>/attachments/ 跟著搬進新殼。
# specs/board-actions「待分類搬進 repo」「新增時附檔」、board-inbox D6。

opsx_file() {
  local slug="" top=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      -*) die "file: 不認得的選項 $1" ;;
      *) [ -z "$slug" ] || die "file: 用法 opsx file <slug> --repo <path>"; slug="$1"; shift ;;
    esac
  done
  [ -n "$slug" ] && [ -n "$top" ] || die "file: 用法 opsx file <slug> --repo <path>"
  [[ "$slug" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "file: slug 不合格：$slug"
  local src="$OPSX_STATE_DIR/unfiled/$slug.md"
  [ -f "$src" ] || die "file: 待分類裡沒有 ${slug}（${src}）"
  top="$(opsx_repo_top "$top")"
  local real extra att="$OPSX_STATE_DIR/unfiled/$slug"
  # 建殼前先擋：建殼後才失敗，重跑會多一個沒有附件的 -2 殼。.DS_Store 是 Finder 打開資料夾時寫的，可以丟
  if [ -d "$att" ]; then
    extra="$(find "$att" -mindepth 1 -maxdepth 1 ! -name attachments ! -name .DS_Store)"
    [ -z "$extra" ] || die "file: ${att} 除了 attachments/ 還有別的檔，先移走再分類：${extra}"
  fi
  real="$(new_shell "$top" "$slug" "$src")"
  if [ -d "$att" ]; then
    [ ! -d "$att/attachments" ] || mv "$att/attachments" "$top/openspec/changes/$real/attachments"
    rm -f "$att/.DS_Store"
    rmdir "$att"
  fi
  rm "$src"
  printf '%s\n' "$real"
}
