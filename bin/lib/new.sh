#!/usr/bin/env bash
# opsx new [--repo <path>] [--source <me|agent:<slug>>] [--kind-of-work <incident|planned>] [--impact <值,…>] [--evidence <一行>] [--attach <file>]… -- <一句話>：＋新增一張收件卡，印出 slug。
# 給了 repo 就在那裡建殼；沒給就寫 <state>/unfiled/<slug>.md，等 opsx file 選 repo（board-inbox D6）。
# slug 是 me-<YYYYMMDD-HHMM>，同名依序加 -2（D2）。specs/board-actions「新增到收件匣」「新增時附檔」「agent 開的卡標明來源」。
# --attach 的檔複製進卡的 attachments/（待分類是 unfiled/<slug>/attachments/），有附件時 source: paste。
# 在 dispatch 的 worktree（<top>/.claude/worktrees/<slug>）裡呼叫是 agent 開的：source: agent:<slug>、slug 前綴 agent-；--source me 蓋過偵測。
# agent 開的卡必帶 --kind-of-work；incident 還要 --impact 與 --evidence（references/priority.md 的事實欄位）。使用者開的卡不強制，沒帶是 planned。

OPSX_ATTACH_MAX=10485760

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# 事實欄位（references/priority.md）：值域、incident 要 impact 與 evidence、planned 不填 impact；agent 開的卡一定要有 kind。
check_fact_flags() { # <source> <kind> <impact> <evidence>
  local src="$1" kind="$2" impact="$3" evidence="$4" v
  case "$src" in agent:*) [ -n "$kind" ] || die "new: agent 開的卡要帶 --kind-of-work incident|planned（incident 還要 --impact 與 --evidence）" ;; esac
  case "$kind" in ""|incident|planned) ;; *) die "new: --kind-of-work 要是 incident 或 planned，拿到：$kind" ;; esac
  case "$impact$evidence" in *$'\n'*|*$'\r'*) die "new: --impact 與 --evidence 不能有換行" ;; esac
  for v in $(printf '%s' "$impact" | tr ',' ' '); do
    case "$v" in security|data|prod_or_main|workaround_exists|blocks_all_agents) ;; *) die "new: --impact 不認得「${v}」，要是 security、data、prod_or_main、workaround_exists、blocks_all_agents 之一" ;; esac
  done
  [ "$kind" = incident ] || [ -z "${impact//[[:space:],]/}" ] || die "new: --impact 只有 incident 填（kind 是「${kind:-planned}」）"
  if [ "$kind" = incident ]; then
    [ -n "${impact//[[:space:],]/}" ] || die "new: incident 要帶 --impact"
    [ -n "${evidence//[[:space:]]/}" ] || die "new: incident 要帶 --evidence（沒有證據不能填 impact）"
  fi
}

opsx_new() {
  local top="" text="" source="" kind="" impact="" evidence="" prefix=me files=() names=() f b stem ext cand n taken=$'\n' i wt mt
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --source) [ $# -ge 2 ] || die "new: --source 後面要給 me 或 agent:<slug>"; source="$2"; shift 2 ;;
      --kind-of-work) [ $# -ge 2 ] || die "new: --kind-of-work 後面要給 incident 或 planned"; kind="$2"; shift 2 ;;
      --impact) [ $# -ge 2 ] || die "new: --impact 後面要給值"; impact="$2"; shift 2 ;;
      --evidence) [ $# -ge 2 ] || die "new: --evidence 後面要給一行證據"; evidence="$2"; shift 2 ;;
      --attach) [ $# -ge 2 ] || die "new: --attach 後面要給檔案"; files+=("$2"); shift 2 ;;
      --) shift; text="$*"; break ;;
      *) die "new: 用法 opsx new [--repo <path>] [--source <me|agent:<slug>>] [--kind-of-work <incident|planned>] [--impact <值,…>] [--evidence <一行>] [--attach <file>]… -- <一句話>" ;;
    esac
  done
  single_line "$text"
  if [ -z "$source" ]; then
    wt="$(git_worktree_top)"
    case "$wt" in
      */.claude/worktrees/*/*) ;;
      */.claude/worktrees/*)
        # 卡名比照 hooks/_lib.sh 的 card_slug：branch 對得到卡（含子殼 <主>--<子>）就用卡名，對不到才用資料夾名（Claude Code 自己開的 worktree 叫 agent-a<hex>）
        b="$(slug_from_branch "$(git_branch)")"; mt="$(git_toplevel)"
        [ -n "$b" ] && [ -d "$(st_card_dir "$mt" "$b")" ] || b="${wt##*/}"
        source="agent:$b" ;;
    esac
  fi
  [ -z "$source" ] || [[ "$source" =~ ^(me|agent:[A-Za-z0-9][A-Za-z0-9._-]*)$ ]] || die "new: --source 要是 me 或 agent:<slug>，拿到：$source"
  check_fact_flags "$source" "$kind" "$impact" "$evidence"
  [ -z "$top" ] || top="$(opsx_repo_top "$top")"
  for f in ${files[@]+"${files[@]}"}; do
    [ -f "$f" ] || die "new: --attach 不存在或不是一般檔案：$f"
    [ "$(( $(wc -c < "$f") ))" -le "$OPSX_ATTACH_MAX" ] || die "new: --attach $f 超過 10 MB"
    b="$(basename "$f")"
    # 檔名原樣寫進 inbox.md 的一行，帶換行就能插出新段落
    case "$b" in *[[:cntrl:]]*) die "new: --attach 檔名不能有控制字元：$(printf '%q' "$b")" ;; esac
    case "$b" in ?*.*) stem="${b%.*}"; ext=".${b##*.}" ;; *) stem="$b"; ext="" ;; esac
    cand="$b"; n=1
    # 不分大小寫比對：macOS 的檔案系統不分大小寫，A.png 與 a.png 會是同一個檔
    while [[ "$taken" == *$'\n'"$(lower "$cand")"$'\n'* ]]; do n=$((n+1)); cand="$stem-$n$ext"; done
    taken+="$(lower "$cand")"$'\n'; names+=("$cand")
  done

  text="$(printf '%s' "$text" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  case "$source" in
    agent:*) prefix=agent ;;
    *) source=me; [ ${#names[@]} -eq 0 ] || source=paste ;;
  esac
  local slug body; slug="$prefix-$(date '+%Y%m%d-%H%M')"; body="$(mktemp "${TMPDIR:-/tmp}/opsx-new.XXXXXX")"
  trap 'rm -f "$body"' RETURN
  printf -- '---\ntype: 功能\nsource: %s\nfound: %s\nrelated:\nkind_of_work: %s\n' "$source" "$(date '+%Y-%m-%d')" "${kind:-planned}" > "$body"
  [ -z "$impact" ] || printf 'impact: %s\n' "$impact" >> "$body"
  [ -z "$evidence" ] || printf 'evidence: %s\n' "$evidence" >> "$body"
  printf -- '---\n\n## 一句話\n\n%s\n\n' "$text" >> "$body"
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
    # set -C 讓重導向以 O_EXCL 建檔：建成功就是拿到這個 slug，並行的另一個呼叫只會建失敗再試下一號。
    # 附件資料夾 <slug>/ 已經在的 slug 也不能用，放掉剛建的空檔再換號。
    while :; do
      if ( set -C; : > "$dir/$s.md" ) 2>/dev/null; then
        [ -e "$dir/$s" ] || break
        rm -f "$dir/$s.md"
      elif [ ! -e "$dir/$s.md" ]; then
        die "new: 建不了 $dir/$s.md"
      fi
      n=$((n+1)); s="$slug-$n"
    done
    cat "$body" > "$dir/$s.md" || { rm -f "$dir/$s.md"; die "new: 寫不進 $dir/$s.md"; }
    dest="$dir/$s/attachments"
  fi
  if [ ${#names[@]} -gt 0 ]; then
    mkdir -p "$dest"
    for i in "${!files[@]}"; do cp "${files[$i]}" "$dest/${names[$i]}"; done
  fi
  printf '%s\n' "$s"
}
