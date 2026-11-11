#!/usr/bin/env bash
# agent_not_ready（不是 trust 畫面）時 pane read 失敗：dispatch 要照樣印錯誤、關 tab、非零退出，不能靜默結束。
# 驗收：openspec/changes/me-20261111-1824/specs/dispatch-pane-read-fail/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela OPSX_DISPATCH_RETRY_SLEEP=0

R="$(mk_repo Agentory-CS git@gitlab.tsg-navigator.com:agentory/Agentory-CS.git)"
mkdir -p "$R/openspec/changes/nr-card" "$OPSX_STATE_DIR"
printf 'schema: opsx\n' > "$R/openspec/changes/nr-card/.openspec.yaml"
printf '[repos]\n"Agentory-CS" = "agnetory-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"
cd "$R"

# pane read 失敗
echo x > "$FX/not-ready"
out="$(OPSX_TEST_NOT_READY_ONCE="$FX/not-ready" OPSX_TEST_PANE_READ_FAIL=1 opsx dispatch nr-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "agent_not_ready 要非零退出: ${out}"
echo "$out" | grep -qF 'herdr agent start 失敗' || fail "要印失敗訊息（rc=${rc}）: ${out}"
echo "$out" | grep -qF 'agent_not_ready' || fail "要印 herdr 的原文: ${out}"
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"

# pane read 成功：畫面文字要印出來
: > "$OPSX_FAKE_LOG"; echo x > "$FX/not-ready"
out="$(OPSX_TEST_NOT_READY_ONCE="$FX/not-ready" OPSX_TEST_PANE_TEXT='some startup dialog' opsx dispatch nr-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "agent_not_ready 要非零退出: ${out}"
echo "$out" | grep -qF 'some startup dialog' || fail "畫面文字要在錯誤訊息裡: ${out}"
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"
echo "dispatch-pane-read-fail ok"
