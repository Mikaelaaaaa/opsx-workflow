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
assert_grep '^agent prompt retry-backoff /apply retry-backoff --wait$' "$OPSX_FAKE_LOG"
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
assert_eq "$(sed -n 2,4p "$OPSX_FAKE_LOG" | tr '\n' '|')" "agent prompt retry-backoff /apply retry-backoff --wait|sleep 1|agent prompt retry-backoff /apply retry-backoff --wait|" "失敗後先 sleep poll 才再送"
echo "$out" | grep -q "可以合併" || fail "退避後要照常推進到可以合併: $out"

# --- agent_prompt_stalled：herdr 收下了，算送過；連兩次階段沒動照樣寫 gate ---
reset_apply; printf 'agent_prompt_stalled\nagent_prompt_stalled\n' > "$FX/perr"
printf '{}' > "$FX/empty.json"
cat > "$FX/on_wait_stop.sh" <<EOF
grep -q '^status: open' "$C/gates.md" 2>/dev/null && printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
true
EOF
out="$(OPSX_TEST_ON_WAIT="$FX/on_wait_stop.sh" opsx drive retry-backoff 2>&1)"; assert_eq "$?" 0 "drive stalled: $out"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 2 "stalled 兩次就該寫 gate: $(cat "$OPSX_FAKE_LOG")"
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
assert_grep '^agent prompt retry-backoff /apply retry-backoff --wait$' "$OPSX_FAKE_LOG"
unset OPSX_TEST_PROMPT_ERR

# --- 同一個 /stage 連送兩次階段都沒動 → 寫 gate（附 pane 最後幾行），照 gate 等；不送第三次 ---
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
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 2 "卡住時只送兩次: $(cat "$OPSX_FAKE_LOG")"
assert_grep '^## drive-apply-1$' "$C/gates.md"
assert_eq "$(cat "$KL")" "$(printf 'drive gates=1\nopsx coordinate --kick')" "寫完 stuck gate 之後才 kick"
assert_grep 'drive 卡在 /apply' "$C/gates.md"
assert_grep '^type: decision$' "$C/gates.md"
assert_grep '^status: open$' "$C/gates.md"
assert_grep '卡住了' "$C/gates.md"
assert_grep '^agent wait retry-backoff --until working --timeout 0$' "$OPSX_FAKE_LOG"
assert_not_grep 'opsx stop' "$C/gates.md"   # 選項會變成送給 agent 的按鈕，不能叫 agent 停自己
unset OPSX_TEST_ON_WAIT OPSX_TEST_PANE_TEXT
export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"
printf '{"Agentory-CS/retry-backoff":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"

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
