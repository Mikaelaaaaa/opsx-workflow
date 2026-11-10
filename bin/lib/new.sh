#!/usr/bin/env bash
# opsx new [--repo <path>] [--attach <file>]… -- <一句話>：＋新增一張收件卡，印出 slug。
# 給了 repo 就在那裡建殼；沒給就寫 <state>/unfiled/<slug>.md，等 opsx file 選 repo（board-inbox D6）。
# slug 是 me-<YYYYMMDD-HHMM>，同名依序加 -2（D2）。specs/board-actions「新增到收件匣」「新增時附檔」。
# --attach 的檔複製進卡的 attachments/（待分類是 unfiled/<slug>/attachments/），有附件時 source: paste。

OPSX_ATTACH_MAX=10485760

opsx_new() {
  local top="" text="" files=() names=() f b stem ext cand n taken=$'\n' i
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --attach) [ $# -ge 2 ] || die "new: --attach 後面要給檔案"; files+=("$2"); shift 2 ;;
      --) shift; text="$*"; break ;;
      *) die "new: 用法 opsx new [--repo <path>] [--attach <file>]… -- <一句話>" ;;
    esac
  done
  single_line "$text"
  [ -z "$top" ] || top="$(opsx_repo_top "$top")"
  for f in ${files[@]+"${files[@]}"}; do
    [ -f "$f" ] || die "new: --attach 不存在或不是一般檔案：$f"
    [ "$(( $(wc -c < "$f") ))" -le "$OPSX_ATTACH_MAX" ] || die "new: --attach $f 超過 10 MB"
    b="$(basename "$f")"
    case "$b" in ?*.*) stem="${b%.*}"; ext=".${b##*.}" ;; *) stem="$b"; ext="" ;; esac
    cand="$b"; n=1
    while [[ "$taken" == *$'\n'"$cand"$'\n'* ]]; do n=$((n+1)); cand="$stem-$n$ext"; done
    taken+="$cand"$'\n'; names+=("$cand")
  done

  text="$(printf '%s' "$text" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  local slug body source=me; slug="me-$(date '+%Y%m%d-%H%M')"; body="$(mktemp "${TMPDIR:-/tmp}/opsx-new.XXXXXX")"
  trap 'rm -f "$body"' RETURN
  [ ${#names[@]} -eq 0 ] || source=paste
  printf -- '---\ntype: 功能\nsource: %s\nfound: %s\nrelated:\n---\n\n## 一句話\n\n%s\n\n' "$source" "$(date '+%Y-%m-%d')" "$text" > "$body"
  if [ ${#names[@]} -gt 0 ]; then
    printf '## 附件\n\n' >> "$body"
    printf -- '- attachments/%s\n' "${names[@]}" >> "$body"
    printf '\n' >> "$body"
  fi
  printf '## 證據\n\n' >> "$body"

  local s dest
  if [ -n "$top" ]; then
    s="$(new_shell "$top" "$slug" "$body")"
    dest="$top/openspec/changes/$s/attachments"
  else
    local dir="$OPSX_STATE_DIR/unfiled"
    s="$slug"; n=1
    mkdir -p "$dir"
    while [ -e "$dir/$s.md" ] || [ -e "$dir/$s" ]; do n=$((n+1)); s="$slug-$n"; done
    cp "$body" "$dir/$s.md"
    dest="$dir/$s/attachments"
  fi
  if [ ${#names[@]} -gt 0 ]; then
    mkdir -p "$dest"
    for i in "${!files[@]}"; do cp "${files[$i]}" "$dest/${names[$i]}"; done
  fi
  printf '%s\n' "$s"
}
