#!/usr/bin/env bash
# opsx merge-card <來源> --into <目標> --repo <path>：把同 repo 的收件卡併進另一張卡。
# 先驗目標與來源，再用 opsx_drop 捨棄來源（理由「併入 <repo>/<目標>」），最後在目標 inbox.md 的 ## 證據 段尾端
# 追加一行、decisions.tsv 記一列。捨棄會歸檔、退不回來，所以能驗的都在捨棄之前驗完。
# specs/board-actions「併進既有的卡」。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/drop.sh"

# 印 inbox.md frontmatter 裡 <key> 的值；沒有這個欄就什麼都不印
frontmatter_field() { # <inbox.md> <key>
  awk -v k="$2" 'NR==1 && !/^---/{exit} NR>1 && /^---/{exit} index($0, k ":") == 1 {v = substr($0, length(k) + 2); sub(/^ +/, "", v); sub(/\r$/, "", v); print v; exit}' "$1"
}

opsx_merge-card() {
  local src="" into="" top=""
  local usage="merge-card: 用法 opsx merge-card <來源> --into <目標> --repo <path>"
  while [ $# -gt 0 ]; do
    case "$1" in
      --into) [ $# -ge 2 ] || die "$usage"; into="$2"; shift 2 ;;
      --repo) [ $# -ge 2 ] || die "$usage"; top="$2"; shift 2 ;;
      -*) die "merge-card: 不認得的選項 $1" ;;
      *) [ -z "$src" ] || die "$usage"; src="$1"; shift ;;
    esac
  done
  [ -n "$src" ] && [ -n "$into" ] && [ -n "$top" ] || die "$usage"
  [[ "$src" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "merge-card: 來源 slug 不合格：$src"
  [[ "$into" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "merge-card: 目標 slug 不合格：$into"
  [ "$into" != "$src" ] || die "merge-card: 目標 $into 就是來源本身"

  top="$(opsx_repo_top "$top")"
  local repo ch; repo="$(basename "$top")"; ch="$top/openspec/changes"
  local s_inbox="$ch/$src/inbox.md" t_inbox="$ch/$into/inbox.md"
  [ -f "$s_inbox" ] || die "merge-card: 來源沒有 inbox.md：$s_inbox"
  [ -f "$t_inbox" ] || die "merge-card: 目標 $into 不存在：$t_inbox"
  grep -q '^## 證據$' "$t_inbox" || die "merge-card: 目標 $into 的 inbox.md 沒有 ## 證據 段，先手動補上：$t_inbox"
  local source url
  source="$(frontmatter_field "$s_inbox" source)"
  [ -n "$source" ] || die "merge-card: 來源 $src 的 inbox.md frontmatter 沒有 source:：$s_inbox"
  url="$(frontmatter_field "$s_inbox" upstream_url)"

  opsx_drop "$src" --repo "$top" -- "併入 $repo/$into"

  local line="- 併進：$repo/$src · source: $source"
  [ -z "$url" ] || line="$line · $url"
  # 插在證據段最後一行非空內容之後，跟 sync.py 的 append_to_section 同一個位置
  awk -v line="$line" '
    { buf[NR] = $0 }
    /^## 證據$/ { sec = NR; next }
    sec && !end && /^## / { end = NR }
    sec && !end && NF { last = NR }
    END {
      for (i = 1; i <= NR; i++) {
        print buf[i]
        if (last && i == last) print line
        if (!last && i == sec) { print ""; print line }
      }
    }' "$t_inbox" | opsx_replace "$t_inbox" \
    || die "merge-card: $repo/$src 已併進並歸檔，但寫不進 ${t_inbox}；請手動在 ## 證據 段補上：$line"
  log_row "$ch/$into" 你 已決定 "併進：$repo/$src"
  say "merge-card: $repo/$src 已併進 $repo/$into"
}
