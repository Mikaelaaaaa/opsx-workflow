#!/usr/bin/env bash
# 步驟名與順序：check.sh、explore 模板、explore SKILL.md 的 Steps 表三處一致。
# 驗收：openspec/changes/node-steps-gates/specs/node-step-gates/spec.md「步驟名與 skill 一致」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

in_check="$(sed -n 's/.*split("\([^"]*\)".*/\1/p' "$OPSX_ROOT/bin/lib/check.sh" | head -1)"
in_tpl="$(sed -n 's/^- [0-9] \(.*\)：$/\1/p' "$OPSX_ROOT/schemas/opsx/templates/explore.md" | paste -sd'|' -)"
in_skill="$(sed -n 's/^| [0-9] | \([^|]*\) | .*/\1/p' "$OPSX_ROOT/skills/explore/SKILL.md" | sed 's/ *$//' | paste -sd'|' -)"
[ -n "$in_check" ] || fail "check.sh 找不到步驟名清單"
assert_eq "$in_tpl" "$in_check" "模板與 check.sh 的步驟名不一致"
assert_eq "$in_skill" "$in_check" "SKILL.md 與 check.sh 的步驟名不一致"
echo ok
