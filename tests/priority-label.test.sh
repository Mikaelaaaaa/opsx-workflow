#!/usr/bin/env bash
# 開卡填事實、拆工寫 milestone、P0 審核 gate、判斷標準只寫一份。只證明規則寫在對的地方；agent 守不守由 eval 驗。
# 驗收：openspec/changes/workplan-priority/subs/priority-label/specs/priority-label/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-10 09:00"
REF="$OPSX_ROOT/references/priority.md"; TPL="$OPSX_ROOT/schemas/opsx/templates/inbox.md"; EX="$OPSX_ROOT/skills/explore/SKILL.md"
assert_file "$REF"; assert_file "$TPL"; assert_file "$EX"
has() { grep -qF -- "$1" "$2" || fail "'$1' not in $2"; }
# section <file> <heading>：從 `## <heading>` 到下一個 `## `（略過 code fence 裡的 `## `）
section() { awk -v h="## $2" '/^```/{fence=!fence} index($0,h)==1{on=1;print;next} !fence && /^## /{on=0} on' "$1"; }
frontmatter() { awk 'NR==1&&/^---$/{on=1;next} on&&/^---$/{exit} on' "$1"; }

# --- Scenario：模板三個欄位 ---
frontmatter "$TPL" > "$FX/tpl-fm"
for k in kind_of_work impact evidence; do assert_grep "^$k:" "$FX/tpl-fm"; done
has 'incident | planned' "$FX/tpl-fm"
for v in security data prod_or_main workaround_exists blocks_all_agents; do grep -q "^impact:.*$v" "$FX/tpl-fm" || fail "impact 註解缺 $v"; done
grep -q '^evidence:.*有 impact 就要 evidence' "$FX/tpl-fm" || fail "evidence 註解缺「有 impact 就要 evidence」"

# --- Scenario：opsx new 寫 planned ---
A="$(mk_opsx_repo a)"
out="$(opsx new --repo "$A" -- 一句話)"; assert_eq "$?" 0 "new: $out"
frontmatter "$A/openspec/changes/$out/inbox.md" > "$FX/new-fm"
assert_grep '^kind_of_work: planned$' "$FX/new-fm"
assert_eq "$(grep -A1 '^related:' "$FX/new-fm" | tail -1)" 'kind_of_work: planned' "kind_of_work 緊接在 related: 之後"
assert_eq "$(opsx priority "$out" --repo "$A" | cut -f1)" P2 "opsx new 的卡算得出等級（不在 workplan → P2）"

# --- Scenario：explore skill 有 milestone 段 ---
section "$EX" Milestones > "$FX/ms"; [ -s "$FX/ms" ] || fail "explore 缺 ## Milestones"
for k in 'milestones:' current_milestone 'milestone:' 做完時使用者能做到什麼 'set only by the user' quote; do has "$k" "$FX/ms"; done
lno() { grep -nF -- "$1" "$EX" | head -1 | cut -d: -f1; }
a="$(lno '## Breaking Down Work + Workplan')"; b="$(lno '## Milestones')"; c="$(lno '## Splitting a big card')"
[ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] || fail "Milestones 要在 Breaking Down Work 之後、Splitting 之前：$a $b $c"

# --- Scenario：拆法 gate 列出 milestone ---
section "$EX" 'Splitting a big card' > "$FX/split"
grep -E '^ +- session ' "$FX/split" | grep -qF 'milestone:' || fail "拆法 gate 的 session 行要帶 milestone:"

# --- Scenario：四個 skill 都寫填事實 / skill 指到 reference ---
for s in apply audit forensics explore; do
  f="$OPSX_ROOT/skills/$s/SKILL.md"; assert_file "$f"
  for k in kind_of_work 'opsx priority' references/priority.md p0-review; do has "$k" "$f"; done
done

# --- Scenario：skill 不叫 agent 選等級 / skill 不重抄規則 ---
find "$OPSX_ROOT/skills" -name SKILL.md > "$FX/skills"; [ -s "$FX/skills" ] || fail "找不到任何 SKILL.md"
while read -r f; do
  ! grep -qF 'priority: P' "$f" || fail "$f 叫 agent 寫 priority: P"
  ! grep -qF blocks_all_agents "$f" || fail "$f 重抄了 blocks_all_agents"
done < "$FX/skills"

# --- Scenario：規則在 reference ---
for k in '## 事實欄位' '## 等級怎麼算' '## milestone' '## 使用者覆寫' '## P0 審核'; do assert_grep "^$k" "$REF"; done
for k in security data prod_or_main workaround_exists blocks_all_agents current_milestone depends-on; do has "$k" "$REF"; done
section "$REF" 等級怎麼算 > "$FX/calc"; has 'current_milestone' "$FX/calc"; has 'P1' "$FX/calc"   # D8
section "$REF" milestone > "$FX/ref-ms"; has '引號' "$FX/ref-ms"

# --- Scenario：審核 gate 的格式寫在 reference ---
section "$REF" 'P0 審核' > "$FX/p0"; [ -s "$FX/p0" ] || fail "reference 缺 ## P0 審核"
for k in '## p0-review' 'type: decision' 'status: open' '確認 P0 (Recommended) | 降為 P1 | 降為 P2' 'opsx priority <slug> --set <level> --reason'; do has "$k" "$FX/p0"; done
grep -q '^問題:.*理由' "$FX/p0" || fail "p0-review 的問題要帶理由"

# --- D1：不寫具體 milestone ---
! grep -qE 'name: "[0-9A-Za-z]' "$REF" "$EX" || fail "reference / explore 不能寫具體 milestone 名稱"
echo ok
