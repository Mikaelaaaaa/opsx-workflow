#!/usr/bin/env bash
# 主流程狀態判斷，純函式，參數明示（top、slug）。hook 的 router 和 drive.sh 都用這一份，
# 所以「下一步是什麼」只有一個答案。要求檔 §8.3 Router 表。
source "$(dirname "${BASH_SOURCE[0]}")/check.sh"

# slug 含 `--` 是子殼：<主>--<子> 對到 changes/<主>/subs/<子>。只印路徑，不檢查存在
st_card_dir() { # <top> <slug>
  case "$2" in
    *--*) printf '%s/openspec/changes/%s/subs/%s' "$1" "${2%%--*}" "${2#*--}" ;;
    *) printf '%s/openspec/changes/%s' "$1" "$2" ;;
  esac
}
# 第一個 kind: 行冒號後的空白剝掉、其餘照原樣（含 \r、尾端空白）；最後一行沒有換行時印出來也不帶換行，跟 sed 一樣
st_card_kind() {
  local line eol
  [ -f "$1/.openspec.yaml" ] || return 0
  while eol=$'\n'; IFS= read -r line || { eol=; [ -n "$line" ]; }; do
    case "$line" in kind:*) line="${line#kind:}"; printf '%s%s' "${line#"${line%%[! ]*}"}" "$eol"; return 0 ;; esac
  done < "$1/.openspec.yaml"
}
st_status_tests() { local d="$1"; [ -f "$d/status.json" ] && jq -r '.tests // "unknown"' "$d/status.json" 2>/dev/null || printf 'unknown'; }
st_review_running() { local d="$1"; [ -f "$d/status.json" ] && jq -e '.phase == "review" and .step < .total' "$d/status.json" >/dev/null 2>&1; }
# 主殼有子 change 的 subagent 在背景做：子殼名在主殼某個未勾 task 行的編號之後、status.json 的 worker 是 subagent-* 且 step < total、at 在過去 120 分鐘內。
# 已疊的子殼 status.json 不會更新，所以「未疊」只認主殼 tasks.md 的勾選；收到 DONE 後 session 把子殼 status 寫成 n/n，等疊的時候不算在跑。
# shortcut: 120 分鐘上限，subagent 死了又沒通知最多多等兩小時；有心跳之後改看心跳
st_subagent_running() { # <主殼目錄>
  local d="$1" s name now; now="$(date +%s)"
  [ -f "$d/tasks.md" ] || return 1
  for s in "$d"/subs/*/; do
    s="${s%/}"; [ -f "$s/status.json" ] || continue
    name="$(basename "$s")"
    grep -qE "^[[:space:]]*- \[ \] [0-9.]+ \`$name\`" "$d/tasks.md" || continue
    jq -e --argjson now "$now" '
      (.at | capture("^(?<t>.{19})(?<s>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2})$")) as $p
      | (($p.t + "Z" | fromdateiso8601) - (if $p.s == "+" then 1 else -1 end) * (($p.h | tonumber) * 3600 + ($p.m | tonumber) * 60)) as $at
      | (.worker | startswith("subagent-")) and (.step | type) == "number" and (.total | type) == "number" and .step < .total and ($now - $at) >= 0 and ($now - $at) <= 7200
    ' "$s/status.json" >/dev/null 2>&1 && return 0
  done
  return 1
}
st_tasks_open() { [ -f "$1/tasks.md" ] || { printf 0; return; }; grep -cE '^\s*- \[ \]' "$1/tasks.md" || true; }
st_tasks_done() { [ -f "$1/tasks.md" ] || { printf 0; return; }; grep -cE '^\s*- \[x\]' "$1/tasks.md" || true; }
st_pending_nonempty() {
  [ -f "$1/explore.md" ] || return 1
  awk '/^## 待決/{f=1;next} /^## /{f=0} f' "$1/explore.md" | grep -vE '^\s*$|^\s*<!--|^\s*-\s*$|^\s*（' | grep -q .
}
# 第一個 MR 網址。整檔一次比對，字元類排除換行，跟 grep 逐行找第一個相同
st_mr_url() {
  local c re='https?://[^ )'$'\n'']+/(merge_requests|pull)/[0-9]+'
  [ -f "$1/report.md" ] || return 0
  IFS= read -r -d '' c < "$1/report.md" || true # -d '' 讀到檔尾一定回 1，呼叫端多半是 set -e
  [[ $c =~ $re ]] && printf '%s\n' "${BASH_REMATCH[0]}"
  return 0
}
st_mr_in_report() { [ -n "$(st_mr_url "$1")" ]; }
# 一張卡的 open gate 數：主殼加每個子殼（subs/<子>/gates.md，apply 把 NEEDS-USER 寫在那）
st_open_gates() {
  local f n=0
  for f in "$1/gates.md" "$1"/subs/*/gates.md; do
    [ -f "$f" ] || continue
    n=$((n + $(grep -cE '^status:[[:space:]]*open[[:space:]]*$' "$f" || true)))
  done
  printf '%s' "$n"
}
# 會擋 Stop 的 open gate 數：標題或「問題:」行問「要不要接 /apply」「要不要繼續？」這類接站問題的不算（接站不用問，continue.md）。主殼加每個子殼
st_open_gates_blocking() {
  local f n=0
  for f in "$1/gates.md" "$1"/subs/*/gates.md; do
    [ -f "$f" ] || continue
    n=$((n + $(st_gates_file_blocking "$f")))
  done
  printf '%s' "$n"
}
st_gates_file_blocking() { # <gates.md>
  awk '
    function flush() { if (open && (!ask || appr)) n++; open = 0; ask = 0; appr = 0 }
    /^## / { flush() }
    /^status:[ \t]*open[ \t]*$/ { open = 1 }
    /^type:[ \t]*approval[ \t]*$/ { appr = 1 }   # 核准只有人能答，不管問法
    /^(## |問題:).*要不要(接|派|繼續)([ ]*\/|[ ]*下一|\?|？|：|$)/ { ask = 1 }
    END { flush(); print n + 0 }
  ' "$1"
}
# slug 是 PR 名或 PR 底下的 change 名，印該 PR 的 <field>（branch、status）；對不到印空。
# 用 awk 不用 chain.py 的 load_workplan：collect 每張卡都判 stage，router 每句 prompt 都判，不能每次 fork python。
wp_pr_field() { # <top> <slug> <field>
  [ -f "$1/openspec/workplan.yaml" ] || return 0
  awk -v s="$2" -v k="$3" '
    function ind() { match($0, /^ */); return RLENGTH }
    function val(  v) { v = $0; sub(/^ *(- )?[A-Za-z_-]+: */, "", v); sub(/ +#.*$/, "", v); if (v == "null" || v == "~") return ""; gsub(/^["\047]|["\047]$/, "", v); return v }
    # 項目縮排取該層第一個 `- name:` 的縮排：YAML 序列可以和 `prs:` / `changes:` 同縮排，也可以更深
    BEGIN { pi = -1; pii = -1; ci = -1; cii = -1 }
    /^ *prs:/ { pi = ind(); pii = -1; ci = -1; cii = -1; pr = ""; next }
    /^ *changes:/ { ci = ind(); cii = -1; next }
    /^ *- name:/ {
      i = ind()
      if (ci >= 0) {
        if (cii < 0 && i >= ci) cii = i
        if (i == cii) { if (hit == "" && val() == s) hit = pr; next }
        if (cii >= 0 && i > cii) next
        ci = -1; cii = -1
      }
      if (pi >= 0) {
        if (pii < 0 && i >= pi) pii = i
        if (i == pii) { pr = val(); ki = i + 2; if (hit == "" && pr == s) hit = pr; next }
        if (pii >= 0 && i > pii) next
      }
      pi = -1; pii = -1; pr = ""; next
    }
    ci >= 0 && $0 !~ /^ *(#|$)/ && ind() <= ci && $0 !~ /^ *- / { ci = -1; cii = -1 }
    pi >= 0 && $0 !~ /^ *(#|$)/ && ind() <= pi && $0 !~ /^ *- / { pi = -1; pii = -1; pr = "" }
    pr != "" && ci < 0 && ind() == ki && index($0, k ":") == ki + 1 { f[pr] = val() }
    END { if (hit != "") print f[hit] }
  ' "$1/openspec/workplan.yaml"
}
st_workplan_merged() { [ "$(wp_pr_field "$1" "$2" status)" = merged ]; } # <top> <slug>
# 只看 frontmatter（第一行是 --- 才算有）裡第一個 split_into:；空值、[]、""、''、~、null 算沒拆
st_split_into() {
  local line n=0 empty='^(\[ *\]|""|'"''"'|~|null)?$'
  [ -f "$1/inbox.md" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1))
    case "$line" in
      ---*) [ "$n" -eq 1 ] && continue; return 0 ;;
      *) [ "$n" -eq 1 ] && return 0 ;;
    esac
    case "$line" in split_into:*) ;; *) continue ;; esac
    line="${line#split_into:}"; line="${line#"${line%%[! ]*}"}"; line="${line%$'\r'}"
    case "$line" in "#"*) line="" ;; *" #"*) line="${line%% #*}"; line="${line%"${line##*[! ]}"}" ;; esac
    [[ $line =~ $empty ]] || printf '%s\n' "$line"
    return 0
  done < "$1/inbox.md"
}

# 印「階段 · slug · kind · Read 清單」。沒卡印 explore。
stage_of() { # <top> <slug>
  local top="$1" slug="$2" d kind
  d="$(st_card_dir "$1" "$2")"
  if [ -z "$slug" ] || [ ! -d "$d" ]; then printf 'explore · （沒有對到卡，先建殼）· — · skills/explore/SKILL.md\n'; return; fi
  kind="$(st_card_kind "$d")"; kind="${kind:-dev}"
  local pb="skills/apply/references/playbooks" reads split
  case "$kind" in
    chore|ops) pb="" ;;
    experiment) pb="$pb/hillclimb.md · $pb/eval.md · " ;;
    *) pb="$pb/${kind}.md · " ;;
  esac
  reads="skills/apply/SKILL.md · ${pb}skills/tdd/SKILL.md"
  split="$(st_split_into "$d")"
  if [ -n "$split" ]; then printf 'split · %s · %s · 已拆成 %s，這張不再往下做\n' "$slug" "$kind" "$split"; return; fi
  if st_workplan_merged "$top" "$slug"; then printf 'archive · %s · %s · skills/archive/SKILL.md\n' "$slug" "$kind"; return; fi
  if [ -f "$d/report.md" ]; then
    if st_mr_in_report "$d"; then printf 'babysit · %s · %s · skills/babysit/SKILL.md（MR 已開，等合併；有留言用 babysit）\n' "$slug" "$kind"
    elif [ -f "$d/tasks.md" ] && [ "$(st_tasks_open "$d")" -gt 0 ]; then printf 'apply · %s · %s · %s（review 退回了 task，先做完）\n' "$slug" "$kind" "$reads"
    else printf 'pr · %s · %s · skills/pr/SKILL.md · skills/pr/references/mr-note.md\n' "$slug" "$kind"; fi; return
  fi
  if [ -f "$d/tasks.md" ]; then
    if [ "$(st_tasks_open "$d")" -gt 0 ]; then printf 'apply · %s · %s · %s\n' "$slug" "$kind" "$reads"; return; fi
    if [ "$(st_status_tests "$d")" != green ]; then printf 'apply · %s · %s · %s（tasks 全勾但 tests 不是 green：先把測試補到綠）\n' "$slug" "$kind" "$reads"; return; fi
    printf 'review · %s · %s · skills/review/SKILL.md · skills/review/references/ponytail-review.md\n' "$slug" "$kind"; return
  fi
  if [ -f "$d/explore.md" ]; then
    if [ -n "$(check_explore "$d")" ]; then printf 'explore · %s · %s · skills/explore/SKILL.md（explore.md 的 ## 步驟 不齊，opsx check %s）\n' "$slug" "$kind" "$slug"; return; fi
    if st_pending_nonempty "$d" && [ ! -f "$d/grill.md" ] && [ "$kind" != chore ] && [ "$kind" != bug-fix ]; then printf 'grill · %s · %s · skills/grill/SKILL.md\n' "$slug" "$kind"; return; fi
    printf 'propose · %s · %s · skills/propose/SKILL.md\n' "$slug" "$kind"; return
  fi
  printf 'explore · %s · %s · skills/explore/SKILL.md\n' "$slug" "$kind"
}
stage_name() { local s; s="$(stage_of "$1" "$2")"; printf '%s\n' "${s%% *}"; }

st_gates_total() { [ -f "$1/gates.md" ] || { printf 0; return; }; grep -c '^## ' "$1/gates.md" || true; }
# drive 送出階段指令前後各取一次，不同就算「有動」：階段、status.json 的 at、tasks 勾數、gate 數。
# shortcut: 不做每站專屬判斷，漏判只多開一個 gate 給人；status.json 被別的流程刷新時誤判有動，退回照階段繼續送
stage_fingerprint() { # <top> <slug>
  local d="$1/openspec/changes/$2" at=""
  [ ! -f "$d/status.json" ] || at="$(jq -r '.at // ""' "$d/status.json")"
  printf '%s|%s|%s|%s\n' "$(stage_name "$1" "$2")" "$at" "$(st_tasks_done "$d")" "$(st_gates_total "$d")"
}

# 舊 spec-driven 的 change：.openspec.yaml 沒有 schema: opsx，inbox.md 不存在或只有空白。看板只計數、router 清單不列。
# 只用 builtin：真 repo 裡有幾百張舊卡，每張 fork 一次 stage 判斷就是十幾秒。
collect_is_legacy() { # <change dir>
  local line inbox
  if [ -f "$1/.openspec.yaml" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ $line =~ ^schema:[[:space:]]*opsx[[:space:]]*$ ]] && return 1
    done < "$1/.openspec.yaml"
  fi
  if [ -f "$1/inbox.md" ]; then
    # [:space:] 依 locale：先刪掉全形空白 U+3000 與 NBSP 的位元組，沒有 LANG 的啟動方式（launchd、nohup）下也算空白
    inbox=$(<"$1/inbox.md"); inbox=${inbox//$'\xe3\x80\x80'/}; inbox=${inbox//$'\xc2\xa0'/}
    [[ $inbox =~ [^[:space:]] ]] && return 1
  fi
  return 0
}

# 進行中的主殼，每行印一項 `/opsx-workflow:<stage> <slug>`，slug 字母序。archive 目錄、舊卡、已拆的卡不列；子殼在 subs/ 底下，glob 碰不到。
active_changes() { # <top>
  local d slug stage
  for d in "$1"/openspec/changes/*/; do
    d="${d%/}"; slug="${d##*/}"
    [ -d "$d" ] && [ "$slug" != archive ] || continue
    if collect_is_legacy "$d"; then continue; fi
    stage="$(stage_name "$1" "$slug")"
    if [ "$stage" != split ]; then printf '/opsx-workflow:%s %s\n' "$stage" "$slug"; fi
  done
}
