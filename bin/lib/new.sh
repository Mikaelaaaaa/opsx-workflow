#!/usr/bin/env bash
# opsx new [--repo <path>] [--source <me|agent:<slug>>] [--type <bug|功能|想法|技術債|待定>] [--kind-of-work <incident|planned>] [--impact <值,…>] [--evidence <一行>] [--attach <file>]… -- <一句話>：＋新增一張收件卡，印出 slug。
# 給了 repo 就在那裡建殼；沒給就寫 <state>/unfiled/<slug>.md，等 opsx file 選 repo（board-inbox D6）。
# slug 是 me-<YYYYMMDD-HHMM>，同名依序加 -2（D2）。specs/board-actions「新增到收件匣」「新增時附檔」「agent 開的卡標明來源」。
# --attach 的檔複製進卡的 attachments/（待分類是 unfiled/<slug>/attachments/），有附件時 source: paste。
# 環境變數 OPSX_CARD 有值（dispatch 啟動的 claude agent 都帶），或在 dispatch 的 worktree（<top>/.claude/worktrees/<slug>）裡呼叫，是 agent 開的：source: agent:<slug>、slug 前綴 agent-；這時帶 --source me 報錯，--source agent:<slug> 照收。
# agent 開的卡必帶 --kind-of-work；incident 還要 --impact 與 --evidence（references/priority.md 的事實欄位）。使用者開的卡不強制，沒帶是 planned。
# type 沒帶時 agent 開的卡是 bug、其他是待定。
# P2 的 bug／技術債提到的 repo 檔案跟一張還沒開工的卡有交集，就併進那張的 inbox.md，不建殼，印的是那張的 slug（specs/card-auto-merge「同檔案併入」）。

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

# 還沒開工、可以當併入目標的主殼：stage 是 explore/grill/propose、不是開卡者自己的主殼。一行一個。
# archive 目錄沒有 inbox.md，子殼在 subs/ 底下，glob 都碰不到。誰跟新項目有共同檔案由 mergematch.py 判斷。
merge_candidates() { # <top> <開卡者自己的主殼名，使用者卡是空字串>
  local f s
  for f in "$1"/openspec/changes/*/inbox.md; do
    [ -e "$f" ] || continue
    s="${f%/inbox.md}"; s="${s##*/}"
    [ "$s" != "$2" ] || continue
    case "$(stage_name "$1" "$s")" in explore|grill|propose) printf '%s\n' "$s" ;; esac
  done
}

# 一句話會原樣成為併入段的最後一行：長得像段落標題或段內欄位，就會切斷那一段或多出一個假 id，之後拆不出來。
# area 留著：舊格式的併入段還有 - area:，parse 認得它。
merge_text_ok() { # <一句話>
  local re='^(## |- (id|kind_of_work|evidence|type|area):)'
  [[ ! "$1" =~ $re ]]
}

# 併進 <目標>：追加 ## 併入 段（id 在鎖內算）、兩邊記 decisions.tsv、在 herdr 裡才通知。stdout 印目標 slug，stderr 印併進哪裡。
# 通知失敗只警告：併入已經寫好，退出非零會讓 agent 以為沒開成、再開一次。
# 寫進去了才把呼叫端的 merged 設成 1；目標在判斷後已開工或已拆（append 退出 4）時不設，呼叫端改建殼。
merge_into() { # <top> <目標> <基本 id> <source> <kind> <evidence> <type> <一句話>
  local top="$1" tgt="$2" source="$4" text="$8" id own err rc=0
  id="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/inboxmerge.py" append "$top/openspec/changes/$tgt" "$3" "$(now_iso)" "$source" "$5" "$6" "$7" "$text")" || rc=$?
  [ "$rc" -ne 4 ] || return 0
  [ "$rc" -eq 0 ] || die "new: 併不進 ${tgt}（上面是原因）"
  merged=1
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
  local top="" text="" source="" type="" type_set="" kind="" impact="" evidence="" prefix=me files=() names=() f b stem ext cand n taken=$'\n' i wt mt
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --source) [ $# -ge 2 ] || die "new: --source 後面要給 me 或 agent:<slug>"; source="$2"; shift 2 ;;
      --kind-of-work) [ $# -ge 2 ] || die "new: --kind-of-work 後面要給 incident 或 planned"; kind="$2"; shift 2 ;;
      --impact) [ $# -ge 2 ] || die "new: --impact 後面要給值"; impact="$2"; shift 2 ;;
      --evidence) [ $# -ge 2 ] || die "new: --evidence 後面要給一行證據"; evidence="$2"; shift 2 ;;
      --attach) [ $# -ge 2 ] || die "new: --attach 後面要給檔案"; files+=("$2"); shift 2 ;;
      --type) [ $# -ge 2 ] || die "new: --type 後面要給 bug、功能、想法、技術債、待定 之一"; type="$2"; type_set=1; shift 2 ;;
      --) shift; text="$*"; break ;;
      *) die "new: 用法 opsx new [--repo <path>] [--source <me|agent:<slug>>] [--type <bug|功能|想法|技術債|待定>] [--kind-of-work <incident|planned>] [--impact <值,…>] [--evidence <一行>] [--attach <file>]… -- <一句話>" ;;
    esac
  done
  if [ -n "$type_set" ]; then
    case "$type" in bug|功能|想法|技術債|待定) ;; *) die "new: --type 要是 bug、功能、想法、技術債、待定 之一，拿到：${type}" ;; esac
  fi
  single_line "$text"
  wt="$(git_worktree_top)"
  # dispatch 的 claude 帶 OPSX_CARD（launch.sh 寫進 settings 的 env），agent cd 到哪都在。
  # shortcut: codex 沒有 env 通道，沿用 worktree 路徑判斷；codex 能注入環境變數時刪掉路徑判斷
  case "$wt" in
    */.claude/worktrees/*/*) wt="" ;;
    */.claude/worktrees/*) ;;
    *) wt="" ;;
  esac
  if [ -n "$wt" ] || [ -n "${OPSX_CARD:-}" ]; then
    [ "$source" != me ] || die "new: dispatch 的 agent 不要帶 --source me：agent 開的卡由系統標成 agent 來源，--source me 會讓卡不被自動併"
    if [ -z "$source" ]; then
      if [ -n "$wt" ]; then
        # 卡名比照 hooks/_lib.sh 的 card_slug：branch 對得到卡（含子殼 <主>--<子>）就用卡名，對不到才用資料夾名（Claude Code 自己開的 worktree 叫 agent-a<hex>）
        b="$(slug_from_branch "$(git_branch)")"; mt="$(git_toplevel)"
        [ -n "$b" ] && [ -d "$(st_card_dir "$mt" "$b")" ] || b="${wt##*/}"
      else
        b="$OPSX_CARD"
      fi
      source="agent:$b"
    fi
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
  [ -n "$type_set" ] || { [ "$prefix" = agent ] && type=bug || type=待定; }
  local slug body lv tgt own="" merged=""; slug="$prefix-$(date '+%Y%m%d-%H%M')"
  # 只併小事：type 是 bug 或技術債、有 repo、沒附件、一句話不像段落結構、等級是 P2 才找目標；等級由 priority.py 算。
  # 只併 P2：目標的等級事後可能因 milestone、覆寫或依賴繼承掉回 P2，併進去的 P0／P1 會跟著掉。
  local small=""
  case "$type" in bug|技術債) small=1 ;; esac
  if [ -n "$small" ] && [ -n "$top" ] && [ ${#names[@]} -eq 0 ] && merge_text_ok "$text"; then
    lv="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/priority.py" level "${kind:-planned}" "$impact")" || die "new: 算不出新卡的等級（上面是原因）"
    if [ "${lv%%$'\t'*}" = P2 ]; then
      # 子殼的 subagent 是 agent:<主>--<子>，它自己的卡是主殼
      case "$source" in agent:*) own="${source#agent:}"; own="${own%%--*}" ;; esac
      tgt="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/mergematch.py" pick "$top" "$text" "$evidence" $(merge_candidates "$top" "$own"))" || die "new: 找不到併入目標（上面是原因）"
      if [ -n "$tgt" ]; then
        merge_into "$top" "$tgt" "$slug" "$source" "${kind:-planned}" "$evidence" "$type" "$text"
        [ -z "$merged" ] || return 0
      fi
    fi
  fi
  body="$(mktemp "${TMPDIR:-/tmp}/opsx-new.XXXXXX")"
  trap 'rm -f "$body"' RETURN
  printf -- '---\ntype: %s\nsource: %s\nfound: %s\nrelated:\nkind_of_work: %s\n' "$type" "$source" "$(date '+%Y-%m-%d')" "${kind:-planned}" > "$body"
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
