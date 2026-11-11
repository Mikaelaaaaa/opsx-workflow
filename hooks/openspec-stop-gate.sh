#!/usr/bin/env bash
# Stop：branch 對到的卡，agent 要停時依 stage_name 看下一站。要擋就 block 並說原因：
#   apply 站 tasks.md 仍有 - [ ]（有會擋的 open gate 時這一項放行）、status.json tests 不是 green、有 commit 但 review 沒跑
#   （report.md 有「確認: <sha>」且 HEAD 等於該 sha 時不算）、report.md 的「待修（範圍內）」還有項目；
#   explore 站（explore.md 已存在、卡建立日期晚於 2026-11-10）## 步驟 不齊；
#   grill / propose / pr / babysit 站該 invoke 下一站而沒有會擋的 open gate；
#   babysit 站若 forge 說 MR 已合併（workplan 還沒標 merged），下一站改成 /archive。
# 同一站最多擋 MAX_BLOCKS 次，再停就由這支 hook 寫「卡在接 /<站>」gate 放行；不看 stop_hook_active。
# 要求檔 §8.5。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
source "$OPSX_ROOT/bin/lib/common.sh"
source "$OPSX_ROOT/bin/lib/mr.sh"
source "$OPSX_ROOT/bin/lib/check.sh"

MAX_BLOCKS=3
# 這支 hook 在 hooks.json 只有 10 秒：forge 查詢（mr_forge）限 5 秒，逾時當查不到
export OPSX_MR_TIMEOUT="${OPSX_MR_TIMEOUT:-5}"

# 印要擋的原因；空字串表示放行。
stop_reason() { # <dir> <slug> <stage>
  local d="$1" slug="$2" stage="$3" open missing last_commit report_ts confirmed head_sha
  # 等人答的 gate、背景的 subagent 與 reviewer 是合法的等待，事實欄位的檢查排在它們後面
  if [ "$(st_open_gates_blocking "$d")" -eq 0 ] && ! st_subagent_running "$d" && ! st_review_running "$d"; then
    missing="$(check_facts "$d")"
    if [ -n "$missing" ]; then
      printf '%s' "facts|opsx：${slug} 或它開出去的卡缺事實欄位（opsx check ${slug}）：
$missing
開卡用 opsx new --kind-of-work …（incident 加 --impact 與 --evidence）；手寫的卡補 inbox.md 的 kind_of_work、impact、evidence。補齊再停；事實查不到就用 Edit 或 Write 寫 gates.md 說缺哪一欄、為什麼，不要編 evidence。"
      return 0
    fi
  fi
  if [ "$stage" = explore ]; then
    [ -f "$d/explore.md" ] || return 0
    missing="$(check_explore "$d")"
    [ -n "$missing" ] || return 0
    [ "$(st_open_gates_blocking "$d")" -gt 0 ] && return 0
    printf '%s' "explore|opsx：${slug} 的 explore.md ## 步驟 不齊（opsx check ${slug}）：
$missing
補齊再停。"
    return 0
  fi
  if [ -f "$d/tasks.md" ]; then
    if [ -d "$d/subs" ] && [ "$(st_open_gates "$d")" -eq 0 ]; then
      missing="$(check_subs "$d")"
      if [ -n "$missing" ]; then
        printf '%s' "apply|opsx：${slug} 的子殼不齊（opsx check ${slug}）：
$missing
補齊再停。"
        return 0
      fi
    fi
    open="$(tasks_open "$d")"
    if [ "$open" -gt 0 ]; then
      [ "$(st_open_gates_blocking "$d")" -gt 0 ] && return 0
      # 子 change 的 subagent 在背景做：session 只能等通知，不算沒接站
      st_subagent_running "$d" && return 0
      printf '%s' "apply|opsx：$slug 的 tasks.md 還有 $open 個 task 沒勾。要停下來就先把做到一半的 task 做完勾起來（測試綠才准勾），或用 Edit 或 Write 寫 gates.md 說明卡在哪；不要帶著半個 task 收工。要繼續就 invoke /apply ${slug}，不要問要不要接。"
      return 0
    fi
    if [ "$(status_tests "$d")" != green ]; then
      printf '%s' "apply|opsx：$slug tasks 全勾，但 status.json 的 tests 不是 green（$(status_tests "$d")）。跑 test agent 把整張卡的測試跑到綠，\`opsx status apply n/n <label> --tests green\`，再停。"
      return 0
    fi
    # review 在背景開 reviewer 時主 agent 會結束 turn：status.json 還在 review 中間步就是在等，不算沒接站
    st_review_running "$d" && return 0
    if [ ! -f "$d/report.md" ]; then
      printf '%s' "review|opsx：$slug tasks 全勾、測試綠，但還沒 review。跑 /review $slug 產 report.md 再停。"
      return 0
    fi
    last_commit="$(git -C "$(hook_cwd)" log -1 --format=%ct 2>/dev/null || echo 0)"
    report_ts="$(stat -f %m "$d/report.md" 2>/dev/null || stat -c %Y "$d/report.md" 2>/dev/null || echo 0)"
    confirmed="$(sed -n 's/^確認: *//p' "$d/report.md" | head -1)"
    head_sha="$(git -C "$(hook_cwd)" rev-parse HEAD 2>/dev/null)"
    if [ "$last_commit" -gt "$report_ts" ] && { [ -z "$confirmed" ] || [ "$(git -C "$(hook_cwd)" rev-parse "$confirmed" 2>/dev/null)" != "$head_sha" ]; }; then
      printf '%s' "review|opsx：$slug 在 report.md 之後又有新 commit，review 沒涵蓋到。再跑一次 /review $slug 再停。"
      return 0
    fi
    if awk '/^### 待修（範圍內）/{on=1; next} /^#/{on=0} on && /^- /{f=1} END{exit !f}' "$d/report.md"; then
      printf '%s' "apply|opsx：$slug 的 report.md 在「待修（範圍內）」還有項目。invoke /apply ${slug} 修掉（tasks.md 的 R 群組），不要問要不要接。"
      return 0
    fi
  fi
  case "$stage" in
    grill|propose|pr|babysit) ;;
    *) return 0 ;;
  esac
  [ "$(st_open_gates_blocking "$d")" -gt 0 ] && return 0
  local mr="" mr_err=""
  if [ "$stage" = babysit ]; then
    # forge 說合併了但 workplan 還沒標 merged（標它是 /archive 與 coordinate 的事）：下一站是 /archive，不是 babysit
    if mr="$(mr_json "$d" 2>&1)"; then
      mr_err="$(printf '%s' "$mr" | jq -r '.error // empty')"
      [ -z "$(printf '%s' "$mr" | jq -r '.merged_at // empty')" ] || stage=archive
    else
      mr_err="mr_json 失敗：$mr"
    fi
  fi
  [ "$stage" = babysit ] && grep -q '^babysit:' "$d/report.md" && return 0
  printf '%s' "${stage}|opsx：${slug} 的下一站是 /${stage}。現在用 Skill 工具 invoke opsx-workflow:${stage}，args ${slug}，不要問要不要接。真有只有使用者能答的問題，用 Edit 或 Write 寫進 gates.md（標題不要寫「要不要接」）。"
  [ "$stage" = babysit ] && printf '%s' " babysit 做完一次 pass 要在 report.md 的 ## MR 底下寫一行 babysit: <時間>。"
  [ -z "$mr_err" ] || printf '%s' " MR 合併狀態查不到，先照 babysit 處理：${mr_err}"
  return 0
}

# 這一站的「卡在接」gate（標題 `卡在接 /<站>` 或 `卡在接 /<站> #<n>`）有沒有 open
titled_gate_open() { # <dir> <站>
  [ -f "$1/gates.md" ] || return 1
  awk -v t="## 卡在接 /$2" '/^## /{cur = ($0 == t || index($0, t " #") == 1)} cur && /^status:[ \t]*open[ \t]*$/{found = 1} END{exit !found}' "$1/gates.md"
}

# 標題帶流水號：答完的舊 gate 跟新 gate 同名的話，opsx answer 只找得到第一個。
# 取現有 #N 的最大值加一（gates.md 少了較早的 gate 時數量會小於最大號）；沒有數字的舊標題算 1。
write_auto_gate() { # <dir> <slug> <站>；站是 facts 時問的是事實欄位，不是接站
  local f="$1/gates.md" n=0 redo="重做 /$3 一次，做不完就把卡在哪寫進 gates.md" ask
  ask="$(printf 'opsx：%s 連續 %s 次停在 /%s 之前沒有 invoke，卡在哪？' "$2" "$MAX_BLOCKS" "$3")"
  if [ "$3" = facts ]; then
    redo="補 inbox.md 的 kind_of_work、impact、evidence（opsx check $2 看缺什麼）"
    ask="$(printf 'opsx：%s 或它開出去的卡的事實欄位連續 %s 次沒補齊，卡在哪？' "$2" "$MAX_BLOCKS")"
  fi
  [ -f "$f" ] && n="$(awk -v t="## 卡在接 /$3" '
    index($0, t) == 1 { rest = substr($0, length(t) + 1)
      if (rest ~ /^[ \t]*$/) k = 1
      else if (rest ~ /^ #[0-9]+[ \t]*$/) k = substr(rest, 3) + 0
      else next
      if (k > max) max = k }
    END { print max + 0 }' "$f")"
  {
    [ -s "$f" ] && printf '\n'
    printf '## 卡在接 /%s #%s\ntype: decision\nstatus: open\nopened_at: %s\n' "$3" "$((n + 1))" "$(now_iso)"
    printf '問題: %s\n' "$ask"
    printf '選項: %s (Recommended) | 停在這裡，把卡在哪寫進 gates.md 等人\n' "$redo"
    printf '建議: %s\n' "$redo"
    printf '預設: hook 不再擋這一站\n'
  } | opsx_append "$f"
}

d="$(card_dir)"
[ -n "$d" ] || exit 0
slug="$(card_slug)"
stage="$(stage_name "$(repo_top)" "$slug")"
case "$stage" in
  explore|grill|propose|apply|review|pr|babysit) ;;
  *) exit 0 ;;
esac

state="$OPSX_STATE_DIR/stop-chain/$(repo_name)-$slug"
out="$(stop_reason "$d" "$slug" "$stage")"
if [ -z "$out" ]; then
  rm -f "$state"
  exit 0
fi
want="${out%%|*}"     # hook 這次要求的站：不一定等於 stage_of 的站（report.md 在但要重跑 /review 時 stage 是 babysit）
reason="${out#*|}"

# 進度指紋：勾了 task 算有在做事；commit 只在 apply 站算（別的站 commit 不會把卡往前推，算的話上限永遠到不了）
fp="$(tasks_done "$d")"
[ "$want" = apply ] && fp="$fp-$(git -C "$(hook_cwd)" rev-parse HEAD)"
# 事實欄位：每補好一項，擋停理由就少一行，算有在做事
[ "$want" = facts ] && fp="$fp-$(printf '%s' "$reason" | wc -l | tr -d ' ')"
last_stage=""; n=0; gated="-"; last_fp=""
[ -f "$state" ] && read -r last_stage n gated last_fp < "$state"
if [ "$last_stage" != "$want" ] || [ "$last_fp" != "$fp" ]; then n=0; gated="-"; fi

if [ "$n" -ge "$MAX_BLOCKS" ]; then
  titled_gate_open "$d" "$want" || [ "$gated" = gated ] || write_auto_gate "$d" "$slug" "$want"
  if titled_gate_open "$d" "$want"; then
    printf '%s %s gated %s\n' "$want" "$n" "$fp" | opsx_replace "$state"
    exit 0
  fi
  n=0; gated="-"   # gate 被回答了，重算
fi

mkdir -p "$(dirname "$state")"
printf '%s %s - %s\n' "$want" "$((n + 1))" "$fp" | opsx_replace "$state"
stop_block "$reason"
