#!/usr/bin/env bash
# 用量上限期間 Stop hook 開的「卡在接」gate：暫停期間只記不答，暫停解除後才答「重做」並清 stop-chain 計數。
# 驗收：openspec/changes/me-20261111-1824/specs/usage-limit-gate-clear/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"

AR="$FX/agent-read.txt"; export OPSX_TEST_AGENT_READ="$AR"
LIMIT_MSG='Usage limit reached · continuing automatically at 7pm · esc to cancel'
CHAIN="$OPSX_STATE_DIR/stop-chain/demo-r1"
GATE='卡在接 /apply #1'
ago() { python3 -I -c 'import datetime,sys; print((datetime.datetime.now().astimezone()-datetime.timedelta(minutes=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
mkcard r1
gate_card() { # <gate id>：有就是 open 的 gate，空字串就是沒有 open 的 gate
  if [ -n "$1" ]; then cards '[{"slug":"r1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","open_gates":[{"id":"'"$1"'","opened_at":null}]}]'
  else cards '[{"slug":"r1","section":"進行中","dispatch":'"$D"',"agent_status":"idle"}]'; fi
}
seed_chain() { mkdir -p "$OPSX_STATE_DIR/stop-chain"; printf 'apply 3 gated 1\n' > "$CHAIN"; }
stuck_memo() { printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"},"_limit_stuck":{"demo/r1":["%s"]}}' "$(ago 70)" "$(ago 10)" "$GATE" > "$MEMO"; }
printf '{}' > "$DISP"

# 上限訊息在 pane 尾巴、gate 是卡在接：暫停期間只記，不代答，不動計數
rm -f "$MEMO"; printf '%s\n' "$LIMIT_MSG" > "$AR"; gate_card "$GATE"; seed_chain
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "暫停期間不代答：$(cat "$OPSX_FAKE_LOG")"
grep -qF "$GATE" "$MEMO" || fail "memo 要記下卡在接 gate：$(cat "$MEMO")"
assert_file "$CHAIN"

# 暫停解除（重置時刻已過、畫面乾淨）、gate 仍 open：答重做、清計數、memo 清掉
printf 'ok\n' > "$AR"; stuck_memo; gate_card "$GATE"; seed_chain
round || fail "rc: $(cat "$FX/out")"
assert_grep '^opsx answer r1 --gate 卡在接 /apply #1 --repo .* -- 重做 /opsx-workflow:apply' "$OPSX_FAKE_LOG"
assert_no_file "$CHAIN"
if grep -qF "$GATE" "$MEMO"; then fail "答完要清 memo：$(cat "$MEMO")"; fi

# 暫停解除時 gate 已被人答掉：不代答，memo 清掉
stuck_memo; gate_card ""; seed_chain
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "gate 已不是 open 不代答：$(cat "$OPSX_FAKE_LOG")"
if grep -qF "$GATE" "$MEMO"; then fail "memo 要清掉：$(cat "$MEMO")"; fi

# 沒有上限訊息、memo 沒有記錄：不動
rm -f "$MEMO"; printf 'ok\n' > "$AR"; gate_card "$GATE"; seed_chain
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "沒有上限訊息不代答：$(cat "$OPSX_FAKE_LOG")"
assert_file "$CHAIN"

# 不是卡在接的 gate：上限期間不記
rm -f "$MEMO"; printf '%s\n' "$LIMIT_MSG" > "$AR"; gate_card 'push 授權'; seed_chain
round || fail "rc: $(cat "$FX/out")"
if grep -q '_limit_stuck' "$MEMO" && grep -q 'push 授權' "$MEMO"; then fail "別的 gate 不記：$(cat "$MEMO")"; fi
assert_file "$CHAIN"
echo "usage-limit-gate-clear ok"
