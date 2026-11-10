#!/usr/bin/env bash
# Stop：branch 對到的卡，agent 要停時依 stage_name 看下一站。要擋就 block 並說原因：
#   apply 站 tasks.md 仍有 - [ ]（有會擋的 open gate 時這一項放行）、status.json tests 不是 green、有 commit 但 review 沒跑；
#   grill / propose / pr / babysit 站該 invoke 下一站而沒有會擋的 open gate。
# 同一站最多擋 MAX_BLOCKS 次，再停就由這支 hook 寫「卡在接 /<站>」gate 放行；不看 stop_hook_active。
# 要求檔 §8.5。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
source "$OPSX_ROOT/bin/lib/common.sh"

MAX_BLOCKS=3

# 印要擋的原因；空字串表示放行。
stop_reason() { # <dir> <slug> <stage>
  local d="$1" slug="$2" stage="$3" open missing last_commit report_ts
  if [ -f "$d/tasks.md" ]; then
    if [ -d "$d/subs" ] && [ "$(st_open_gates "$d")" -eq 0 ]; then
      source "$OPSX_ROOT/bin/lib/check.sh"
      missing="$(check_subs "$d")"
      if [ -n "$missing" ]; then
        printf '%s' "opsx：${slug} 的子殼不齊（opsx check ${slug}）：
$missing
補齊再停。"
        return 0
      fi
    fi
    open="$(tasks_open "$d")"
    if [ "$open" -gt 0 ]; then
      [ "$(st_open_gates_blocking "$d")" -gt 0 ] && return 0
      printf '%s' "opsx：$slug 的 tasks.md 還有 $open 個 task 沒勾。要停下來就先把做到一半的 task 做完勾起來（測試綠才准勾），或用 Edit 或 Write 寫 gates.md 說明卡在哪；不要帶著半個 task 收工。要繼續就 invoke /apply ${slug}，不要問要不要接。"
      return 0
    fi
    if [ "$(status_tests "$d")" != green ]; then
      printf '%s' "opsx：$slug tasks 全勾，但 status.json 的 tests 不是 green（$(status_tests "$d")）。跑 test agent 把整張卡的測試跑到綠，`opsx status apply n/n <label> --tests green`，再停。"
      return 0
    fi
    if [ ! -f "$d/report.md" ]; then
      printf '%s' "opsx：$slug tasks 全勾、測試綠，但還沒 review。跑 /review $slug 產 report.md 再停。"
      return 0
    fi
    last_commit="$(git -C "$(hook_cwd)" log -1 --format=%ct 2>/dev/null || echo 0)"
    report_ts="$(stat -f %m "$d/report.md" 2>/dev/null || stat -c %Y "$d/report.md" 2>/dev/null || echo 0)"
    if [ "$last_commit" -gt "$report_ts" ]; then
      printf '%s' "opsx：$slug 在 report.md 之後又有新 commit，review 沒涵蓋到。再跑一次 /review $slug 再停。"
      return 0
    fi
  fi
  case "$stage" in
    grill|propose|pr|babysit) ;;
    *) return 0 ;;
  esac
  [ "$(st_open_gates_blocking "$d")" -gt 0 ] && return 0
  # review 把沒做完的 task 記成「回 `/apply`」：這時不逼 /pr
  [ "$stage" = pr ] && grep -qF '回 `/apply' "$d/report.md" && return 0
  [ "$stage" = babysit ] && grep -q '^babysit:' "$d/report.md" && return 0
  printf '%s' "opsx：${slug} 的下一站是 /${stage}。現在用 Skill 工具 invoke opsx-workflow:${stage}，args ${slug}，不要問要不要接。真有只有使用者能答的問題，用 Edit 或 Write 寫進 gates.md（標題不要寫「要不要接」）。"
  [ "$stage" = babysit ] && printf '%s' " babysit 做完一次 pass 要在 report.md 的 ## MR 底下寫一行 babysit: <時間>。"
  return 0
}

# 這個標題的 gate 有沒有 open
titled_gate_open() { # <dir> <title>
  [ -f "$1/gates.md" ] || return 1
  awk -v t="## $2" '/^## /{cur = ($0 == t)} cur && /^status:[ \t]*open[ \t]*$/{found = 1} END{exit !found}' "$1/gates.md"
}

write_auto_gate() { # <dir> <slug> <stage>
  local f="$1/gates.md"
  [ -s "$f" ] && printf '\n' >> "$f"
  printf '## 卡在接 /%s\nstatus: open\nopened_at: %s\nquestion: opsx：%s 連續 %s 次停在 /%s 之前沒有 invoke。需要人看一下為什麼接不下去。\n' \
    "$3" "$(now_iso)" "$2" "$MAX_BLOCKS" "$3" >> "$f"
}

d="$(card_dir)"
[ -n "$d" ] || exit 0
slug="$(card_slug)"
stage="$(stage_name "$(repo_top)" "$slug")"
case "$stage" in
  grill|propose|apply|review|pr|babysit) ;;
  *) exit 0 ;;
esac

state="$OPSX_STATE_DIR/stop-chain/$(repo_name)-$slug"
reason="$(stop_reason "$d" "$slug" "$stage")"
if [ -z "$reason" ]; then
  rm -f "$state"
  exit 0
fi

last_stage=""; n=0; gated=""
[ -f "$state" ] && read -r last_stage n gated < "$state"
[ "$last_stage" = "$stage" ] || { n=0; gated=""; }

if [ "$n" -ge "$MAX_BLOCKS" ]; then
  if [ -z "$gated" ]; then
    write_auto_gate "$d" "$slug" "$stage"
    printf '%s %s gated\n' "$stage" "$n" > "$state"
    exit 0
  fi
  titled_gate_open "$d" "卡在接 /$stage" && exit 0
  n=0; gated=""   # 人答完了，重算
fi

mkdir -p "$(dirname "$state")"
printf '%s %s\n' "$stage" "$((n + 1))" > "$state"
stop_block "$reason"
