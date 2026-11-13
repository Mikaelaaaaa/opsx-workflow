#!/usr/bin/env bash
# Stop hook：claude 啟動參數丟了時放行，不逼寫檔、不開「卡在接」gate；認不得時照舊擋。
# 驗收：specs/args-lost-guard/spec.md（參數遺失時 Stop 放行）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI)"
mkdir -p "$R/openspec/changes/archive"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
printf '## 1. x\n\n- [x] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"
S="$OPSX_STATE_DIR/settings/Acmecorp-AI-eval-core-autopilot.json"
mkdir -p "$(dirname "$S")"; printf '{}' > "$S"
mode() { printf '{"Acmecorp-AI/eval-core":{"mode":"%s","pane":"w1:p1"}}' "$1" > "$OPSX_STATE_DIR/dispatch.json"; }
# pane 的 process-info：前景 claude 帶了這張卡的 settings／沒帶
SAMPLES="$OPSX_ROOT/tests/fakes/herdr-samples"
PI_HAS="$FX/pi-has.json"; PI_LOST="$FX/pi-lost.json"; PI_TWO="$FX/pi-two.json"
jq -c --arg s "$S" '(.result.process_info.foreground_processes[] | select(.argv0 == "claude") | .argv) |= ["claude", "--model", "m", "--settings", $s]' "$SAMPLES/process-info-claude.json" > "$PI_HAS"
jq -c '(.result.process_info.foreground_processes[] | select(.argv0 == "claude") | .argv) |= ["claude", "--model", "m"]' "$SAMPLES/process-info-claude.json" > "$PI_LOST"
jq -c '.result.process_info.foreground_processes += [.result.process_info.foreground_processes[1]]' "$PI_HAS" > "$PI_TWO"
export OPSX_TEST_PROCESS_INFO="$PI_LOST"

# 假 ps 與假 herdr（回報協調者的那行記在 $CL）
mkdir -p "$FX/cbin"
# 只接受 `-o args= -p <hook 的 parent pid>`：hook 問的不是自己的 parent 就非 0 結束
export OPSX_FAKE_PS_PID="$FX/hook-parent"
printf '#!/usr/bin/env bash\n[ "$*" = "-o args= -p $(cat "$OPSX_FAKE_PS_PID")" ] || { echo "fake ps: 不是問 hook 的 parent：$*" >&2; exit 1; }\nprintf "%%s\\n" "${OPSX_FAKE_PS:-}"\nexit "${OPSX_FAKE_PS_RC:-0}"\n' > "$FX/cbin/ps"; chmod +x "$FX/cbin/ps"
printf '#!/usr/bin/env bash\nexec bash "%s/tests/fakes/herdr" "$@"\n' "$OPSX_ROOT" > "$FX/cbin/herdr"; chmod +x "$FX/cbin/herdr"
CL="$FX/coord.log"
stop() { # 狀態（擋的次數）跨呼叫保留；要重來自己 rm -rf stop-chain。hook 的 PPID 就是這個 bash -c 的 $$
  PATH="$FX/cbin:$PATH" OPSX_FAKE_LOG="$CL" OPSX_TEST_COORDINATOR_UP=1 bash -c \
    'echo $$ > "$OPSX_FAKE_PS_PID"; printf "{\"cwd\":\"%s\",\"stop_hook_active\":false}" "$0" | bash "$1/openspec-stop-gate.sh" 2>/dev/null; true' "$R" "$H"
}
fresh() { rm -rf "$OPSX_STATE_DIR/stop-chain" "$OPSX_STATE_DIR/stop-said" "$C/gates.md"; : > "$CL"; }
blocked() { [ "$(printf '%s' "$1" | jq -r '.decision // "allow"')" = block ]; }

mode autopilot

# 有帶 settings：照舊擋，連擋到上限開「卡在接」gate
fresh
out="$(OPSX_FAKE_PS="claude --settings $S" stop)"; blocked "$out" || fail "有帶 settings 要照舊擋：$out"

# 遺失：連續超過 MAX_BLOCKS（3）次都放行，不寫 gate，回報協調者
fresh
for i in 1 2 3 4 5; do
  out="$(OPSX_FAKE_PS="claude --model m" stop)"
  [ -z "$out" ] || fail "遺失時第 $i 次要放行：$out"
done
assert_no_file "$C/gates.md"
assert_grep "參數遺失" "$CL"
assert_file "$OPSX_STATE_DIR/args-lost/Acmecorp-AI-eval-core"   # drive 靠這個標記知道參數遺失

# 父行程沒帶，但 pane 的 claude 有帶：不是遺失，照既有規則擋（還有沒勾的 task），不回報、不留標記
# 驗收：openspec/changes/agent-20261113-1355/specs/args-lost-guard/spec.md（判遺失前用 pane 的 claude 確認）
fresh; rm -rf "$OPSX_STATE_DIR/args-lost"
out="$(OPSX_TEST_PROCESS_INFO="$PI_HAS" OPSX_FAKE_PS="claude --model m" stop)"
blocked "$out" || fail "pane 的 claude 有帶要照舊擋：$out"
printf '%s' "$out" | jq -r '.reason' | grep -q '/opsx-workflow:apply' || fail "要叫接 /apply：$out"
case "$(cat "$CL")" in *"參數遺失"*) fail "pane 的 claude 有帶不回報參數遺失：$(cat "$CL")" ;; esac
assert_no_file "$OPSX_STATE_DIR/args-lost/Acmecorp-AI-eval-core"
assert_grep "^pane process-info --pane w1:p1$" "$CL"   # 問的是 dispatch.json 記的那個 pane

# pane 讀不到：判不了，照擋並回報原因，不回報參數遺失、不留標記
pane_unknown() { # <說明> → 呼叫前設好 env 或 dispatch.json
  local out
  out="$(OPSX_FAKE_PS="claude --model m" stop)"
  blocked "$out" || fail "$1：要照舊擋：$out"
  assert_grep "無法判斷啟動參數" "$CL"
  case "$(cat "$CL")" in *"參數遺失"*) fail "$1：不回報參數遺失：$(cat "$CL")" ;; esac
  assert_no_file "$OPSX_STATE_DIR/args-lost/Acmecorp-AI-eval-core"
}
fresh; OPSX_TEST_PROCESS_INFO_ERR=1 pane_unknown "herdr pane process-info 失敗"
fresh; OPSX_TEST_PROCESS_INFO="$SAMPLES/process-info-shell.json" pane_unknown "pane 前景沒有 claude"
assert_grep "前景沒有 claude" "$CL"
fresh; OPSX_TEST_PROCESS_INFO="$PI_TWO" pane_unknown "pane 前景有兩個 claude"
fresh; printf '{"Acmecorp-AI/eval-core":{"mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
pane_unknown "dispatch.json 的條目沒有 pane"
assert_grep "pane" "$CL"
mode autopilot

# 重新啟動後有帶 settings：標記清掉
fresh
OPSX_FAKE_PS="claude --settings $S" stop >/dev/null
assert_no_file "$OPSX_STATE_DIR/args-lost/Acmecorp-AI-eval-core"

# 認不得（不是 claude 的 cmdline）：照舊擋，回報原因，不放行
fresh
out="$(OPSX_FAKE_PS="node server.js" stop)"; blocked "$out" || fail "認不得時要照舊擋：$out"
assert_grep "無法判斷啟動參數" "$CL"

# ps 失敗：同樣照舊擋
fresh
out="$(OPSX_FAKE_PS="operation not permitted" OPSX_FAKE_PS_RC=1 stop)"; blocked "$out" || fail "ps 失敗要照舊擋：$out"
assert_grep "無法判斷啟動參數" "$CL"

# interactive 卡不判定：argv 沒帶 settings 也照舊擋
mode interactive
fresh
out="$(OPSX_FAKE_PS="claude --model m" stop)"; blocked "$out" || fail "interactive 卡要照舊擋：$out"
case "$(cat "$CL")" in *"參數遺失"*) fail "interactive 卡不回報參數遺失" ;; esac

# settings 檔不存在：沒派過，不判定
mode autopilot; rm -f "$S"
fresh
out="$(OPSX_FAKE_PS="claude --model m" stop)"; blocked "$out" || fail "沒有 settings 檔要照舊擋：$out"
echo ok
