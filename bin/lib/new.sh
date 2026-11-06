#!/usr/bin/env bash
# opsx new [--repo <path>] -- <一句話>：＋新增一張 source: me 的收件卡，印出 slug。
# 給了 repo 就在那裡建殼；沒給就寫 <state>/unfiled/<slug>.md，等 opsx file 選 repo（board-inbox D6）。
# slug 是 me-<YYYYMMDD-HHMM>，同名依序加 -2（D2）。specs/board-actions「新增到收件匣」。

opsx_new() {
  local top="" text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --) shift; text="$*"; break ;;
      *) die "new: 用法 opsx new [--repo <path>] -- <一句話>" ;;
    esac
  done
  single_line "$text"
  [ -z "$top" ] || top="$(opsx_repo_top "$top")"
  text="$(printf '%s' "$text" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  local slug body; slug="me-$(date '+%Y%m%d-%H%M')"; body="$(mktemp "${TMPDIR:-/tmp}/opsx-new.XXXXXX")"
  trap 'rm -f "$body"' RETURN
  printf -- '---\ntype: 功能\nsource: me\nfound: %s\nrelated:\n---\n\n## 一句話\n\n%s\n\n## 證據\n\n' "$(date '+%Y-%m-%d')" "$text" > "$body"
  if [ -n "$top" ]; then
    new_shell "$top" "$slug" "$body"
    return
  fi
  local dir="$OPSX_STATE_DIR/unfiled" s="$slug" n=1
  mkdir -p "$dir"
  while [ -e "$dir/$s.md" ]; do n=$((n+1)); s="$slug-$n"; done
  cp "$body" "$dir/$s.md"
  printf '%s\n' "$s"
}
