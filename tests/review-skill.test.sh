#!/usr/bin/env bash
# skills/review/SKILL.md 的結構：修一輪的範圍、未實作 task、D 對照、hook 引用。
# 只證明規則寫在對的段落；agent 守不守由 eval 驗。對應 openspec/changes/review-fix-scope/specs/opsx-review-fix。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/review/SKILL.md"
assert_file "$SK"

section() { awk -v h="## $1" 'index($0,h)==1{on=1;print;next} /^## (Step|Guardrails)/{on=0} on' "$SK"; }
STEP2="$FX/step2"; STEP3="$FX/step3"; STEP4="$FX/step4"; STEP5="$FX/step5"
section "Step 2" > "$STEP2"; section "Step 3" > "$STEP3"; section "Step 4" > "$STEP4"; section "Step 5" > "$STEP5"
for f in "$STEP2" "$STEP3" "$STEP4" "$STEP5"; do [ -s "$f" ] || fail "section missing: $f"; done

# --- 1.1 Agent A 回傳 D_TABLE，每個 finding 註明相關 D-id ---
assert_grep 'D_TABLE' "$STEP2"
assert_grep 'd_id:' "$STEP2"

# --- 1.2 report 的 D 對照表與修前清單 ---
assert_grep '^## D 對照' "$STEP5"
assert_grep '修前清單' "$STEP5"

# --- 2.1 task 已勾但沒實作：進 Consider，回 /apply，不修 ---
assert_grep '已勾但沒實作.*Consider' "$STEP3"
assert_grep '回 `/apply <slug>`' "$STEP3"

# --- 2.2 step 4：範圍限制與清單在修改之前；超出轉 Consider；回歸測試上限一個 ---
assert_grep '修前清單' "$STEP4"
assert_grep '超出.*Consider' "$STEP4"
assert_grep '回歸測試.*一個' "$STEP4"
list_ln=$(grep -n '修前清單' "$STEP4" | head -1 | cut -d: -f1)
test_ln=$(grep -n 'test agent' "$STEP4" | head -1 | cut -d: -f1)
[ -n "$list_ln" ] && [ -n "$test_ln" ] && [ "$list_ln" -lt "$test_ln" ] || fail "修前清單 must come before the test run in step 4 (list=$list_ln test=$test_ln)"

# --- 2.3 hook 擋下：引用共用文件，不在本文重寫 ---
assert_grep 'references/harness-claude-code.md' "$STEP4"
