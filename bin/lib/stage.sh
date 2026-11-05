#!/usr/bin/env bash
# 主流程狀態判斷，純函式，參數明示（top、slug）。hook 的 router 和 drive.sh 都用這一份，
# 所以「下一步是什麼」只有一個答案。要求檔 §8.3 Router 表。

st_card_kind() { local d="$1"; [ -f "$d/.openspec.yaml" ] && sed -n 's/^kind: *//p' "$d/.openspec.yaml" | head -1 || true; }
st_status_tests() { local d="$1"; [ -f "$d/status.json" ] && jq -r '.tests // "unknown"' "$d/status.json" 2>/dev/null || printf 'unknown'; }
st_tasks_open() { [ -f "$1/tasks.md" ] || { printf 0; return; }; grep -cE '^\s*- \[ \]' "$1/tasks.md" || true; }
st_tasks_done() { [ -f "$1/tasks.md" ] || { printf 0; return; }; grep -cE '^\s*- \[x\]' "$1/tasks.md" || true; }
st_pending_nonempty() {
  [ -f "$1/explore.md" ] || return 1
  awk '/^## 待決/{f=1;next} /^## /{f=0} f' "$1/explore.md" | grep -vE '^\s*$|^\s*<!--|^\s*-\s*$|^\s*（' | grep -q .
}
st_mr_url() { [ -f "$1/report.md" ] && grep -oE 'https?://[^ )]+/(merge_requests|pull)/[0-9]+' "$1/report.md" | head -1 || true; }
st_mr_in_report() { [ -n "$(st_mr_url "$1")" ]; }
st_open_gates() { [ -f "$1/gates.md" ] || { printf 0; return; }; grep -cE '^status: *open' "$1/gates.md" || true; }
st_workplan_merged() { # <top> <slug>
  [ -f "$1/openspec/workplan.yaml" ] && awk -v s="$2" '$0 ~ "name: *"s"$"{f=1;next} f && /status:/{print; exit} f && /^ *- /{exit}' "$1/openspec/workplan.yaml" | grep -q merged
}

# 印「階段 · slug · kind · Read 清單」。沒卡印 explore。
stage_of() { # <top> <slug>
  local top="$1" slug="$2" d="$1/openspec/changes/$2" kind
  if [ -z "$slug" ] || [ ! -d "$d" ]; then printf 'explore · （沒有對到卡，先建殼）· — · skills/explore/SKILL.md\n'; return; fi
  kind="$(st_card_kind "$d")"; kind="${kind:-dev}"
  local reads="skills/apply/SKILL.md · skills/apply/references/playbooks/${kind}.md · skills/tdd/SKILL.md"
  if st_workplan_merged "$top" "$slug"; then printf 'archive · %s · %s · skills/archive/SKILL.md\n' "$slug" "$kind"; return; fi
  if [ -f "$d/report.md" ]; then
    if st_mr_in_report "$d"; then printf 'babysit · %s · %s · skills/babysit/SKILL.md（MR 已開，等合併；有留言用 babysit）\n' "$slug" "$kind"
    else printf 'pr · %s · %s · skills/pr/SKILL.md · skills/pr/references/mr-note.md\n' "$slug" "$kind"; fi; return
  fi
  if [ -f "$d/tasks.md" ]; then
    if [ "$(st_tasks_open "$d")" -gt 0 ]; then printf 'apply · %s · %s · %s\n' "$slug" "$kind" "$reads"; return; fi
    if [ "$(st_status_tests "$d")" != green ]; then printf 'apply · %s · %s · %s（tasks 全勾但 tests 不是 green：先把測試補到綠）\n' "$slug" "$kind" "$reads"; return; fi
    printf 'review · %s · %s · skills/review/SKILL.md · skills/review/references/ponytail-review.md\n' "$slug" "$kind"; return
  fi
  if [ -f "$d/explore.md" ]; then
    if st_pending_nonempty "$d" && [ ! -f "$d/grill.md" ]; then printf 'grill · %s · %s · skills/grill/SKILL.md\n' "$slug" "$kind"; return; fi
    printf 'propose · %s · %s · skills/propose/SKILL.md\n' "$slug" "$kind"; return
  fi
  printf 'explore · %s · %s · skills/explore/SKILL.md\n' "$slug" "$kind"
}
stage_name() { stage_of "$1" "$2" | cut -d' ' -f1; }
