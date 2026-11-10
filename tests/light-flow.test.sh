#!/usr/bin/env bash
# 依 kind 減輕流程：router 跳過 grill、continue.md 的 Light flow 段、grill / propose / review 的文字契約。
# 只證明規則寫在對的地方且沒被反向改寫；agent 守不守由 eval 驗。驗收：openspec/changes/kind-light-flow/specs/light-flow/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$(dirname "$2")")/$(basename "$2")"; }
assert_not_fixed() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }
bash_fn() { ( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; "$@" ); }

# --- 1.1 chore 與 bug-fix 待決非空也不經 grill；其他 kind 照舊 ---
R="$(mk_repo light)"
mk_card() { # mk_card <slug> <kind>
  local d="$R/openspec/changes/$1"; mkdir -p "$d"
  printf 'schema: opsx\nkind: %s\n' "$2" > "$d/.openspec.yaml"
  printf '## 已知\n- x\n\n## 待決\n- 要不要 A？\n\n## 不做\n' > "$d/explore.md"
}
mk_card c-chore chore; mk_card c-bug bug-fix; mk_card c-dev dev; mk_card c-ops ops
assert_eq "$(bash_fn stage_name "$R" c-chore)" propose "chore 有待決 → propose"
assert_eq "$(bash_fn stage_name "$R" c-bug)" propose "bug-fix 有待決 → propose"
assert_eq "$(bash_fn stage_name "$R" c-dev)" grill "dev 有待決 → grill"
assert_eq "$(bash_fn stage_name "$R" c-ops)" grill "ops 有待決 → grill"

CONT="$OPSX_ROOT/references/continue.md"
GRILL="$OPSX_ROOT/skills/grill/SKILL.md"
PROP="$OPSX_ROOT/skills/propose/SKILL.md"
REV="$OPSX_ROOT/skills/review/SKILL.md"
for f in "$CONT" "$GRILL" "$PROP" "$REV"; do assert_file "$f"; done
section() { awk -v h="## $1" 'index($0,h)==1{on=1;print;next} /^## /{on=0} on' "$2"; }

# --- 1.2 grill 與 propose 的文字；continue.md 的 explore 兩列 ---
assert_fixed '| explore | `/grill <slug>` | 待決 non-empty and kind is not chore or bug-fix' "$CONT"
assert_fixed '| explore | `/propose <slug>` | 待決 empty, or kind is chore or bug-fix' "$CONT"
assert_fixed 'kind is chore or bug-fix' "$GRILL"
assert_fixed 'kind is chore or bug-fix' "$PROP"
assert_fixed '假設' "$PROP"
assert_fixed 'The exception is a card whose kind is chore or bug-fix' "$PROP"

# --- 2.1 continue.md 的 Light flow 段 ---
section "Light flow" "$CONT" > "$FX/sec-light"; [ -s "$FX/sec-light" ] || fail "continue.md has no '## Light flow' section"
assert_fixed 'tasks.md has at most 3 tasks' "$FX/sec-light"
assert_fixed 'first path component' "$FX/sec-light"
assert_fixed 'test paths' "$FX/sec-light"
assert_fixed 'Only kind chore or bug-fix' "$FX/sec-light"
assert_fixed 'Consider never blocks the flow' "$FX/sec-light"

# --- 2.2 小卡只一個合併 reviewer，其他卡三個 ---
assert_fixed 'one merged reviewer' "$REV"
assert_fixed '../../references/continue.md' "$REV"
assert_fixed 'Light flow' "$REV"
assert_not_fixed 'Three agents every time;' "$REV"
assert_fixed 'Three agents every time except a small card' "$REV"

# --- 2.3 輪數、第三次不審、Consider 不開 gate ---
assert_fixed '# Review · <slug> · 第 <N> 輪 · <date> · <commit>' "$REV"
section "Step 0" "$REV" > "$FX/sec-step0"; [ -s "$FX/sec-step0" ] || fail "review has no '## Step 0' section"
assert_fixed 'Read the round from report.md' "$FX/sec-step0"
assert_fixed 'two rounds' "$FX/sec-step0"
assert_fixed 'does not start a reviewer' "$FX/sec-step0"
assert_fixed 'Consider never opens a gate' "$REV"

# --- review 回歸：後面幾輪重寫 report.md 時保留 pr 附加的 ## MR ---
awk 'index($0,"## Step 5")==1{on=1;print;next} /^## (Step|Guardrails)/{on=0} on' "$REV" > "$FX/sec-step5"; [ -s "$FX/sec-step5" ] || fail "review has no '## Step 5' section"
assert_fixed 'keeps an existing `## MR` section verbatim' "$FX/sec-step5"
assert_fixed 'Consider never opens a gate' "$CONT"
