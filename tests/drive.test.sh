#!/usr/bin/env bash
# opsx drive：假 herdr 的 agent prompt 會推進 fixture，看迴圈走的順序和停的地方。要求檔 §3.6 自主程度表。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_DRIVE_POLL=0 OPSX_DRIVE_MAX=20

R="$(mk_repo Agentory-CS)"; C="$R/openspec/changes/retry-backoff"; mkdir -p "$C" "$OPSX_STATE_DIR"
# opsx coordinate 走 fake（記到 kick.log，連同當下 gates.md 有幾個 drive gate），其他子命令照常跑真的
KL="$FX/kick.log"; : > "$KL"
cat > "$FX/fakebin/opsx" <<EOF
#!/usr/bin/env bash
if [ "\$1" = coordinate ]; then
  printf 'drive gates=%s\n' "\$(grep -c '^## drive-' "$C/gates.md" 2>/dev/null || true)" >> "$KL"
  OPSX_FAKE_LOG="$KL" exec bash "$FAKES/opsx" "\$@"
fi
exec bash "$OPSX_ROOT/bin/opsx" "\$@"
EOF
chmod +x "$FX/fakebin/opsx"
printf 'schema: opsx\nkind: bug-fix\n' > "$C/.openspec.yaml"
printf '## 1\n\n- [ ] 1.1 a\n  - 驗收：R1\n  - 測試：t.py\n' > "$C/tasks.md"
printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
export OPSX_TEST_GLAB_JSON="$FX/mr.json"
printf '{"state":"opened","draft":false,"has_conflicts":false,"head_pipeline":{"status":"failed"},"unresolved_discussions_count":1}' > "$OPSX_TEST_GLAB_JSON"

# 假 agent：收到 /apply → 勾完 tasks + tests green；/review → report.md；/pr → report 加 MR URL；/babysit → 把 pipeline 修綠、threads 清掉
cat > "$FX/on_prompt.sh" <<EOF
case "\$1" in
  "/opsx-workflow:apply retry-backoff") printf '## 1\n\n- [x] 1.1 a\n' > "$C/tasks.md"; printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json" ;;
  "/opsx-workflow:review retry-backoff") printf '# report\n' > "$C/report.md" ;;
  "/opsx-workflow:pr retry-backoff") printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/Agentory-CS/-/merge_requests/431\n' > "$C/report.md" ;;
  "/opsx-workflow:babysit retry-backoff") printf '{"state":"opened","draft":false,"has_conflicts":false,"head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON" ;;
esac
EOF
export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"

cd "$R"; out="$(opsx drive retry-backoff 2>&1)"; rc=$?
assert_eq "$rc" 0 "drive rc: $out"
seq="$(grep '^agent prompt' "$OPSX_FAKE_LOG" | sed 's/ --wait$//' | cut -d' ' -f4- | tr '\n' '|')"
assert_eq "$seq" "/opsx-workflow:apply retry-backoff|/opsx-workflow:review retry-backoff|/opsx-workflow:pr retry-backoff|/opsx-workflow:babysit retry-backoff|" "prompt 順序"
echo "$out" | grep -q "可以合併" || fail "要停在可以合併: $out"
assert_grep '"phase": "pr"' "$C/status.json"
# 起來先等 agent 把 dispatch 送的第一句做完，之後沒 gate 就不再 wait
assert_eq "$(head -1 "$OPSX_FAKE_LOG")" "agent wait retry-backoff" "第一個呼叫要等 agent settle"
assert_eq "$(grep -c '^agent wait' "$OPSX_FAKE_LOG")" 1 "沒 gate 只有起來那次 wait"

# --- 可以合併時觸發一輪 coordinate，沒有任何 merge 指令 ---
assert_eq "$(grep -c '^opsx coordinate --kick$' "$KL")" 1 "可以合併要 kick 一次: $(cat "$KL")"
assert_not_grep merge "$OPSX_FAKE_LOG"; assert_not_grep merge "$KL"

# --- kick 失敗照常走：還是以 0 結束，log 有一行 kick 失敗 ---
: > "$KL"; : > "$OPSX_FAKE_LOG"
out="$(OPSX_TEST_FAIL_coordinate="kick boom" opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "kick 失敗 drive 仍要 0: $out"
assert_grep '^opsx coordinate --kick$' "$KL"
echo "$out" | grep 'coordinate --kick' | grep -q 'kick boom' || fail "kick 失敗要記一行: $out"
echo "$out" | grep -q "可以合併" || fail "kick 失敗照常停在可以合併: $out"

# --- gate 開著 → 不丟 prompt，agent wait --until working；人回了（gate 關）才繼續 ---
: > "$OPSX_FAKE_LOG"
printf '## 1\n\n- [ ] 1.1 a\n' > "$C/tasks.md"; rm -f "$C/status.json" "$C/report.md"
printf '## gate 1\nstatus: open\ntype: approval\n' > "$C/gates.md"
cat > "$FX/on_wait.sh" <<EOF
case "\$*" in *"--until working"*) printf '## gate 1\nstatus: answered\n' > "$C/gates.md" ;; esac
EOF
export OPSX_TEST_ON_WAIT="$FX/on_wait.sh"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive w/ gate: $out"
assert_eq "$(sed -n 2p "$OPSX_FAKE_LOG")" "agent wait retry-backoff --until working --timeout 0" "gate 時先 wait working，不 prompt"
assert_grep '^agent prompt retry-backoff /opsx-workflow:apply retry-backoff --wait$' "$OPSX_FAKE_LOG"
# 回完 gate 時 opsx answer 已經 prompt 過 agent：drive 要等它做完（不帶 --until 的 wait）才送下一句
assert_eq "$(sed -n 3p "$OPSX_FAKE_LOG")" "agent wait retry-backoff" "gate 回完要先等 agent settle 再送 prompt"
unset OPSX_TEST_ON_WAIT

reset_apply() { : > "$OPSX_FAKE_LOG"; printf '## 1\n\n- [ ] 1.1 a\n' > "$C/tasks.md"; rm -f "$C/status.json" "$C/report.md" "$C/gates.md"; }

# --- herdr agent_blocked → 不再 prompt，改成等人在 pane 處理完 ---
reset_apply; printf 'agent_blocked\n' > "$FX/perr"; export OPSX_TEST_PROMPT_ERR="$FX/perr"
: > "$KL"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive blocked: $out"
assert_eq "$(grep -c '^opsx coordinate --kick$' "$KL")" 2 "blocked 時 kick 一次（另一次是最後可以合併）: $(cat "$KL")"
assert_eq "$(sed -n 3p "$OPSX_FAKE_LOG")" "agent wait retry-backoff --until working" "blocked 後要等 working: $(cat "$OPSX_FAKE_LOG")"
assert_eq "$(sed -n 4p "$OPSX_FAKE_LOG")" "agent wait retry-backoff" "blocked 後要等 settle"
echo "$out" | grep -q "終端機等待輸入" || fail "blocked 要說明在等人: $out"

# --- herdr agent_not_found → pane 沒了，結束，不再碰 herdr ---
reset_apply; printf 'agent_not_found\n' > "$FX/perr"
: > "$KL"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive not_found: $out"
assert_eq "$(grep -c '^opsx coordinate --kick$' "$KL")" 1 "pane 沒了要 kick 一次: $(cat "$KL")"
assert_eq "$(wc -l < "$OPSX_FAKE_LOG" | tr -d ' ')" 2 "not_found 後不該再呼叫 herdr: $(cat "$OPSX_FAKE_LOG")"
echo "$out" | grep -q "pane 沒了" || fail "not_found 要說 pane 沒了: $out"

# --- wait 回 agent_not_found 也結束 ---
reset_apply; printf '## gate 1\nstatus: open\ntype: approval\n' > "$C/gates.md"; : > "$FX/perr"
printf 'agent_not_found\n' > "$FX/werr"; export OPSX_TEST_WAIT_ERR="$FX/werr"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive wait not_found: $out"
assert_eq "$(wc -l < "$OPSX_FAKE_LOG" | tr -d ' ')" 1 "wait not_found 後不該再呼叫 herdr: $(cat "$OPSX_FAKE_LOG")"
unset OPSX_TEST_WAIT_ERR

# --- 其他錯誤 → 說出錯誤碼並退避 poll 秒（假 sleep 記進 log），之後照常推進 ---
reset_apply; printf 'boom\n' > "$FX/perr"
mkdir -p "$FX/sleepbin"; printf '#!/usr/bin/env bash\necho "sleep $*" >> "$OPSX_FAKE_LOG"\n' > "$FX/sleepbin/sleep"; chmod +x "$FX/sleepbin/sleep"
out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=1 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive generic err: $out"
echo "$out" | grep -q "回 boom，等 1 秒" || fail "一般錯誤要說碼與退避: $out"
assert_eq "$(sed -n 2,4p "$OPSX_FAKE_LOG" | tr '\n' '|')" "agent prompt retry-backoff /opsx-workflow:apply retry-backoff --wait|sleep 1|agent prompt retry-backoff /opsx-workflow:apply retry-backoff --wait|" "失敗後先 sleep poll 才再送"
echo "$out" | grep -q "可以合併" || fail "退避後要照常推進到可以合併: $out"

# --- agent_prompt_stalled：herdr 收下了，算送過；階段沒動照樣寫 gate，不再送 ---
reset_apply; printf 'agent_prompt_stalled\n' > "$FX/perr"
printf '{}' > "$FX/empty.json"
cat > "$FX/on_wait_stop.sh" <<EOF
grep -q '^status: open' "$C/gates.md" 2>/dev/null && printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
true
EOF
out="$(OPSX_TEST_ON_WAIT="$FX/on_wait_stop.sh" opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive stalled: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "stalled 一次就該寫 gate: $(cat "$OPSX_FAKE_LOG")"
assert_grep '^## drive-apply-1$' "$C/gates.md"
printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"

# --- gate 回了但 agent 沒開工（answer 的 prompt 沒送成）：wait 逾時就回頭重讀 gates.md，不永遠卡著 ---
reset_apply; : > "$FX/perr"
printf '## gate 1\nstatus: open\ntype: approval\n' > "$C/gates.md"
printf 'ok\ntimeout\n' > "$FX/werr"
cat > "$FX/on_wait_answer.sh" <<EOF
case "\$*" in *"--until working"*) printf '## gate 1\nstatus: answered\n' > "$C/gates.md" ;; esac
EOF
out="$(OPSX_TEST_WAIT_ERR="$FX/werr" OPSX_TEST_ON_WAIT="$FX/on_wait_answer.sh" opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive gate timeout: $out"
assert_eq "$(sed -n 2,3p "$OPSX_FAKE_LOG" | tr '\n' '|')" "agent wait retry-backoff --until working --timeout 0|agent wait retry-backoff --until working --timeout 0|" "逾時後重讀 gates.md 再等: $(cat "$OPSX_FAKE_LOG")"
assert_grep '^agent prompt retry-backoff /opsx-workflow:apply retry-backoff --wait$' "$OPSX_FAKE_LOG"
unset OPSX_TEST_PROMPT_ERR

# --- 送一次 /stage 階段沒動 → 寫 gate（附 pane 最後幾行），照 gate 等；不送第二次 ---
reset_apply
printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
export OPSX_TEST_ON_PROMPT="$FX/noop.sh"; : > "$FX/noop.sh"
export OPSX_TEST_PANE_TEXT="pane 最後一行：卡住了"
cat > "$FX/on_wait.sh" <<EOF
case "\$*" in *"--until working"*) printf '{}' > "$OPSX_STATE_DIR/dispatch.json" ;; esac
EOF
export OPSX_TEST_ON_WAIT="$FX/on_wait.sh"
: > "$KL"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive stuck: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "卡住時只送一次: $(cat "$OPSX_FAKE_LOG")"
assert_grep '^## drive-apply-1$' "$C/gates.md"
assert_eq "$(cat "$KL")" "$(printf 'drive gates=1\nopsx coordinate --kick')" "寫完 stuck gate 之後才 kick"
assert_grep 'drive 卡在 /opsx-workflow:apply' "$C/gates.md"
assert_grep '可能跑到別的 skill' "$C/gates.md"
assert_grep '^選項: 重做 /opsx-workflow:apply 一次' "$C/gates.md"
assert_grep '不再送 /opsx-workflow:apply' "$C/gates.md"
assert_grep '^type: decision$' "$C/gates.md"
assert_grep '^status: open$' "$C/gates.md"
assert_grep '卡住了' "$C/gates.md"
assert_grep '^agent wait retry-backoff --until working --timeout 0$' "$OPSX_FAKE_LOG"
assert_not_grep 'opsx stop' "$C/gates.md"   # 選項會變成送給 agent 的按鈕，不能叫 agent 停自己
unset OPSX_TEST_ON_WAIT OPSX_TEST_PANE_TEXT
export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"
printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"

# --- drive 自己開的 gate 被回答：「重做」才繼續（不再送階段指令，做完後驗一次），其他答案結束並 kick ---
export OPSX_TEST_ON_PROMPT="$FX/noop.sh"; export OPSX_TEST_PANE_TEXT="pane 尾巴"
cat > "$FX/answer_on_wait.sh" <<EOF
case "\$*" in *"--until working"*)
  if grep -q '^## drive-apply-2' "$C/gates.md"; then printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
  else printf '## drive-apply-1\ntype: decision\nstatus: answered\nanswer: %s\n' "\$(cat "$FX/answer.txt")" > "$C/gates.md"; fi ;;
esac
EOF
export OPSX_TEST_ON_WAIT="$FX/answer_on_wait.sh"
answered_run() { # <答案>：卡住的 gate 一開就被答掉
  reset_apply; printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
  printf '%s' "$1" > "$FX/answer.txt"; : > "$KL"
  out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive gate 答「${1}」: $out"
  assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "答「${1}」之後不該再送階段指令: $(cat "$OPSX_FAKE_LOG")"
}
answered_run "重做 /opsx-workflow:apply 一次，做不完就把卡在哪寫進 gates.md (Recommended)"
assert_grep '^## drive-apply-2$' "$C/gates.md"   # 答案已由 opsx answer 送進 agent；做完後指紋沒變，再開一個
assert_eq "$(grep -c '^opsx coordinate --kick$' "$KL")" 2 "兩個 stuck gate 各 kick 一次: $(cat "$KL")"
for a in "跳過這一步，在 decisions.tsv 寫下原因再往下走" "停在這裡，把卡在哪寫進 gates.md 等人" "先別動，我看一下"; do
  answered_run "$a"
  assert_not_grep '^## drive-apply-2$' "$C/gates.md"
  assert_eq "$(grep -c '^opsx coordinate --kick$' "$KL")" 2 "答「${a}」要再 kick 一次: $(cat "$KL")"
  echo "$out" | grep -q "不是重做" || fail "要說為什麼結束: $out"
done
# 答「重做」之後 agent 動了（tasks 勾數變）：不寫 drive-apply-2，drive 往下走、再送階段指令
cat > "$FX/answer_and_tick.sh" <<EOF
case "\$*" in *"--until working"*)
  if grep -q '^## drive-apply-2' "$C/gates.md"; then printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
  else printf '## drive-apply-1\ntype: decision\nstatus: answered\nanswer: 重做 /opsx-workflow:apply 一次\n' > "$C/gates.md"; printf '## 1\n\n- [x] 1.1 a\n' > "$C/tasks.md"; fi ;;
esac
EOF
export OPSX_TEST_ON_WAIT="$FX/answer_and_tick.sh"
reset_apply; printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 重做有動: $out"
if echo "$out" | grep -q "重做 /opsx-workflow:apply 之後階段還是沒動"; then fail "重做後 tasks 動了，不該再寫 gate: $out"; fi
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 2 "重做有動之後 drive 繼續送階段指令: $(cat "$OPSX_FAKE_LOG")"

# --- Stop hook 開的「卡在接」gate 被回答：跟 drive 自己的 gate 一樣讀答案，不拿階段指令蓋掉 ---
cat > "$FX/answer_hook_gate.sh" <<EOF
case "\$*" in *"--until working"*)
  if grep -q '^## drive-apply-1' "$C/gates.md"; then printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
  else printf '## 卡在接 /apply #1\ntype: decision\nstatus: answered\nanswer: %s\n' "\$(cat "$FX/answer.txt")" > "$C/gates.md"; [ ! -f "$FX/tick" ] || printf '## 1\n\n- [x] 1.1 a\n' > "$C/tasks.md"; fi ;;
esac
EOF
export OPSX_TEST_ON_WAIT="$FX/answer_hook_gate.sh"
hook_gate_run() { # <答案>：Stop hook 的 gate 一開始就是 open，等 agent 開工時被答掉
  reset_apply; printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
  printf '## 卡在接 /apply #1\ntype: decision\nstatus: open\n' > "$C/gates.md"
  printf '%s' "$1" > "$FX/answer.txt"; : > "$KL"
  out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "卡在接 gate 答「${1}」: $out"
}
rm -f "$FX/tick"
hook_gate_run "停在這裡，把卡在哪寫進 gates.md 等人"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 0 "卡在接 gate 答停在這裡，不該送階段指令: $(cat "$OPSX_FAKE_LOG")"
echo "$out" | grep -q "不是重做" || fail "卡在接 gate 答停在這裡，要說為什麼結束: $out"
hook_gate_run "重做 /opsx-workflow:apply 一次，做不完就把卡在哪寫進 gates.md (Recommended)"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 0 "卡在接 gate 答重做但沒動，不該送階段指令: $(cat "$OPSX_FAKE_LOG")"
assert_grep '^## drive-apply-1$' "$C/gates.md"
: > "$FX/tick"
hook_gate_run "重做 /opsx-workflow:apply 一次，做不完就把卡在哪寫進 gates.md (Recommended)"
if echo "$out" | grep -q "重做 /opsx-workflow:apply 之後階段還是沒動"; then fail "卡在接 gate 重做後 tasks 動了，不該寫 gate 說沒動: $out"; fi
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "卡在接 gate 重做有動之後 drive 繼續送階段指令: $(cat "$OPSX_FAKE_LOG")"
rm -f "$FX/tick"
unset OPSX_TEST_ON_WAIT OPSX_TEST_PANE_TEXT
export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"

# --- agent 立刻失敗（送出後階段沒動，pane 尾巴有 API 錯誤）→ 不寫 gate、不立刻重送、退避 poll 秒；再失敗翻倍 ---
reset_apply; printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
export OPSX_TEST_ON_PROMPT="$FX/noop.sh" OPSX_TEST_PANE_TEXT="API Error: HTTP 429 rate_limit"
out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=7 OPSX_DRIVE_MAX=1 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 429: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "429 尾巴只送一次: $(cat "$OPSX_FAKE_LOG")"
assert_grep '^sleep 7$' "$OPSX_FAKE_LOG"
if [ -f "$C/gates.md" ]; then assert_not_grep '^## drive-' "$C/gates.md"; fi
echo "$out" | grep -q "退避 7 秒" || fail "要說退避多久: $out"
reset_apply
out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=7 OPSX_DRIVE_MAX=2 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 429 兩輪: $out"
assert_grep '^sleep 14$' "$OPSX_FAKE_LOG"
if [ -f "$C/gates.md" ]; then assert_not_grep '^## drive-' "$C/gates.md"; fi
unset OPSX_TEST_PANE_TEXT
# --- 送出後階段沒動，但 pane 顯示背景工作或 subagent 在跑 → 不寫 gate、不重送、睡 poll 秒；輸入框與一般輸出照樣寫 gate ---
for t in "1 shell / 1 monitor still running" "general-purpose 8m"; do
  reset_apply; printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
  export OPSX_TEST_ON_PROMPT="$FX/noop.sh" OPSX_TEST_PANE_TEXT="$t"
  out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=7 OPSX_DRIVE_MAX=1 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 背景工作「${t}」: $out"
  assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "「${t}」只送一次: $(cat "$OPSX_FAKE_LOG")"
  assert_grep '^sleep 7$' "$OPSX_FAKE_LOG"
  if [ -f "$C/gates.md" ]; then assert_not_grep '^## drive-' "$C/gates.md"; fi
done
for t in "❯ " "● Bash(ls) Running…" "Plan 3 steps"; do
  reset_apply; printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
  export OPSX_TEST_ON_PROMPT="$FX/noop.sh" OPSX_TEST_PANE_TEXT="$t"
  out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=7 OPSX_DRIVE_MAX=1 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 沒有背景工作「${t}」: $out"
  assert_grep '^## drive-apply-1$' "$C/gates.md"
done
# 背景工作等過一輪之後仍在跑：不重送階段指令（間隔下限被 --wait 加 sleep 吃掉，只靠它擋不住）
reset_apply; printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
export OPSX_TEST_ON_PROMPT="$FX/noop.sh" OPSX_TEST_PANE_TEXT="1 shell / 1 monitor still running"
out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=7 OPSX_DRIVE_MAX=2 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 背景工作兩輪: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "背景工作還在跑時第二輪不重送: $(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c '^sleep 7$' "$OPSX_FAKE_LOG")" 2 "兩輪各等一次: $(cat "$OPSX_FAKE_LOG")"
if [ -f "$C/gates.md" ]; then assert_not_grep '^## drive-' "$C/gates.md"; fi
# 背景工作結束（第二次讀 pane 只剩輸入框）而指紋仍沒動：寫 gate，不重送
reset_apply; printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '1 shell / 1 monitor still running\n' > "$FX/pane_once"
export OPSX_TEST_PANE_TEXT="❯ " OPSX_TEST_PANE_ONCE="$FX/pane_once"
out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=7 OPSX_DRIVE_MAX=2 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 背景工作結束: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "背景工作結束也不重送: $(cat "$OPSX_FAKE_LOG")"
assert_grep '^## drive-apply-1$' "$C/gates.md"
unset OPSX_TEST_PANE_ONCE
unset OPSX_TEST_PANE_TEXT
# --- 同階段相鄰兩次送出之間至少隔 poll 秒（扣掉已經過的時間） ---
reset_apply; printf '## 1\n\n- [ ] 1.1 a\n- [ ] 1.2 b\n- [ ] 1.3 c\n' > "$C/tasks.md"
cat > "$FX/tick.sh" <<EOF
awk '!d && /- \[ \]/ {sub(/\[ \]/, "[x]"); d = 1} {print}' "$C/tasks.md" > "$C/tasks.tmp" && mv "$C/tasks.tmp" "$C/tasks.md"
EOF
export OPSX_TEST_ON_PROMPT="$FX/tick.sh"
out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=1000 OPSX_DRIVE_MAX=2 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 間隔: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 2 "兩輪各送一次: $(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c '^sleep' "$OPSX_FAKE_LOG")" 1 "第二次送出前 sleep 一次: $(cat "$OPSX_FAKE_LOG")"
gap="$(grep '^sleep' "$OPSX_FAKE_LOG" | cut -d' ' -f2)"
[ "$gap" -ge 990 ] && [ "$gap" -le 1000 ] || fail "間隔要接近 poll 秒，得到 $gap"
# --- 送出逾時（prompt 已送、agent 還沒 settle）也算一次送出：第二次送出前照樣受下限 ---
reset_apply; printf 'timeout\n' > "$FX/perr"; export OPSX_TEST_PROMPT_ERR="$FX/perr" OPSX_TEST_ON_PROMPT="$FX/noop.sh"
out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=1000 OPSX_DRIVE_MAX=2 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 逾時: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 2 "逾時後再送一次: $(cat "$OPSX_FAKE_LOG")"
gap="$(grep '^sleep' "$OPSX_FAKE_LOG" | head -1 | cut -d' ' -f2)"
[ -n "$gap" ] && [ "$gap" -ge 990 ] && [ "$gap" -le 1000 ] || fail "逾時後的第二次送出前要 sleep 接近 poll 秒，得到「${gap}」: $(cat "$OPSX_FAKE_LOG")"
unset OPSX_TEST_PROMPT_ERR
# --- 退避有動歸零：失敗、有動、再失敗，第二次退避仍是 poll 秒，不是翻倍 ---
reset_apply; printf '0' > "$FX/cnt"
cat > "$FX/flaky.sh" <<EOF
n="\$(cat "$FX/cnt")"; printf '%s' \$((n + 1)) > "$FX/cnt"
[ "\$n" = 1 ] && printf '{"phase":"apply","step":1,"total":8,"label":"x","tests":"red","at":"2026-11-05T17:00:00+08:00"}' > "$C/status.json"
true
EOF
export OPSX_TEST_ON_PROMPT="$FX/flaky.sh" OPSX_TEST_PANE_TEXT="API Error: HTTP 429 rate_limit"
out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=7 OPSX_DRIVE_MAX=3 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 歸零: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 3 "三輪各送一次: $(cat "$OPSX_FAKE_LOG")"
assert_eq "$(printf '%s\n' "$out" | grep -c '退避 7 秒')" 2 "有動之後退避要從 poll 秒重來: $out"
assert_not_grep '^sleep 14$' "$OPSX_FAKE_LOG"
unset OPSX_TEST_PANE_TEXT
export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"
# --- 階段前進的那一輪不受限：apply → review → pr 之間不 sleep ---
reset_apply; export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"
out="$(PATH="$FX/sleepbin:$PATH" OPSX_DRIVE_POLL=1000 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 階段前進: $out"
sed '/opsx-workflow:pr /q' "$OPSX_FAKE_LOG" > "$FX/upto_pr.log"
assert_grep 'opsx-workflow:review' "$FX/upto_pr.log"; assert_not_grep '^sleep' "$FX/upto_pr.log"

# --- 送一次後有動就不寫 gate：階段、tasks 勾數、status.json 的 at、gate 數各一案（只跑一輪，看送完那刻有沒有 drive gate） ---
run_once() { # <名稱>：fixture 與 $FX/moved.sh 已備好
  printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
  export OPSX_TEST_ON_PROMPT="$FX/moved.sh"
  out="$(OPSX_DRIVE_MAX=1 opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 有動($1): $out"
  assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "有動($1)只送一次: $(cat "$OPSX_FAKE_LOG")"
  if [ -f "$C/gates.md" ]; then assert_not_grep '^## drive-' "$C/gates.md"; fi
}
reset_apply   # 階段變：tasks 全勾且 tests green 是 review，agent 寫出 report.md 之後是 pr
printf '## 1\n\n- [x] 1.1 a\n' > "$C/tasks.md"
printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
printf 'printf "# report\\n" > "%s/report.md"\n' "$C" > "$FX/moved.sh"; run_once 階段變
reset_apply   # 勾數變：階段仍是 apply
printf '## 1\n\n- [ ] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"
printf 'printf "## 1\\n\\n- [x] 1.1 a\\n- [ ] 1.2 b\\n" > "%s/tasks.md"\n' "$C" > "$FX/moved.sh"; run_once 勾數變
reset_apply   # status.json 的 at 變，其他都沒動
printf '{"phase":"apply","step":1,"total":8,"label":"x","tests":"red","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
printf 'printf "{\\"phase\\":\\"apply\\",\\"step\\":2,\\"total\\":8,\\"label\\":\\"x\\",\\"tests\\":\\"red\\",\\"at\\":\\"2026-11-05T16:00:00+08:00\\"}" > "%s/status.json"\n' "$C" > "$FX/moved.sh"; run_once at變
reset_apply   # gate 數變：新增的 gate 已答，不擋迴圈
printf 'printf "## g1\\nstatus: answered\\n" >> "%s/gates.md"\n' "$C" > "$FX/moved.sh"; run_once gate數變
export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"

# --- drive 自己登記 pid 並把 mode 正規化成 autopilot；結束時清掉自己的 pid ---
reset_apply
cat > "$FX/snap.sh" <<EOF
cp "$OPSX_STATE_DIR/dispatch.json" "$FX/snap.json"
bash "$FX/on_prompt.sh" "\$1"
EOF
export OPSX_TEST_ON_PROMPT="$FX/snap.sh"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive register: $out"
assert_eq "$(jq -r '."Agentory-CS/retry-backoff".drive_pid | type' "$FX/snap.json")" number "跑的時候 drive_pid 要是數字"
assert_eq "$(jq -r '."Agentory-CS/retry-backoff".mode' "$FX/snap.json")" autopilot "drive 要正規化成 autopilot"
assert_eq "$(jq -r '."Agentory-CS/retry-backoff".drive_pid' "$OPSX_STATE_DIR/dispatch.json")" null "結束後清掉自己的 pid"
export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"

# --- 已經有一支活著的 drive → 拒絕，不碰 herdr ---
reset_apply
printf '{"Agentory-CS/retry-backoff":{"mode":"autopilot","pane":"p42","grants":[],"drive_pid":%s}}' "$$" > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx drive retry-backoff 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "活著的 drive_pid 要拒絕: $out"
echo "$out" | grep -q "$$" || fail "拒絕訊息要有那個 pid: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不該碰 herdr"

# --- 不在 dispatch.json（被 stop）→ 立刻結束，不碰 herdr ---
: > "$OPSX_FAKE_LOG"; printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0; assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "stopped card 不該碰 herdr"
echo "$out" | grep -q "不在 dispatch.json" || fail "要說明為什麼結束: $out"
: > "$OPSX_FAKE_LOG"; printf '{"Agentory-CS/retry-backoff":{"mode":"stopped","pane":"p42","grants":[],"drive_pid":null}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0; assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "stopped 的卡不該碰 herdr"
assert_eq "$(jq -r '."Agentory-CS/retry-backoff".drive_pid' "$OPSX_STATE_DIR/dispatch.json")" null "stopped 的卡不登記 pid"

# --- 跑到一半卡被 /archive 搬走（fixture 沒有 workplan）→ 結束，搬走之後不再送 prompt，不寫 gate ---
reset_apply
printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
mkdir -p "$R/openspec/changes/archive"
cat > "$FX/archive_on_prompt.sh" <<EOF
mv "$C" "$R/openspec/changes/archive/2026-11-10-retry-backoff"
EOF
export OPSX_TEST_ON_PROMPT="$FX/archive_on_prompt.sh"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 卡被歸檔: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "歸檔後不該再送 prompt: $(cat "$OPSX_FAKE_LOG")"
echo "$out" | grep -q "已歸檔" || fail "要說已歸檔: $out"
[ ! -e "$R/openspec/changes/archive/2026-11-10-retry-backoff/gates.md" ] || fail "歸檔之後不該有人再寫 gate"

# --- 第一輪等 agent settle 的時候卡被搬走（手動掛 drive 時 agent 正在跑 /archive）→ 一個 prompt 都不送 ---
rm -rf "$R/openspec/changes/archive/2026-11-10-retry-backoff"; mkdir -p "$C"
printf 'schema: opsx\nkind: bug-fix\n' > "$C/.openspec.yaml"; reset_apply
printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
cat > "$FX/archive_on_wait.sh" <<EOF
mv "$C" "$R/openspec/changes/archive/2026-11-10-retry-backoff"
EOF
export OPSX_TEST_ON_WAIT="$FX/archive_on_wait.sh"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 第一輪 settle 時卡被歸檔: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 0 "settle 時被歸檔不該送任何 prompt: $(cat "$OPSX_FAKE_LOG")"
echo "$out" | grep -q "已歸檔" || fail "要說已歸檔: $out"
unset OPSX_TEST_ON_WAIT

# --- 卡目錄被直接刪掉（archive/ 底下也沒有）→ 同樣結束，訊息不同 ---
rm -rf "$R/openspec/changes/archive/2026-11-10-retry-backoff"; mkdir -p "$C"
printf 'schema: opsx\nkind: bug-fix\n' > "$C/.openspec.yaml"; reset_apply
printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
printf 'rm -rf "%s"\n' "$C" > "$FX/delete_on_prompt.sh"
export OPSX_TEST_ON_PROMPT="$FX/delete_on_prompt.sh"
out="$(opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive 卡被刪: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "刪掉後不該再送 prompt: $(cat "$OPSX_FAKE_LOG")"
echo "$out" | grep -q "卡目錄不見了" || fail "要說卡目錄不見了: $out"
[ ! -e "$C" ] || fail "不該重建卡目錄: $(ls -A "$C")"
echo ok
