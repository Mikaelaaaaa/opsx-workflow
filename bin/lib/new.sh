#!/usr/bin/env bash
# opsx new [--repo <path>] [--source <me|agent:<slug>>] [--kind-of-work <incident|planned>] [--impact <值,…>] [--evidence <一行>] [--area <名>] [--attach <file>]… -- <一句話>：＋新增一張收件卡，印出 slug。
# 給了 repo 就在那裡建殼；沒給就寫 <state>/unfiled/<slug>.md，等 opsx file 選 repo（board-inbox D6）。
# slug 是 me-<YYYYMMDD-HHMM>，同名依序加 -2（D2）。specs/board-actions「新增到收件匣」「新增時附檔」「agent 開的卡標明來源」。
# --attach 的檔複製進卡的 attachments/（待分類是 unfiled/<slug>/attachments/），有附件時 source: paste。
# 在 dispatch 的 worktree（<top>/.claude/worktrees/<slug>）裡呼叫是 agent 開的：source: agent:<slug>、slug 前綴 agent-；--source me 蓋過偵測。
# agent 開的卡必帶 --kind-of-work；incident 還要 --impact 與 --evidence（references/priority.md 的事實欄位）。使用者開的卡不強制，沒帶是 planned。
# --area 寫進 frontmatter 的 area:，值要在 repo 的 openspec/areas.txt 裡；有清單時 agent 開的卡必帶。沒有清單的 repo 不收 --area，其餘照舊（new-auto-merge D2、D3）。
# agent 開的卡遇到同 area、還沒有 tasks.md 的卡就併進那張的 inbox.md，不建殼，印的是那張的 slug（new-auto-merge D1、D4）。

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

# 讀 area 清單，一行印一個。忽略空行、# 開頭的行與行尾空白；不合格式的行 die 並報行號，免得打錯字的 area 永遠對不到。
opsx_areas() { # <areas.txt>
  local f="$1" line n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1))
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in ""|"#"*) continue ;; esac
    [[ "$line" =~ ^[a-z0-9][a-z0-9/_-]*$ ]] || die "new: $f 第 $n 行不是合格的 area 名（要符合 [a-z0-9][a-z0-9/_-]*）：$line"
    printf '%s\n' "$line"
  done < "$f"
}

check_area() { # <top> <source> <area>
  local top="$1" src="$2" area="$3" f="$1/openspec/areas.txt" list
  if [ -z "$top" ]; then
    [ -z "$area" ] || die "new: --area 要配 --repo（待分類的卡沒有 repo，對不到 areas.txt）"
    return 0
  fi
  if [ ! -f "$f" ]; then
    [ -z "$area" ] || die "new: $f 不存在，這個 repo 不收 --area（拿到：${area}）"
    return 0
  fi
  case "$src" in agent:*) ;; *) [ -n "$area" ] || return 0 ;; esac
  list="$(opsx_areas "$f")" || exit 2
  [ -n "$area" ] || die "new: 這個 repo 有 openspec/areas.txt，agent 開的卡要帶 --area <名>，可選：${list//$'\n'/ }"
  grep -qxF -- "$area" <<< "$list" || die "new: --area「${area}」不在 openspec/areas.txt 裡，可選：${list//$'\n'/ }"
}

# 自動併入的目標（new-auto-merge D1–D3）：主殼 frontmatter area: 等於 <area>、stage 是 explore/grill/propose、不是開卡 agent 自己的主殼。
# 好幾張取 slug 字母序（C locale）第一張；沒有就不印。archive 目錄沒有 inbox.md，子殼在 subs/ 底下，glob 都碰不到。
merge_target() { # <top> <area> <開卡 agent 的主殼名>
  local f=("$1"/openspec/changes/*/inbox.md) s
  [ -e "${f[0]}" ] || return 0
  while IFS= read -r s; do
    [ "$s" != "$3" ] || continue
    case "$(stage_name "$1" "$s")" in explore|grill|propose) printf '%s\n' "$s"; return ;; esac
  done < <(awk -v a="$2" '
    FNR == 1 { fm = ($0 ~ /^---[[:space:]]*$/); next }
    fm && /^---[[:space:]]*$/ { fm = 0; nextfile }
    fm && /^area:/ { v = $0; sub(/^area:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); if (v == a) print FILENAME; fm = 0; nextfile }
  ' "${f[@]}" | sed -E 's#/inbox\.md$##; s#.*/##' | LC_ALL=C sort)
}

# 一句話會原樣成為併入段的最後一行：長得像段落標題或段內欄位，就會切斷那一段或多出一個假 id，之後拆不出來。
merge_text_ok() { # <一句話>
  local re='^(## |- (id|kind_of_work|impact|evidence|area):)'
  [[ ! "$1" =~ $re ]]
}

# 新卡等級比目標高就不併：併進去之後是照目標的等級排隊。目標的事實不合格、算不出等級時也不併，照樣建殼。
merge_level_ok() { # <top> <目標> <新卡等級>
  local got
  got="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/priority.py" get "$1" "$2" 2>&1)" || { warn "new: 算不出 $2 的等級，不併入：$got"; return 1; }
  [[ ! "$3" < "${got%%$'\t'*}" ]]
}

# 併進 <目標>：追加 ## 併入 段（id 在鎖內算）、兩邊記 decisions.tsv、在 herdr 裡才通知。stdout 印目標 slug，stderr 印併進哪裡。
# 通知失敗只警告：併入已經寫好，退出非零會讓 agent 以為沒開成、再開一次。
merge_into() { # <top> <目標> <基本 id> <source> <kind> <impact> <evidence> <area> <一句話>
  local top="$1" tgt="$2" source="$4" text="$9" id own err
  id="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/inboxmerge.py" append "$top/openspec/changes/$tgt" "$3" "$(now_iso)" "$source" "$5" "$6" "$7" "$8" "$text")" || die "new: 併不進 ${tgt}（上面是原因）"
  log_row "$top/openspec/changes/$tgt" 系統 已決定 "併入 ${id}：${text}" "$source"
  own="$(st_card_dir "$top" "${source#agent:}")"
  [ ! -d "$own" ] || log_row "$own" 系統 已決定 "併進 ${tgt}（id ${id}）" "$source"
  if [ -n "${HERDR_ENV:-}" ]; then
    err="$(herdr notification show "[${top##*/}/${tgt}] 併入" --body "${text} 併進 ${tgt}" 2>&1 >/dev/null)" || warn "new: 已併進 ${tgt}，但 herdr 通知送不出去：$err"
  fi
  printf '併進 %s（id %s）\n' "$tgt" "$id" >&2
  printf '%s\n' "$tgt"
}

opsx_new() {
  local top="" text="" source="" kind="" impact="" evidence="" area="" prefix=me files=() names=() f b stem ext cand n taken=$'\n' i wt mt
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --source) [ $# -ge 2 ] || die "new: --source 後面要給 me 或 agent:<slug>"; source="$2"; shift 2 ;;
      --kind-of-work) [ $# -ge 2 ] || die "new: --kind-of-work 後面要給 incident 或 planned"; kind="$2"; shift 2 ;;
      --impact) [ $# -ge 2 ] || die "new: --impact 後面要給值"; impact="$2"; shift 2 ;;
      --evidence) [ $# -ge 2 ] || die "new: --evidence 後面要給一行證據"; evidence="$2"; shift 2 ;;
      --attach) [ $# -ge 2 ] || die "new: --attach 後面要給檔案"; files+=("$2"); shift 2 ;;
      --area) [ $# -ge 2 ] || die "new: --area 後面要給 openspec/areas.txt 裡的一個名字"; area="$2"; shift 2 ;;
      --) shift; text="$*"; break ;;
      *) die "new: 用法 opsx new [--repo <path>] [--source <me|agent:<slug>>] [--kind-of-work <incident|planned>] [--impact <值,…>] [--evidence <一行>] [--area <名>] [--attach <file>]… -- <一句話>" ;;
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
  check_area "$top" "$source" "$area"
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
  local slug body lv tgt own; slug="$prefix-$(date '+%Y%m%d-%H%M')"
  # agent 開、有 repo 與 area、沒附件、一句話不像段落結構、不是 P0 的卡才找目標；等級由 priority.py 算
  if [ "$prefix" = agent ] && [ -n "$top" ] && [ -n "$area" ] && [ ${#names[@]} -eq 0 ] && merge_text_ok "$text"; then
    lv="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/priority.py" level "${kind:-planned}" "$impact")" || die "new: 算不出新卡的等級（上面是原因）"
    lv="${lv%%$'\t'*}"
    if [ "$lv" != P0 ]; then
      # 子殼的 subagent 是 agent:<主>--<子>，它自己的卡是主殼
      own="${source#agent:}"; own="${own%%--*}"
      tgt="$(merge_target "$top" "$area" "$own")"
      if [ -n "$tgt" ] && merge_level_ok "$top" "$tgt" "$lv"; then
        merge_into "$top" "$tgt" "$slug" "$source" "${kind:-planned}" "$impact" "$evidence" "$area" "$text"; return
      fi
    fi
  fi
  body="$(mktemp "${TMPDIR:-/tmp}/opsx-new.XXXXXX")"
  trap 'rm -f "$body"' RETURN
  printf -- '---\ntype: 功能\nsource: %s\nfound: %s\nrelated:\nkind_of_work: %s\n' "$source" "$(date '+%Y-%m-%d')" "${kind:-planned}" > "$body"
  [ -z "$impact" ] || printf 'impact: %s\n' "$impact" >> "$body"
  [ -z "$evidence" ] || printf 'evidence: %s\n' "$evidence" >> "$body"
  [ -z "$area" ] || printf 'area: %s\n' "$area" >> "$body"
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
