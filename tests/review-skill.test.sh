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

# --- 2.1 task 已勾但沒實作：進 Consider，回 /apply，review 不修；分類 tie-break ---
assert_fixed '已勾但沒實作」 is always Consider, never Act on' "$STEP3"
assert_not_fixed 'always Act on' "$STEP3"
assert_fixed '回 `/apply <slug>`' "$STEP3"
assert_fixed 'read the diff yourself' "$STEP3"
assert_fixed 'BUG = task checked and the diff has no code for it' "$STEP2"
assert_fixed 'Review never implements a task' "$GUARD"

# --- 2.2 step 4：範圍限制與清單在修改之前；清單綁定 finding 引用的位置；測試整輪一個 ---
assert_fixed 'Scope first, before any edit' "$STEP4"
assert_fixed "the finding's cited file:line" "$STEP4"
assert_fixed 'change nothing for it' "$STEP4"
assert_fixed 'at most 一個 回歸測試 in total' "$STEP4"
assert_not_fixed 'per fix' "$STEP4"
scope_ln=$(line_of 'Scope first, before any edit' "$STEP4"); fix_ln=$(line_of 'Then apply the fixes' "$STEP4")
[ -n "$scope_ln" ] && [ -n "$fix_ln" ] && [ "$scope_ln" -lt "$fix_ln" ] || fail "scope rule must come before 'Then apply the fixes' (scope=$scope_ln fix=$fix_ln)"

# --- 2.3 hook 擋下：引用的共用文件要解析得到，不在本文重寫 ---
assert_fixed '../../references/harness-claude-code.md' "$STEP4"
[ -f "$(dirname "$SK")/../../references/harness-claude-code.md" ] || fail "harness-claude-code.md does not resolve from skills/review/"
assert_fixed 'do not reword the command' "$STEP4"
