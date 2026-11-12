#!/usr/bin/env bash
# 用量上限期間 Stop hook 開的「卡在接」gate：暫停期間不處理，暫停解除後照卡住 gate 的規則通知人，從不代答、不動 stop-chain 計數。
# 驗收：openspec/changes/me-20261112-1415/specs/usage-limit-gate-clear/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"

AR="$FX/agent-read.txt"; export OPSX_TEST_AGENT_READ="$AR"
LIMIT_MSG='Usage limit reached · continuing automatically at 7pm · esc to cancel'
CHAIN="$OPSX_STATE_DIR/stop-chain/demo-r1"
GATE='卡在接 /apply #1'
ago() { python3 -I -c 'import datetime,sys; print((datetime.datetime.now().astimezone()-datetime.timedelta(minutes=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
mkcard r1
stuck_card() { cards '[{"slug":"r1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","open_gates":[{"id":"'"$GATE"'","opened_at":null}],"waiting":{"type":"等待決定","needs":null,"waits_on":null,"gate_id":"'"$GATE"'","question":"卡在哪","recommended":null,"options":["重做"]}}]'; }
seed_chain() { mkdir -p "$OPSX_STATE_DIR/stop-chain"; printf 'apply 3 gated 1\n' > "$CHAIN"; }
gate_notes() { grep -F '[demo/r1] gate 卡在接' "$OPSX_FAKE_LOG" | grep -c 'notification show' || true; }
printf '{}' > "$DISP"

# 上限期間不通知不答（反例）：上限訊息在 pane 尾巴，gate 是卡在接
rm -f "$MEMO"; printf '%s\n' "$LIMIT_MSG" > "$AR"; stuck_card; seed_chain
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "暫停期間不代答：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(gate_notes)" 0 "暫停期間不為 gate 通知：$(cat "$OPSX_FAKE_LOG")"
assert_file "$CHAIN"

# 恢復後通知不答（正例）：重置時刻已過、畫面乾淨、gate 仍 open
printf 'ok\n' > "$AR"; printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"}}' "$(ago 70)" "$(ago 10)" > "$MEMO"; seed_chain; stuck_card
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "恢復後也不代答重做：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(gate_notes)" 1 "恢復後通知人一次：$(cat "$OPSX_FAKE_LOG")"
assert_file "$CHAIN"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(gate_notes)" 0 "第二輪不重送：$(cat "$OPSX_FAKE_LOG")"
echo "usage-limit-gate-clear ok"
