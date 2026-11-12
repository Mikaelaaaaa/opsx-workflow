#!/usr/bin/env bash
# agent 啟動參數遺失（hook 留了 args-lost 標記）時，drive 送完階段指令見階段沒動：不寫 drive-<stage>-N 的假 gate、不 kick 協調者。
# 驗收：openspec/changes/me-20261111-1824/specs/drive-args-lost/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_DRIVE_POLL=0 OPSX_DRIVE_MAX=20

R="$(mk_repo Agentory-CS)"; C="$R/openspec/changes/retry-backoff"; mkdir -p "$C" "$OPSX_STATE_DIR"
KL="$FX/kick.log"; : > "$KL"
cat > "$FX/fakebin/opsx" <<EOF
#!/usr/bin/env bash
if [ "\$1" = coordinate ]; then OPSX_FAKE_LOG="$KL" exec bash "$FAKES/opsx" "\$@"; fi
exec bash "$OPSX_ROOT/bin/opsx" "\$@"
EOF
chmod +x "$FX/fakebin/opsx"
printf 'schema: opsx\nkind: bug-fix\n' > "$C/.openspec.yaml"
MARK="$OPSX_STATE_DIR/args-lost/Agentory-CS-retry-backoff"
reset() {
  printf '## 1\n\n- [ ] 1.1 a\n  - 驗收：R1\n  - 測試：t.py\n' > "$C/tasks.md"; rm -f "$C/gates.md" "$C/status.json" "$C/report.md"
  printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
  : > "$OPSX_FAKE_LOG"; : > "$KL"
}
# 假 agent 收到指令不動；等 agent 開工時把卡從 dispatch.json 拿掉，讓 drive 結束
: > "$FX/noop.sh"; export OPSX_TEST_ON_PROMPT="$FX/noop.sh" OPSX_TEST_PANE_TEXT="pane 尾巴"
cat > "$FX/on_wait.sh" <<EOF
case "\$*" in *"--until working"*) printf '{}' > "$OPSX_STATE_DIR/dispatch.json" ;; esac
EOF
export OPSX_TEST_ON_WAIT="$FX/on_wait.sh"

# 遺失：不寫 gate、不 kick、只送一次、說明裡指出 opsx relaunch
reset; mkdir -p "$(dirname "$MARK")"; : > "$MARK"
out="$(opsx drive retry-backoff --repo "$R" 2>&1)"; assert_eq "$?" 0 "drive rc: ${out}"
assert_no_file "$C/gates.md"
assert_eq "$(cat "$KL")" "" "不該 kick 協調者"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "只送一次: $(cat "$OPSX_FAKE_LOG")"
echo "$out" | grep -qF 'opsx relaunch retry-backoff' || fail "說明要指出 opsx relaunch: ${out}"

# 沒有標記：照舊寫 gate 並 kick
reset; rm -f "$MARK"
out="$(opsx drive retry-backoff --repo "$R" 2>&1)"; assert_eq "$?" 0 "drive rc: ${out}"
assert_grep '^## drive-apply-1$' "$C/gates.md"
assert_grep 'opsx coordinate --kick' "$KL"
echo "drive-args-lost ok"
