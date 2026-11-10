#!/usr/bin/env bash
# 主流程每一站結尾自己接下一站：六個 SKILL.md 指向 references/continue.md，continue.md 列齊銜接與停下規則。
# 只證明規則寫在對的地方、沒被反向改寫；agent 守不守由 eval 驗。對應 openspec/changes/skill-chain/specs/skill-chain。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONT="$OPSX_ROOT/references/continue.md"
assert_file "$CONT"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$(dirname "$2")")/$(basename "$2")"; }

check_node() { # check_node <skill> <next-command>
  local sk="$OPSX_ROOT/skills/$1/SKILL.md"
  assert_file "$sk"
  grep -F -- '../../references/continue.md' "$sk" | grep -qF -- "$2" \
    || fail "no single line in $1/SKILL.md has both continue.md and '$2'"
}
check_node explore '/grill <slug>'
check_node explore '/propose <slug>'
check_node grill '/propose <slug>'
check_node propose '/apply <name>'
check_node apply '/review <slug>'
check_node review '/pr <slug>'
check_node pr '/babysit <slug>'

assert_not_grep 'Do not run the review yourself' "$OPSX_ROOT/skills/apply/SKILL.md"

# feature session：babysit 停在等合併時先跑 opsx next，印出指令就接著做（apply-fanout session-dispatch）
awk '/^\| babysit /{f=1} f' "$CONT" | grep -qF 'opsx next' || fail "continue.md 的 babysit 列之後要寫 feature session 跑 opsx next"

for row in '| explore | `/grill <slug>`' '| explore | `/propose <slug>`' '| grill | `/propose <slug>`' \
           '| propose | `/apply <slug>`' '| apply | `/review <slug>`' '| review | `/pr <slug>`' \
           '| pr | `/babysit <slug>`' '| babysit | stop'; do
  assert_fixed "$row" "$CONT"
done
assert_fixed 'status: open' "$CONT"
assert_fixed 'condition in the table is not met' "$CONT"
assert_fixed 'Merging is never part of this chain' "$CONT"
