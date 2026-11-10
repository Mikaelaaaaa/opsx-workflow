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
st_open_gates() { [ -f "$1/gates.md" ] || { printf 0; return; }; grep -cE '^status:[[:space:]]*open[[:space:]]*$' "$1/gates.md" || true; }
# slug 是 PR 名或 PR 底下的 change 名，印該 PR 的 <field>（branch、status）；對不到印空。
# 用 awk 不用 chain.py 的 load_workplan：collect 每張卡都判 stage，router 每句 prompt 都判，不能每次 fork python。
wp_pr_field() { # <top> <slug> <field>
  [ -f "$1/openspec/workplan.yaml" ] || return 0
  awk -v s="$2" -v k="$3" '
    function ind() { match($0, /^ */); return RLENGTH }
    function val(  v) { v = $0; sub(/^ *(- )?[A-Za-z_-]+: */, "", v); sub(/ +#.*$/, "", v); gsub(/^["\047]|["\047]$/, "", v); return v }
    BEGIN { pi = -1; ci = -1 }
    /^ *prs:/ { pi = ind(); ci = -1; pr = ""; next }
    /^ *changes:/ { ci = ind(); next }
    /^ *- name:/ {
      i = ind()
      if (ci >= 0 && i > ci) { if (hit == "" && val() == s) hit = pr; next }
      ci = -1
      if (pi >= 0 && i > pi) { pr = val(); ki = i + 2; if (hit == "" && pr == s) hit = pr; next }
      pi = -1; pr = ""; next
    }
    ci >= 0 && $0 !~ /^ *(#|$)/ && ind() <= ci && $0 !~ /^ *- / { ci = -1 }
    pr != "" && ci < 0 && ind() == ki && index($0, k ":") == ki + 1 { f[pr] = val() }
    END { if (hit != "") print f[hit] }
  ' "$1/openspec/workplan.yaml"
}
st_workplan_merged() { [ "$(wp_pr_field "$1" "$2" status)" = merged ]; } # <top> <slug>
st_split_into() { [ -f "$1/inbox.md" ] && awk 'NR==1 && !/^---/{exit} NR>1 && /^---/{exit} /^split_into:/{sub(/^split_into: */,""); sub(/\r$/,""); sub(/ +#.*$/,""); if ($0 ~ /^(\[ *\]|""|\047\047|~|null)?$/) exit; print; exit}' "$1/inbox.md" || true; }

# 印「階段 · slug · kind · Read 清單」。沒卡印 explore。
stage_of() { # <top> <slug>
  local top="$1" slug="$2" d="$1/openspec/changes/$2" kind
  if [ -z "$slug" ] || [ ! -d "$d" ]; then printf 'explore · （沒有對到卡，先建殼）· — · skills/explore/SKILL.md\n'; return; fi
  kind="$(st_card_kind "$d")"; kind="${kind:-dev}"
  local reads="skills/apply/SKILL.md · skills/apply/references/playbooks/${kind}.md · skills/tdd/SKILL.md" split
  split="$(st_split_into "$d")"
  if [ -n "$split" ]; then printf 'split · %s · %s · 已拆成 %s，這張不再往下做\n' "$slug" "$kind" "$split"; return; fi
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
