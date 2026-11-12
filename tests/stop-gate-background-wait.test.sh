#!/usr/bin/env bash
# Stop hook：背景工作（Monitor、背景 Bash、背景 subagent）還在跑，或剛答覆完「卡在接」gate 的那一輪，都不算沒接站。
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
row "啟動時間在未來" block -10

# 兩個 task-id：終態通知只結束自己那一個
rm -rf "$STOP_STATE"; { start_monitor job1; start_monitor job2; notify job1 completed; } > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" allow "job1 結束 job2 還在跑要放行: $out"
rm -rf "$STOP_STATE"; { start_monitor job1; start_monitor job2; notify job2 completed; } > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" allow "job2 結束 job1 還在跑要放行: $out"
rm -rf "$STOP_STATE"; { start_monitor job1; start_monitor job2; notify job1 completed; notify job2 failed; } > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "兩個都結束要擋: $out"
# 前景 subagent 的結果也有 agentId，但 status 不是 async_launched
rm -rf "$STOP_STATE"; printf '{"type":"user","timestamp":"%s","toolUseResult":{"status":"completed","agentId":"fg1"}}\n' "$(ago 5)" > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "前景 subagent 不算背景工作: $out"
# 壞行不拖垮整份判斷：截斷的半行、字串型 toolUseResult、沒有毫秒的時間戳
rm -rf "$STOP_STATE"; { printf '{"type":"us\n'; printf '{"type":"user","toolUseResult":"Error: nope"}\n'; start_monitor job1; } > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" allow "壞行旁邊的背景工作仍要放行: $out"
rm -rf "$STOP_STATE"; printf '{"type":"user","timestamp":"%s","toolUseResult":{"taskId":"job1","timeoutMs":900000,"persistent":false}}\n' "$(ago 5 | sed 's/\.000Z$/Z/')" > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" allow "沒有毫秒的時間戳要放行: $out"
rm -rf "$STOP_STATE"; printf '{"type":"us\n' > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "只有壞行要擋: $out"

# 20 MB 的 transcript：只讀尾端，要在 hook 的 10 秒上限內判完
rm -rf "$STOP_STATE"; { yes '{"type":"assistant","message":"filler"}' | head -c 20000000; start_monitor job1; } > "$T"
SECONDS=0; out="$(sg "$T")"
assert_eq "$(decision "$out")" allow "大 transcript 尾端的背景工作要放行: $out"
[ "$SECONDS" -le 3 ] || fail "大 transcript 判斷花了 ${SECONDS} 秒，hook 上限 10 秒"

# 7200 秒邊界：直接呼叫函式，now 明給
printf '{"type":"user","timestamp":"2026-11-12T00:00:00.000Z","toolUseResult":{"taskId":"job1","timeoutMs":900000,"persistent":false}}\n' > "$T"
E="$(python3 -I -c 'import datetime; print(int(datetime.datetime(2026, 11, 12, tzinfo=datetime.timezone.utc).timestamp()))')"
running() { ( source "$OPSX_ROOT/bin/lib/stage.sh"; st_background_running "$T" "$1" ); }
assert_rc 0 running "$((E + 7200))"
assert_rc 1 running "$((E + 7201))"
assert_rc 1 running "$((E - 1))"

# --- 背景放行不重設擋的次數：擋、擋、背景放行、背景結束、再擋，第 3 次擋之後要開 gate ---
rm -rf "$STOP_STATE"; rm -f "$C/gates.md"; : > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "計數 1"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "計數 2"
start_monitor job1 > "$T"
out="$(sg "$T")"; assert_eq "$out" "" "背景放行"
: > "$T"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "背景結束後第 3 次擋"
out="$(sg "$T")"; assert_eq "$out" "" "第 3 次之後開 gate 放行"
assert_eq "$(stuck_gates)" 1 "背景放行不能把次數歸零"

# --- 答覆「卡在接」gate 那一輪不計次 ---
rm -rf "$STOP_STATE"; rm -f "$C/gates.md"; : > "$T"
for i in 1 2 3; do out="$(sg "$T")"; assert_eq "$(decision "$out")" block "gate 前第 $i 次擋"; done
out="$(sg "$T")"; assert_eq "$out" "" "擋滿後開 gate 放行"
assert_eq "$(stuck_gates)" 1 "擋滿開一張 gate"
# gate 寫完立刻被答覆（中間沒有別的 Stop）：答覆那一輪擋停但不計次，不開新 gate
sed 's/^status: open$/status: answered/' "$C/gates.md" > "$C/gates.md.new" && mv "$C/gates.md.new" "$C/gates.md"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "gate 寫完立刻答覆，那一輪仍擋停"
assert_eq "$(stuck_gates)" 1 "答覆那一輪不開新 gate"
read -r _ n gated _ < "$STOP_STATE/Acmecorp-AI-eval-core"; assert_eq "$n $gated" "0 -" "答覆那一輪不計次"
# 答覆那一輪指紋變了（有新 commit）：重新從 1 算
rm -rf "$STOP_STATE"; rm -f "$C/gates.md"
for i in 1 2 3; do out="$(sg "$T")"; done
out="$(sg "$T")"
sed 's/^status: open$/status: answered/' "$C/gates.md" > "$C/gates.md.new" && mv "$C/gates.md.new" "$C/gates.md"
git -C "$R" commit -q --allow-empty -m "feat: answer turn"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "答覆那一輪有新 commit 仍擋停"
read -r _ n _ < "$STOP_STATE/Acmecorp-AI-eval-core"; assert_eq "$n" 1 "指紋變了從 1 算"
# 還沒答覆的 gate：維持放行，不再開，答覆後那一輪擋停不計次
rm -rf "$STOP_STATE"; rm -f "$C/gates.md"
for i in 1 2 3; do out="$(sg "$T")"; done
out="$(sg "$T")"; assert_eq "$out" "" "擋滿後開 gate 放行（第二輪）"
out="$(sg "$T")"; assert_eq "$out" "" "gate open 時放行"
assert_eq "$(stuck_gates)" 1 "gate open 時不再開"
sed 's/^status: open$/status: answered/' "$C/gates.md" > "$C/gates.md.new" && mv "$C/gates.md.new" "$C/gates.md"
out="$(sg "$T")"; assert_eq "$(decision "$out")" block "答覆那一輪擋停"
assert_eq "$(stuck_gates)" 1 "答覆那一輪不開新 gate"
read -r _ n gated _ < "$STOP_STATE/Acmecorp-AI-eval-core"; assert_eq "$n $gated" "0 -" "答覆那一輪之後次數歸零且不再是 gated"
# 反例：之後仍不接站，照樣擋 3 次再開下一張
for i in 1 2 3; do out="$(sg "$T")"; assert_eq "$(decision "$out")" block "答覆後第 $i 次擋"; done
out="$(sg "$T")"; assert_eq "$out" "" "答覆後擋滿再開 gate 放行"
assert_eq "$(stuck_gates)" 2 "答覆後仍不接站要開第二張"
assert_grep '^## 卡在接 /apply #2' "$C/gates.md"

echo "stop-gate-background-wait ok"
