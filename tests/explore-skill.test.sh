#!/usr/bin/env bash
# skills/explore/SKILL.md 的拆工規則：D5 對照、拆法 gate、確認後建殼。只證明規則寫在對的段落且舊句子已移除；agent 守不守由 eval 驗。
# 驗收：openspec/changes/split-plan/specs/work-split/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/explore/SKILL.md"
assert_file "$SK"
has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
section() { awk -v h="## $1" '/^```/{fence=!fence} index($0,h)==1{on=1;print;next} !fence && /^## /{on=0} on' "$SK"; }
ENDING="$FX/ending"; SPLIT="$FX/split"; ENGAGE="$FX/engage"
section "Ending: explore.md" > "$ENDING"; section "Splitting a big card" > "$SPLIT"; section "How to Engage" > "$ENGAGE"
for f in "$ENDING" "$SPLIT" "$ENGAGE"; do [ -s "$f" ] || fail "section missing: $f"; done

# --- Scenario：explore skill 有 D5 對照段 ---
has 'D5 check' "$ENDING"
has 'more than one subsystem' "$ENDING"
has 'different risk' "$ENDING"
has 'more than 6 tasks' "$ENDING"
has 'any one' "$ENDING"

# --- Scenario：拆法 gate 段存在 ---
has 'type: decision' "$SPLIT"
for k in session 'main change' 'sub-change' 'depends-on'; do has "$k" "$SPLIT"; done
has 'Until the gate is answered, create no shell and do not touch the workplan' "$SPLIT"

# --- Scenario：移除 autopilot 不確認的句子 ---
! grep -qF 'written without the confirmation step' "$SK" || fail "autopilot 不確認的句子要移除"
has 'Splitting a big card' "$ENGAGE"

# --- Scenario：建殼步驟完整（四步，順序固定） ---
line() { grep -nF -- "$1" "$SPLIT" | head -1 | cut -d: -f1; }
a="$(line 'openspec new change')"; b="$(line 'subs/<sub>/')"; c="$(line 'openspec/workplan.yaml')"; d="$(line 'split_into:')"
for v in "$a" "$b" "$c" "$d"; do [ -n "$v" ] || fail "建殼四步缺一步: $a $b $c $d"; done
[ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ] || fail "四步順序：主殼 $a < 子殼 $b < workplan $c < split_into $d"
has 'parent:' "$SPLIT"

# --- Scenario：explore skill 有步驟表（驗收：openspec/changes/node-steps-wired/specs/node-step-wiring/spec.md） ---
STEPS="$FX/steps"; section "Steps" > "$STEPS"
[ -s "$STEPS" ] || fail "section missing: Steps"
for k in '../how/SKILL.md' '../blast-radius/SKILL.md' '../why/SKILL.md' 'references/prototype.md' '../unslop/SKILL.md' '查資料' 'skip：' '## 步驟'; do has "$k" "$STEPS"; done
! grep -qF 'There are no fixed steps' "$SK" || fail "'no fixed steps' 要移除"
TPL="$OPSX_ROOT/schemas/opsx/templates/explore.md"
has '## 步驟' "$TPL"
# 驗收：node-step-text「模板與 skill 步驟名一致」——步驟名與順序逐行相同
awk -F'|' '/^\| [0-9]+ \|/{gsub(/^ +| +$/,"",$3); print $3}' "$STEPS" > "$FX/skill-names"
awk '/^## /{on=($0=="## 步驟");next} on && /^- [0-9]+ /{sub(/^- [0-9]+ /,""); sub(/：.*/,""); print}' "$TPL" > "$FX/tpl-names"
[ -s "$FX/skill-names" ] || fail "SKILL.md 步驟表沒有步驟列"
cmp -s "$FX/skill-names" "$FX/tpl-names" || fail "步驟名或順序不一致。SKILL.md 步驟表: $(tr '\n' ' ' < "$FX/skill-names")／模板 ## 步驟: $(tr '\n' ' ' < "$FX/tpl-names")"
REQ="$OPSX_ROOT/docs/rewrite-requirements-pstack-grill.md"
! grep -qF '八段固定標題' "$REQ" || fail "需求文件 §8.3 不該再寫八段固定標題"
echo ok
