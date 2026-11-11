#!/usr/bin/env bash
# skills/review/SKILL.md 的結構：修一輪的範圍、未實作 task、D 對照、hook 引用。
# 只證明規則寫在對的段落且沒被反向改寫；agent 守不守由 eval 驗。對應 openspec/changes/review-fix-scope/specs/opsx-review-fix。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/review/SKILL.md"
assert_file "$SK"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
assert_not_fixed() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }
line_of() { grep -nF -- "$1" "$2" | head -1 | cut -d: -f1; }

section() { awk -v h="## $1" 'index($0,h)==1{on=1;print;next} /^## (Step|Guardrails)/{on=0} on' "$SK"; }
STEP2="$FX/step2"; STEP3="$FX/step3"; STEP4="$FX/step4"; STEP5="$FX/step5"; GUARD="$FX/guard"
section "Step 2" > "$STEP2"; section "Step 3" > "$STEP3"; section "Step 4" > "$STEP4"; section "Step 5" > "$STEP5"; section "Guardrails" > "$GUARD"
for f in "$STEP2" "$STEP3" "$STEP4" "$STEP5" "$GUARD"; do [ -s "$f" ] || fail "section missing: $f"; done

# --- 1.1 Agent A 被要求回傳 D_TABLE（含照做的），每個 finding 註明 D-id ---
assert_fixed 'Also return `D_TABLE`' "$STEP2"
assert_fixed 'followed as well as violated' "$STEP2"
assert_fixed 'status: <followed|violated>' "$STEP2"
assert_fixed 'd_id: <related D-id, or none>' "$STEP2"
assert_fixed 'Agents B and C write `d_id: none`' "$STEP3"
assert_fixed 'keep every row, followed ones included' "$STEP3"

# --- 1.2 report 的 D 對照表；四個桶都有 D-id 欄位；有修前清單 ---
assert_grep '^## D 對照' "$STEP5"
assert_fixed '照做 / 偏離' "$STEP5"
assert_fixed '修前清單' "$STEP5"
n=$(grep -cF 'D-id <Dn|none>' "$STEP5"); [ "$n" -ge 4 ] || fail "D-id slot in all four buckets: found $n of 4"

# --- 2.1 範圍：因果判準，退回看 diff 行；task 已勾但沒實作屬範圍內 ---
assert_fixed 'cannot happen on main' "$STEP3"
assert_fixed 'a caller this change broke' "$STEP3"
assert_fixed 'git diff -U0 main...HEAD' "$STEP3"
assert_fixed 'happens on main too' "$STEP3"
assert_not_fixed 'always Consider, never Act on' "$STEP3"
assert_fixed 'BUG = task checked and the diff has no code for it' "$STEP2"
assert_fixed 'Review never implements a task' "$GUARD"

# --- 2.2 step 4：範圍內寫成 task 回 apply，範圍外開卡，驗不了的降 Consider ---
assert_fixed '## R<N>. review 退回' "$STEP4"
assert_fixed '待修（範圍內）' "$STEP4"
assert_fixed '/opsx-workflow:apply <slug>' "$STEP4"
assert_fixed 'opsx new' "$STEP4"
assert_fixed '優先度 P2' "$STEP4"
assert_fixed 'review changes no code' "$STEP4"
assert_not_fixed 'at most 一個 回歸測試 in total' "$STEP4"
assert_fixed '確認: <sha>' "$STEP4"
assert_fixed '待修（範圍內）' "$STEP5"
assert_fixed '確認: <sha>' "$STEP5"

# --- card-area-field：範圍外開卡帶 --area，slug 可能是既有的卡；priority.md 事實欄位表有 area（specs/card-auto-merge「review 的範圍外開卡」）---
grep -F -- '- **範圍外.**' "$STEP4" > "$FX/oos"; [ -s "$FX/oos" ] || fail "Step 4 找不到範圍外段"
for k in 'opsx new' '--area' 'openspec/areas.txt' 'existing card'; do assert_fixed "$k" "$FX/oos"; done
assert_not_fixed 'openspec new change' "$FX/oos"
# me-20261111-1326：開卡步驟不教 agent 帶 --source
assert_fixed '不要帶 `--source`' "$FX/oos"
assert_fixed '併進' "$FX/oos"; assert_fixed '--evidence' "$FX/oos"
assert_fixed 'before you know whether it merges' "$FX/oos"; assert_fixed 'opsx split-out' "$FX/oos"
grep -q '^| `area` |' "$OPSX_ROOT/references/priority.md" || fail "references/priority.md 事實欄位表缺 area 列"

# --- 2.3 hook 擋下：引用的共用文件要解析得到，不在本文重寫 ---
assert_fixed '../../references/harness-claude-code.md' "$STEP4"
[ -f "$(dirname "$SK")/../../references/harness-claude-code.md" ] || fail "harness-claude-code.md does not resolve from skills/review/"
assert_fixed 'do not reword the command' "$STEP4"

# --- node-steps-gates：opsx check 的 Must-fix 候選由 review 讀並判斷 ---
assert_fixed 'Must-fix 候選' "$STEP3"
assert_fixed 'sends it back to explore' "$STEP3"
assert_fixed 'A `Must-fix 候選` line is not an incomplete shell: leave it for Step 3.' "$SK"
assert_fixed 'A line starting `explore.md 步驟` goes back to `/opsx-workflow:explore <slug>`, not to `/opsx-workflow:apply`.' "$SK"

# --- gherkin-check / check-wiring：前置對每張卡跑 opsx check，spec 的行退回 apply（specs/spec-gherkin-check）---
STEP0="$FX/step0"; section "Step 0" > "$STEP0"; [ -s "$STEP0" ] || fail "section missing: Step 0"
assert_fixed 'Every card: also run `opsx check <slug>`.' "$STEP0"
assert_not_fixed 'A main change with `subs/`: also run `opsx check' "$STEP0"
assert_fixed 'A line pointing at a `spec.md` is a spec that breaks the Gherkin rules: stop the same way, list those lines, and send it back to `/opsx-workflow:apply <slug>`.' "$STEP0"
