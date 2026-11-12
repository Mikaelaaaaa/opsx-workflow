#!/usr/bin/env bash
# tasks 全勾、測試綠、沒有 report.md 的 review 站：有 blocking gate 時 Stop hook 放行，不累計 MAX_BLOCKS。
# 驗收：openspec/changes/me-20261111-1824/specs/stop-gate-open-gate/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Agentory-AI git@gitlab.tsg-navigator.com:agentory/Agentory-AI.git)"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$C/explore.md"
printf '## 1. x\n\n- [x] 1.1 a\n  - 驗收：R\n  - 測試：tests/a.test.sh\n' > "$C/tasks.md"
printf '{"phase":"apply","step":2,"total":2,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
STOP_STATE="$OPSX_STATE_DIR/stop-chain"
sg() { printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
decision() { [ -z "$1" ] && { echo allow; return; }; printf '%s' "$1" | jq -r '.decision // "allow"'; }

# 沒有 gate：擋，要求跑 review
rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "沒有 gate 時要擋"
printf '%s' "$out" | jq -r '.reason' | grep -q '/opsx-workflow:review' || fail "要叫跑 review: $out"

# 為等協調者寫了 decision gate：放行，stop-chain 計數不增加
printf '## 等協調者的全套結果\ntype: decision\nstatus: open\n問題: 全套結果出來前先停嗎\n選項: 等 (Recommended) | 不等\n建議: 等\n預設: 不等\n' > "$C/gates.md"
rm -rf "$STOP_STATE"
for i in 1 2 3 4; do
  out="$(sg)"; assert_eq "$(decision "$out")" allow "第 ${i} 次有 open decision gate 要放行: $out"
done
assert_no_file "$STOP_STATE/Agentory-AI-eval-core"
assert_not_grep '卡在接 /review' "$C/gates.md"

# gate 答完之後恢復原行為
printf '## 等協調者的全套結果\ntype: decision\nstatus: answered\nanswer: 等\n' > "$C/gates.md"
rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "gate answered 後要擋"
echo "stop-gate-open-gate ok"
