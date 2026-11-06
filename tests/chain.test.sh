#!/usr/bin/env bash
# auto-dispatch：pane 撐完一條相依鏈。續接、fan-out 登記、代管卡的送話與停止。
# 驗收：specs/opsx-chain/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_TEST_GLAB_JSON="$FX/mr.json"

R="$(mk_repo Agentory-AI)"; mk_change "$R" p; mkdir -p "$OPSX_STATE_DIR"
cd "$R"

# --- 已交接的父卡：merge / answer / stop 都拒絕，訊息說交給誰，不碰 herdr 也不動檔 ---
P="$R/openspec/changes/p"
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/Agentory-AI/-/merge_requests/431\n' > "$P/report.md"
printf '## g1\ntype: decision\nstatus: open\n問題: q\n選項: a | b\n' > "$P/gates.md"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
printf '{"Agentory-AI/p":{"mode":"autopilot","pane":"w5:pQ","agent":"claude","grants":[],"herdr_name":"p","handed_to":["c"],"handed_at":"2026-11-06T15:00:00+08:00"}}' > "$OPSX_STATE_DIR/dispatch.json"
cp "$OPSX_STATE_DIR/dispatch.json" "$FX/disp.before"; cp "$P/gates.md" "$FX/gates.before"
for cmd in "stop p" "merge p" "answer p --gate g1 a"; do
  : > "$OPSX_FAKE_LOG"
  out="$(opsx $cmd 2>&1)"; rc=$?
  [ $rc -ne 0 ] || fail "已交接的卡 opsx $cmd 要拒絕: $out"
  echo "$out" | grep -q 'c' && echo "$out" | grep -q '交接' || fail "opsx $cmd 的訊息要說交接給 c: $out"
  assert_not_grep '^pane close' "$OPSX_FAKE_LOG"; assert_not_grep '^agent prompt' "$OPSX_FAKE_LOG"
  cmp -s "$OPSX_STATE_DIR/dispatch.json" "$FX/disp.before" || fail "opsx $cmd 不該動 dispatch.json"
  cmp -s "$P/gates.md" "$FX/gates.before" || fail "opsx $cmd 不該動 gates.md"
done
echo ok
