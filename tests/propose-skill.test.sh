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

# --- me-20261111-1326：worktree 沒有 openspec/，openspec 指令走主 checkout；測試一律 bash tests/run.sh，不帶前綴環境變數 ---
has '主 checkout' "$P"
has 'bash tests/run.sh' "$P"
has 'cd <worktree root>' "$P"
! grep -qE '^[[:space:]]*(`)?OPSX_ROOT=' "$P" || fail "propose SKILL.md 不能有 OPSX_ROOT= 開頭的測試指令範例"
echo ok
