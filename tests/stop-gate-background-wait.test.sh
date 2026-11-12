#!/usr/bin/env bash
# Stop hook：背景工作（Monitor、背景 Bash、背景 subagent）還在跑，或剛答覆完「卡在接」gate 的那一輪，都不算沒接站。
# 驗收：openspec/changes/me-20261112-1052/specs/stop-gate-background-wait/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI git@gitlab.example.com:acmecorp/Acmecorp-AI.git)"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$C/explore.md"
printf '## 1. x\n\n- [x] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"
STOP_STATE="$OPSX_STATE_DIR/stop-chain"
T="$FX/transcript.jsonl"

# sg [transcript]：不給 transcript 就不帶 transcript_path；狀態檔跟著呼叫累積，要重算的 case 自己清
sg() {
  local tp=""; [ -z "${1:-}" ] || tp=",\"transcript_path\":\"$1\""
  printf '{"cwd":"%s","stop_hook_active":false%s}' "$R" "$tp" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true
}
decision() { [ -z "$1" ] && { echo allow; return; }; printf '%s' "$1" | jq -r '.decision // "allow"'; }
ago() { python3 -I -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%S.000Z"))' "$1"; }
# 三種啟動記錄與結束通知，形狀取自 Claude Code 2.1.322 的 transcript
start_monitor() { printf '{"type":"user","timestamp":"%s","toolUseResult":{"taskId":"%s","timeoutMs":900000,"persistent":false}}\n' "$(ago "${2:-5}")" "$1"; }
start_bash() { printf '{"type":"user","timestamp":"%s","toolUseResult":{"stdout":"","stderr":"","interrupted":false,"backgroundTaskId":"%s"}}\n' "$(ago "${2:-5}")" "$1"; }
start_agent() { printf '{"type":"user","timestamp":"%s","toolUseResult":{"isAsync":true,"status":"async_launched","agentId":"%s","description":"x"}}\n' "$(ago "${2:-5}")" "$1"; }
notify() { printf '{"type":"queue-operation","operation":"enqueue","timestamp":"%s","content":"<task-notification>\\n<task-id>%s</task-id>\\n<tool-use-id>toolu_x</tool-use-id>\\n<status>%s</status>\\n<summary>x</summary>\\n</task-notification>"}\n' "$(ago 1)" "$1" "$2"; }
stuck_gates() { [ -f "$C/gates.md" ] || { echo 0; return; }; grep -c '^## 卡在接 /apply' "$C/gates.md" || true; }

# --- 正例：三種背景工作各自還在跑，連停三次都放行，不計次、不開 gate ---
for kind in monitor bash agent; do
  rm -rf "$STOP_STATE"; rm -f "$C/gates.md"
  "start_$kind" job1 > "$T"
  for i in 1 2 3; do
    out="$(sg "$T")"; assert_eq "$(decision "$out")" allow "$kind 還在跑第 $i 次要放行: $out"
  done
  assert_no_file "$STOP_STATE/Acmecorp-AI-eval-core"
  assert_eq "$(stuck_gates)" 0 "$kind 還在跑不能開卡在接 gate"
done

# --- 反例：沒有背景工作、沒有 transcript_path、transcript 不存在，都照擋 ---
rm -rf "$STOP_STATE"; : > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "沒有背景工作要擋"
printf '%s' "$out" | jq -r '.reason' | grep -q '/opsx-workflow:apply' || fail "要叫 invoke apply: $out"
rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "沒有 transcript_path 要擋"
rm -rf "$STOP_STATE"
out="$(sg "$FX/no-such-transcript.jsonl")"; assert_eq "$(decision "$out")" block "transcript 不存在要擋"

# --- 正例：放行時回報協調者「等背景工作」 ---
CL="$FX/coord.log"; mkdir -p "$FX/cbin"
printf '#!/usr/bin/env bash\nexec bash "%s/tests/fakes/herdr" "$@"\n' "$OPSX_ROOT" > "$FX/cbin/herdr"; chmod +x "$FX/cbin/herdr"
rm -rf "$STOP_STATE" "$OPSX_STATE_DIR/stop-said"; : > "$CL"; start_monitor job1 > "$T"
printf '{"cwd":"%s","transcript_path":"%s"}' "$R" "$T" | PATH="$FX/cbin:$PATH" OPSX_FAKE_LOG="$CL" OPSX_TEST_COORDINATOR_UP=1 bash "$H/openspec-stop-gate.sh" > /dev/null 2>&1
assert_grep '^agent prompt opsx-coordinator \[eval-core\] 停住：等背景工作（apply 站）' "$CL"

# --- Scenario Outline：結束狀態與 120 分鐘上限，每一列一個斷言 ---
row() { # <說明> <allow|block> <啟動分鐘前> [通知 status]
  rm -rf "$STOP_STATE"; rm -f "$C/gates.md"
  start_monitor job1 "$3" > "$T"; [ -z "${4:-}" ] || notify job1 "$4" >> "$T"
  out="$(sg "$T")"; assert_eq "$(decision "$out")" "$2" "$1: $out"
}
row "completed" block 5 completed
row "failed" block 5 failed
row "killed" block 5 killed
row "stopped" block 5 stopped
row "沒有通知" allow 5
row "status 是 running" allow 5 running
row "119 分鐘前啟動" allow 119
row "121 分鐘前啟動" block 121

# --- 答覆「卡在接」gate 那一輪不計次 ---
rm -rf "$STOP_STATE"; rm -f "$C/gates.md"; : > "$T"
for i in 1 2 3; do out="$(sg "$T")"; assert_eq "$(decision "$out")" block "gate 前第 $i 次擋"; done
out="$(sg "$T")"; assert_eq "$out" "" "擋滿後開 gate 放行"
assert_eq "$(stuck_gates)" 1 "擋滿開一張 gate"
# gate 還沒答：維持放行，不再開
out="$(sg "$T")"; assert_eq "$out" "" "gate open 時放行"
assert_eq "$(stuck_gates)" 1 "gate open 時不再開"
# 答覆：第一次 Stop 放行一次，不開新 gate
sed 's/^status: open$/status: answered/' "$C/gates.md" > "$C/gates.md.new" && mv "$C/gates.md.new" "$C/gates.md"
out="$(sg "$T")"; assert_eq "$out" "" "答覆那一輪放行一次"
assert_eq "$(stuck_gates)" 1 "答覆那一輪不開新 gate"
read -r _ n gated _ < "$STOP_STATE/Acmecorp-AI-eval-core"; assert_eq "$n $gated" "0 -" "答覆那一輪之後次數歸零且不再是 gated"
# 反例：之後仍不接站，照樣擋 3 次再開下一張
for i in 1 2 3; do out="$(sg "$T")"; assert_eq "$(decision "$out")" block "答覆後第 $i 次擋"; done
out="$(sg "$T")"; assert_eq "$out" "" "答覆後擋滿再開 gate 放行"
assert_eq "$(stuck_gates)" 2 "答覆後仍不接站要開第二張"
assert_grep '^## 卡在接 /apply #2' "$C/gates.md"

echo "stop-gate-background-wait ok"
