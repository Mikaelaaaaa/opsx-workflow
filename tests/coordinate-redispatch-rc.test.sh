#!/usr/bin/env bash
# 單卡重派要看 opsx dispatch 的退出碼：失敗不記 _redispatched、同一輪通知。
# 驗收：openspec/changes/me-20261111-1824/specs/coordinate-redispatch-rc/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"

mkcard u
cards '[{"slug":"u","section":"進行中","dispatch":'"$D"',"agent_status":"unknown"}]'

# dispatch 失敗：不記 _redispatched，通知一次
OPSX_TEST_FAIL_dispatch='herdr tab create 失敗' round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 1 "要試一次重派"
assert_eq "$(memo_get _redispatched demo/u)" "" "失敗不能記 _redispatched：$(cat "$MEMO" 2>/dev/null)"
assert_eq "$(count '^agent prompt')" 1 "失敗要通知協調者：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep -q 'demo/u' || fail "要記 ??：$(cat "$LOG")"
# 下一輪還是失敗：不重複通知
OPSX_TEST_FAIL_dispatch='herdr tab create 失敗' round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^agent prompt')" 0 "同一件事不重複通知"

# dispatch 成功：記 _redispatched，不通知
rm -f "$MEMO"
round || fail "rc: $(cat "$FX/out")"
[ -n "$(memo_get _redispatched demo/u)" ] || fail "成功要記 _redispatched：$(cat "$MEMO")"
assert_eq "$(count '^agent prompt')" 0 "成功不通知"
echo "coordinate-redispatch-rc ok"
