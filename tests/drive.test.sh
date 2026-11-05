#!/usr/bin/env bash
# opsx drive：假 herdr 的 agent prompt 會推進 fixture，看迴圈走的順序和停的地方。要求檔 §3.6 自主程度表。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_DRIVE_POLL=0 OPSX_DRIVE_MAX=20

R="$(mk_repo Agentory-CS)"; C="$R/openspec/changes/retry-backoff"; mkdir -p "$C" "$OPSX_STATE_DIR"
printf 'schema: opsx\nkind: bug-fix\n' > "$C/.openspec.yaml"
printf '## 1\n\n- [ ] 1.1 a\n  - 驗收：R1\n  - 測試：t.py\n' > "$C/tasks.md"
printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
export OPSX_TEST_GLAB_JSON="$FX/mr.json"
printf '{"state":"opened","draft":false,"has_conflicts":false,"head_pipeline":{"status":"failed"},"unresolved_discussions_count":1}' > "$OPSX_TEST_GLAB_JSON"

# 假 agent：收到 /apply → 勾完 tasks + tests green；/review → report.md；/pr → report 加 MR URL；/babysit → 把 pipeline 修綠、threads 清掉
cat > "$FX/on_prompt.sh" <<EOF
case "\$1" in
  "/apply retry-backoff") printf '## 1\n\n- [x] 1.1 a\n' > "$C/tasks.md"; printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json" ;;
  "/review retry-backoff") printf '# report\n' > "$C/report.md" ;;
  "/pr retry-backoff") printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/Agentory-CS/-/merge_requests/431\n' > "$C/report.md" ;;
  "/babysit retry-backoff") printf '{"state":"opened","draft":false,"has_conflicts":false,"head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON" ;;
esac
EOF
export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"

cd "$R"; out="$(opsx drive retry-backoff 2>&1)"; rc=$?
assert_eq "$rc" 0 "drive rc: $out"
seq="$(grep '^agent prompt' "$OPSX_FAKE_LOG" | sed 's/ --wait$//' | cut -d' ' -f4- | tr '\n' '|')"
assert_eq "$seq" "/apply retry-backoff|/review retry-backoff|/pr retry-backoff|/babysit retry-backoff|" "prompt 順序"
echo "$out" | grep -q "可以合併" || fail "要停在可以合併: $out"
assert_grep '"phase": "pr"' "$C/status.json"
assert_not_grep '^agent wait' "$OPSX_FAKE_LOG"   # 沒 gate 不該 wait

# --- gate 開著 → 不丟 prompt，agent wait --until working；人回了（gate 關）才繼續 ---
: > "$OPSX_FAKE_LOG"
printf '## 1\n\n- [ ] 1.1 a\n' > "$C/tasks.md"; rm -f "$C/status.json" "$C/report.md"
printf '## gate 1\nstatus: open\ntype: approval\n' > "$C/gates.md"
cat > "$FX/on_wait.sh" <<EOF
printf '## gate 1\nstatus: answered\n' > "$C/gates.md"
EOF
export OPSX_TEST_ON_WAIT="$FX/on_wait.sh"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive w/ gate: $out"
first="$(head -1 "$OPSX_FAKE_LOG")"; assert_eq "$first" "agent wait retry-backoff --until working" "gate 時第一個呼叫要是 wait"
assert_grep '^agent prompt retry-backoff /apply retry-backoff --wait$' "$OPSX_FAKE_LOG"

# --- 不在 dispatch.json（被 stop）→ 立刻結束，不碰 herdr ---
: > "$OPSX_FAKE_LOG"; printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0; assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "stopped card 不該碰 herdr"
echo "$out" | grep -q "不在 dispatch.json" || fail "要說明為什麼結束: $out"
echo ok
