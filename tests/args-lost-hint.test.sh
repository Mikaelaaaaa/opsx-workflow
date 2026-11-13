#!/usr/bin/env bash
# SessionStart：autopilot / drive 卡的 claude 啟動參數丟了，router 在注入文字最前面印救法。
# 驗收：specs/args-lost-guard/spec.md（SessionStart 提示參數遺失）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI)"
mkdir -p "$R/openspec/changes/archive"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
S="$OPSX_STATE_DIR/settings/Acmecorp-AI-eval-core-autopilot.json"

# 假 ps：輸出 $OPSX_FAKE_PS，退出碼 $OPSX_FAKE_PS_RC（預設 0）
mkdir -p "$FX/psbin"
# 只接受 `-o args= -p <hook 的 parent pid>`：hook 問的不是自己的 parent 就非 0 結束
export OPSX_FAKE_PS_PID="$FX/hook-parent"
printf '#!/usr/bin/env bash\n[ "$*" = "-o args= -p $(cat "$OPSX_FAKE_PS_PID")" ] || { echo "fake ps: 不是問 hook 的 parent：$*" >&2; exit 1; }\nprintf "%%s\\n" "${OPSX_FAKE_PS:-}"\nexit "${OPSX_FAKE_PS_RC:-0}"\n' > "$FX/psbin/ps"; chmod +x "$FX/psbin/ps"

start() { # <事件> → router 注入的文字。hook 是 bash -c 這個行程的子行程，所以它的 PPID 就是那個 bash -c 的 $$
  local json; json="$(python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],prompt="",hook_event_name=sys.argv[2])))' "$R" "$1")"
  PATH="$FX/psbin:$PATH" bash -c 'echo $$ > "$OPSX_FAKE_PS_PID"; printf "%s" "$0" | bash "$1"' "$json" "$H/openspec-router.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""'
}
mode() { mkdir -p "$OPSX_STATE_DIR"; printf '{"Acmecorp-AI/eval-core":{"mode":"%s","pane":"w1:p1"}}' "$1" > "$OPSX_STATE_DIR/dispatch.json"; }
# 父行程看起來遺失時 hook 問 pane：假 herdr 的 process-info 印 $OPSX_TEST_PROCESS_INFO
printf '#!/usr/bin/env bash\nexec bash "%s/tests/fakes/herdr" "$@"\n' "$OPSX_ROOT" > "$FX/psbin/herdr"; chmod +x "$FX/psbin/herdr"
PI_HAS="$FX/pi-has.json"; PI_LOST="$FX/pi-lost.json"
jq -c --arg s "$S" '(.result.process_info.foreground_processes[] | select(.argv0 == "claude") | .argv) |= ["claude", "--model", "m", "--settings", $s]' "$OPSX_ROOT/tests/fakes/herdr-samples/process-info-claude.json" > "$PI_HAS"
jq -c '(.result.process_info.foreground_processes[] | select(.argv0 == "claude") | .argv) |= ["claude", "--model", "m"]' "$OPSX_ROOT/tests/fakes/herdr-samples/process-info-claude.json" > "$PI_LOST"
export OPSX_TEST_PROCESS_INFO="$PI_LOST" OPSX_FAKE_LOG="$FX/herdr.log"

mode autopilot
mkdir -p "$(dirname "$S")"; printf '{}' > "$S"

# 父行程沒帶、pane 的 claude 有帶：不印參數遺失
# 驗收：openspec/changes/agent-20261113-1355/specs/args-lost-guard/spec.md（SessionStart 提示同樣先看 pane）
out="$(OPSX_TEST_PROCESS_INFO="$PI_HAS" OPSX_FAKE_PS="claude --model m" start SessionStart)"
case "$out" in *"參數遺失"*|*"無法判斷"*) fail "pane 的 claude 有帶不該印參數遺失或無法判斷：$out" ;; esac

out="$(OPSX_FAKE_PS="claude --model m --settings $S" start SessionStart)"
case "$out" in *"參數遺失"*) fail "有帶 settings 不該印參數遺失：$out" ;; esac
case "$out" in *"無法判斷"*) fail "有帶 settings 不該印無法判斷：$out" ;; esac

out="$(OPSX_FAKE_PS="claude --model m" start SessionStart)"
case "$out" in *"參數遺失，跑 opsx relaunch eval-core"*) ;; *) fail "遺失時要印救法：$out" ;; esac
case "$out" in *"參數遺失"*"autopilot："*) ;; *) fail "救法要在 autopilot 規則之前，規則照舊在後面：$out" ;; esac

out="$(OPSX_FAKE_PS="claude --model m" start UserPromptSubmit)"
case "$out" in *"參數遺失"*) fail "只有 SessionStart 判定，UserPromptSubmit 不判：$out" ;; esac

mode drive
out="$(OPSX_FAKE_PS="claude" start SessionStart)"
case "$out" in *"opsx relaunch eval-core"*) fail "drive 卡的 settings 檔名是 -drive.json，autopilot 那份不算：$out" ;; esac
mode autopilot

mode interactive
out="$(OPSX_FAKE_PS="claude --model m" start SessionStart)"
case "$out" in *"參數遺失"*|*"無法判斷"*) fail "interactive 卡不判定：$out" ;; esac
mode autopilot

rm -f "$S"
out="$(OPSX_FAKE_PS="claude --model m" start SessionStart)"
case "$out" in *"參數遺失"*|*"無法判斷"*) fail "settings 檔不存在表示沒派過，不判定：$out" ;; esac
printf '{}' > "$S"

out="$(OPSX_FAKE_PS="node server.js" start SessionStart)"
case "$out" in *"無法判斷啟動參數"*"argv[0]"*) ;; *) fail "不是 claude 的 cmdline 要大聲報原因：$out" ;; esac
case "$out" in *"opsx relaunch"*) fail "認不得時不印救法：$out" ;; esac

out="$(OPSX_FAKE_PS="operation not permitted" OPSX_FAKE_PS_RC=1 start SessionStart)"
case "$out" in *"無法判斷啟動參數"*"ps"*) ;; *) fail "ps 失敗要大聲報：$out" ;; esac
case "$out" in *"opsx relaunch"*) fail "ps 失敗時不印救法：$out" ;; esac
echo ok
