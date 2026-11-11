#!/usr/bin/env bash
# 寫作 pass 寫在節點 SKILL.md 裡：grill、pr 先 technical-writing 再 unslop；explore 只要 unslop（§8.3 explore 第 8 步只列 unslop）。
# 只證明路徑寫在檔裡且順序對；agent 有沒有照做由 eval 量。
# 驗收：openspec/changes/node-steps-text/specs/node-step-text/spec.md「寫作 pass」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
first_line() { grep -boF -- "$1" "$2" | head -1 | cut -d: -f1; }
assert_file "$OPSX_ROOT/skills/technical-writing/SKILL.md"
assert_file "$OPSX_ROOT/skills/unslop/SKILL.md"
bad=""
for node in grill pr; do
  sk="$OPSX_ROOT/skills/$node/SKILL.md"
  assert_file "$sk"
  tw="$(first_line 'technical-writing/SKILL.md' "$sk")"
  un="$(first_line 'unslop/SKILL.md' "$sk")"
  if [ -z "$tw" ] || [ -z "$un" ]; then bad="$bad $node(缺：technical-writing=[$tw] unslop=[$un])"; continue; fi
  [ "$tw" -lt "$un" ] || bad="$bad $node(順序：technical-writing 位移 $tw 不在 unslop 位移 $un 之前)"
done
ex="$OPSX_ROOT/skills/explore/SKILL.md"
assert_file "$ex"
[ -n "$(first_line 'unslop/SKILL.md' "$ex")" ] || bad="$bad explore(缺 unslop)"
[ -z "$bad" ] || fail "寫作 pass 不齊：$bad"
echo ok
