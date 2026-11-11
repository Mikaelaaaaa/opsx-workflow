#!/usr/bin/env bash
# apply 與 review 的說明都要指示全套測試在背景跑（specs/test-runner-progress/spec.md「說明指示全套在背景跑」）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_grep '背景跑' "$OPSX_ROOT/skills/apply/SKILL.md"
assert_grep '背景跑' "$OPSX_ROOT/skills/review/SKILL.md"
