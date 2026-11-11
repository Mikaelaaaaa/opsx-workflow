#!/usr/bin/env bash
# propose 產子殼並以 opsx check 收尾；review 步驟 0 也跑 opsx check。只證明規則寫在對的段落；agent 守不守由 eval 驗。
# 驗收：openspec/changes/split-plan/specs/subchange-propose/spec.md「propose skill 有子殼段」「review 步驟 0 呼叫 check」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
P="$OPSX_ROOT/skills/propose/SKILL.md"; RV="$OPSX_ROOT/skills/review/SKILL.md"
has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$(dirname "$2")")/$(basename "$2")"; }
sec() { awk -v h="$2" 'index($0,h)==1{on=1;print;next} on && /^#{2,3} /{on=0} on' "$1"; }

# --- Scenario：propose skill 有子殼段 ---
SUB="$FX/sub"; sec "$P" "### 4c. Sub-change shells" > "$SUB"; [ -s "$SUB" ] || fail "propose 少 4c 子殼段"
has 'one item per sub-change' "$SUB"
for a in proposal.md specs/ design.md tasks.md; do has "$a" "$SUB"; done
has 'D-id' "$SUB"
has 'opsx check <name>' "$SUB"
has 'do not continue to `/opsx-workflow:apply`' "$SUB"
OUT="$FX/out"; sec "$P" "## Output" > "$OUT"; has 'opsx check' "$OUT"

# --- new-auto-merge：寫 tasks.md 前，每段 ## 併入 要嘛變成 task，要嘛先 opsx split-out ---
has '## 併入' "$P"; has 'opsx split-out' "$P"

# --- Scenario：review 步驟 0 呼叫 check ---
S0="$FX/s0"; sec "$RV" "## Step 0: the gate" > "$S0"; [ -s "$S0" ] || fail "review 少 Step 0"
has 'opsx check <slug>' "$S0"

# 驗收：openspec/changes/propose-gherkin/subs/propose-specs-rewrite/specs/propose-spec-guidance/spec.md 五個 Scenario
hasnt() { ! grep -qE -- "$1" "$2" || fail "'$1' should not be in $(basename "$2"): $(grep -nE -- "$1" "$2")"; }
RULES="$FX/rules"; sec "$P" "   Rules specific to opsx:" > "$RULES"; [ -s "$RULES" ] || fail "propose 少 Rules specific to opsx 段"
SPEC="$FX/spec-rule"; grep -F -- '**Specs follow' "$RULES" > "$SPEC"; [ -s "$SPEC" ] || fail "Rules 段少寫 spec 的那一條"
TASKS="$FX/tasks-rule"; awk '/tasks\.md: every task carries/{on=1;print;next} on && /^   - /{exit} on' "$RULES" > "$TASKS"; [ -s "$TASKS" ] || fail "Rules 段少 tasks.md 規則"

# --- Scenario：段落指向 instruction 與 reference（正例）---
has 'references/gherkin.md' "$SPEC"
has 'openspec instructions specs' "$SPEC"
has 'Examples table' "$SPEC"
has 'review can match each row to a test' "$SPEC"

# --- Scenario：段落不放範例也不留 WHEN/THEN 規則（反例）---
hasnt 'WHEN / THEN' "$RULES"
hasnt '^[[:space:]]*- \*\*(GIVEN|WHEN|THEN)\*\*' "$RULES"

# --- Scenario：段落不堆全大寫命令（反例）---
hasnt '(ALWAYS|NEVER|MUST)' "$SPEC"

# --- Scenario：tasks 規則提到 Examples 每一列（正例）---
has 'Examples' "$TASKS"
has 'covers every row' "$TASKS"

# --- Scenario：不重抄 instruction 的關鍵字表（反例）---
hasnt '\| Scenario Outline \| 參數化場景' "$P"
hasnt '正確的、適當的、合理的' "$P"
echo ok
