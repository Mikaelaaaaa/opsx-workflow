#!/usr/bin/env bash
# stage_of 的 Read 清單不組不存在的 playbook 路徑：chore、ops 不列，experiment 列 hillclimb 與 eval，其餘 kind 照舊。
# 驗收：openspec/changes/node-steps-gates/specs/node-step-gates/spec.md「階段行不組不存在的 playbook」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$OPSX_ROOT/bin/lib/stage.sh"

T="$FX/repo"
mk_card() { # <slug> <kind>：一張只有 tasks.md 未勾的卡，階段是 apply
  mkdir -p "$T/openspec/changes/$1"
  printf 'schema: opsx\ncreated: 2026-11-05\nkind: %s\n' "$2" > "$T/openspec/changes/$1/.openspec.yaml"
  printf '## 1. x\n\n- [ ] 1.1 a\n' > "$T/openspec/changes/$1/tasks.md"
}
for k in chore ops experiment bug-fix; do mk_card "c-$k" "$k"; done

out="$(stage_of "$T" c-chore)"
case "$out" in *playbooks/*) fail "chore 不該列 playbook: $out" ;; esac
case "$out" in *skills/apply/SKILL.md*skills/tdd/SKILL.md*) ;; *) fail "chore 仍要列 apply 與 tdd: $out" ;; esac

out="$(stage_of "$T" c-ops)"
case "$out" in *playbooks/*) fail "ops 不該列 playbook: $out" ;; esac

out="$(stage_of "$T" c-experiment)"
case "$out" in *playbooks/hillclimb.md*playbooks/eval.md*) ;; *) fail "experiment 要列 hillclimb.md 與 eval.md: $out" ;; esac
case "$out" in *playbooks/experiment.md*) fail "experiment 不該列不存在的 experiment.md: $out" ;; esac

out="$(stage_of "$T" c-bug-fix)"
case "$out" in *skills/apply/references/playbooks/bug-fix.md*) ;; *) fail "bug-fix 仍列自己的 playbook: $out" ;; esac
echo ok
