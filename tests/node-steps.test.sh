#!/usr/bin/env bash
# 需求文件 §8.3 每個節點表點名的 skill，在該節點的 SKILL.md 或它的 references/ 裡要有 <name>/SKILL.md 的 Read 路徑。
# 只證明路徑寫了；agent 有沒有照讀由 eval 量。
# 驗收：openspec/changes/node-steps-text/specs/node-step-text/spec.md「節點表的 skill 都能被讀到」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NODES="
explore:how blast-radius why unslop
apply:tdd architect benchmark-checklist show-me-your-work unslop how interrogate
review:interrogate/references
propose:technical-writing unslop
pr:technical-writing unslop
archive:reflect
"

missing=""
while IFS=: read -r node skills; do
  [ -n "$node" ] || continue
  dir="$OPSX_ROOT/skills/$node"
  assert_file "$dir/SKILL.md"
  for s in $skills; do
    case "$s" in
      */*)
        assert_file "$OPSX_ROOT/skills/$s/reviewer-prompt.md"
        grep -rqF -- "$s/" "$dir" || missing="$missing ${node}:${s}" ;;
      *)
        # 抽出完整的 (../)+<name>/SKILL.md，以寫它的那個檔所在目錄為基準解析，層數寫錯就失敗
        assert_file "$OPSX_ROOT/skills/$s/SKILL.md"
        found=""
        for f in $(grep -rlF -- "$s/SKILL.md" "$dir"); do
          for rel in $(grep -oE "(\.\./)+$s/SKILL\.md" "$f" | sort -u); do
            assert_file "$(dirname "$f")/$rel"
            found=1
          done
        done
        [ -n "$found" ] || missing="$missing ${node}:${s}" ;;
    esac
  done
done <<< "$NODES"
[ -z "$missing" ] || fail "節點沒有可解析的 Read 路徑：$missing"

# 驗收：archive 的 3b（長任務 reflect）在 autopilot 下不等批准，不卡住歸檔
awk '/^### /{on=($0 ~ /^### 3b\./);next} /^## /{on=0} on' "$OPSX_ROOT/skills/archive/SKILL.md" > "$FX/archive-3b"
[ -s "$FX/archive-3b" ] || fail "archive 沒有 3b 一節"
assert_grep 'not wait for that approval' "$FX/archive-3b"

# playbooks 與 architect / teach 點名的 skill 要寫成相對於該檔的路徑，且路徑解析得到檔案
# 驗收：「playbook 的 skill 都有路徑」
PB="skills/apply/references/playbooks"
REFS="
$PB/dev.md:../../../how ../../../architect ../../../interrogate
$PB/bug-fix.md:../../../how ../../../why ../../../architect
$PB/perf.md:../../../how ../../../architect ../../../benchmark-checklist
$PB/refactoring.md:../../../how ../../../architect
$PB/hillclimb.md:../../../how ../../../benchmark-checklist
skills/architect/SKILL.md:../how ../why ../interrogate
skills/teach/SKILL.md:../how ../why
"
missing=""
while IFS=: read -r file rels; do
  [ -n "$file" ] || continue
  for r in $rels; do
    assert_file "$OPSX_ROOT/$(dirname "$file")/$r/SKILL.md"
    grep -qF -- "$r/SKILL.md" "$OPSX_ROOT/$file" || missing="$missing ${file}:${r}"
  done
done <<< "$REFS"
[ -z "$missing" ] || fail "沒有 Read 路徑：$missing"

# 驗收：「playbook 不叫 pr」
! grep -rEq 'Run the (`pr`|pr) skill' "$OPSX_ROOT/$PB" || fail "playbook 還有 Run the pr skill：$(grep -rnE 'Run the (`pr`|pr) skill' "$OPSX_ROOT/$PB")"

# 驗收：「原則路徑存在」
assert_grep '`\.\./\.\./references/principles/INDEX.md`' "$OPSX_ROOT/skills/apply/SKILL.md"
assert_file "$OPSX_ROOT/skills/apply/../../references/principles/INDEX.md"
! grep -rq 'principle skill' "$OPSX_ROOT/$PB" || fail "playbook 還有「principle skill」字樣：$(grep -rno '.\{30\}principle skill' "$OPSX_ROOT/$PB")"
! grep -rq '\*\*principle-' "$OPSX_ROOT/$PB" || fail "playbook 還有 **principle-<name>** 字樣"
for f in "$OPSX_ROOT/$PB"/*.md; do
  for p in $(grep -o '\.\./\.\./\.\./\.\./references/principles/[a-z-]*\.md' "$f" | sort -u); do
    assert_file "$(dirname "$f")/$p"
  done
done

# 驗收：「孤兒 skill 有節點引用」
grep -qF 'blast-radius/SKILL.md' "$OPSX_ROOT/skills/explore/SKILL.md" || fail "explore 沒有 blast-radius 路徑"
grep -qF 'typescript-best-practices/SKILL.md' "$OPSX_ROOT/skills/apply/SKILL.md" || fail "apply 沒有 typescript-best-practices 路徑"
echo ok
