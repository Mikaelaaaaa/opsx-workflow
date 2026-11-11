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
echo ok
