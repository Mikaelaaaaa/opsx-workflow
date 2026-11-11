#!/usr/bin/env bash
# 用量上限期間 Stop hook 開的「卡在接」gate 沒人答得了：協調者看到 pane 有上限訊息就代答「重做」並清掉 stop-chain 計數。
# 驗收：openspec/changes/me-20261111-1824/specs/usage-limit-gate-clear/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"

AR="$FX/agent-read.txt"; export OPSX_TEST_AGENT_READ="$AR"
LIMIT_MSG='Usage limit reached · continuing automatically at 7pm · esc to cancel'
CHAIN="$OPSX_STATE_DIR/stop-chain/demo-r1"
mkcard r1
gate_card() { # <gate id>
  cards '[{"slug":"r1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","open_gates":[{"id":"'"$1"'","opened_at":null}]}]'
}
seed_chain() { mkdir -p "$OPSX_STATE_DIR/stop-chain"; printf 'apply 3 gated 1\n' > "$CHAIN"; }
rm -f "$MEMO"; printf '{}' > "$DISP"

# 上限訊息在 pane 尾巴、gate 是卡在接：代答重做、清計數
printf '%s\n' "$LIMIT_MSG" > "$AR"; gate_card '卡在接 /apply #1'; seed_chain
round || fail "rc: $(cat "$FX/out")"
assert_grep '^opsx answer r1 --gate 卡在接 /apply #1 --repo .* -- 重做 /opsx-workflow:apply' "$OPSX_FAKE_LOG"
assert_no_file "$CHAIN"

# 沒有上限訊息：不動
rm -f "$MEMO"; printf 'ok\n' > "$AR"; gate_card '卡在接 /apply #1'; seed_chain
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "沒有上限訊息不代答：$(cat "$OPSX_FAKE_LOG")"
assert_file "$CHAIN"

# 不是卡在接的 gate：上限期間照舊不代答
rm -f "$MEMO"; printf '%s\n' "$LIMIT_MSG" > "$AR"; gate_card 'push 授權'; seed_chain
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "別的 gate 不代答：$(cat "$OPSX_FAKE_LOG")"
assert_file "$CHAIN"
echo "usage-limit-gate-clear ok"
