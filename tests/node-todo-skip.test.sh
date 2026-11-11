#!/usr/bin/env bash
# 六個節點（explore grill propose review pr archive）的 SKILL.md 都要求把步驟抄進 TodoWrite，不做的留 `skip: <reason>`。
# 只證明規則寫進去了；agent 守不守由 eval 驗。apply 已有，不在清單。
# 驗收：openspec/changes/node-steps-text/subs/node-todo-skip/specs
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
missing=""
for node in explore grill propose review pr archive; do
  sk="$OPSX_ROOT/skills/$node/SKILL.md"
  assert_file "$sk"
  grep -qF -- 'TodoWrite' "$sk" && grep -qF -- 'skip:' "$sk" || missing="$missing $node"
done
[ -z "$missing" ] || fail "TodoWrite / skip: 缺在:$missing"

# 驗收：「節點要求抄進 TodoWrite」「grill 總結過寫作 pass」——grill 沒有編號步驟表，TodoWrite 那句要有 ## Steps 可抄
GRILL="$OPSX_ROOT/skills/grill/SKILL.md"
awk '/^```/{f=!f} !f && /^## /{on=($0=="## Steps");next} on' "$GRILL" > "$FX/grill-steps"
[ -s "$FX/grill-steps" ] || fail "grill 沒有 ## Steps"
assert_eq "$(grep -cE '^[0-9]+\. ' "$FX/grill-steps")" 5 "grill ## Steps 要照 §8.3 有五個編號步驟"
for k in '../technical-writing/SKILL.md' '../unslop/SKILL.md'; do assert_grep "$k" "$FX/grill-steps"; done
grep -F 'TodoWrite' "$GRILL" | grep -qF '## Steps' || fail "grill 的 TodoWrite 那句沒有指向 ## Steps"
# ## Steps 要和同檔正文一致：bucket 1、2 自己查自己跑、不退回 explore；autopilot 不呼叫 AskUserQuestion
assert_grep 'remove it from 待決' "$FX/grill-steps"
assert_grep 'autopilot' "$FX/grill-steps"
assert_not_grep 'goes back to explore' "$FX/grill-steps"
# 階段指令用 /opsx-workflow:<stage> 的全名（main 的 stage-cmd-prefix）
assert_grep '/opsx-workflow:propose' "$FX/grill-steps"
echo ok
