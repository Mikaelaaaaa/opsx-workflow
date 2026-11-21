#!/usr/bin/env bash
# opsx dispatch / stop：用假 herdr 驗呼叫順序和寫下的檔。要求檔 §3.6「派」、§3.1。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
# glab 的每次呼叫另外記在不會被清空的檔（OPSX_FAKE_LOG 中途會被清掉），結尾檢查沒有人查真的 GitLab project
: > "$FX/glab-all.log"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/glab-all.log"\nexec bash "%s/glab" "$@"\n' "$FX" "$FAKES" > "$FX/fakebin/glab"
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
# opsx coordinate 走 fake，記到 kick.log：drive kick 的真 coordinate 會在背景跑 collect，把 agent list 寫進 herdr log
KL="$FX/kick.log"; : > "$KL"
cat > "$FX/fakebin/opsx" <<EOF
#!/usr/bin/env bash
[ "\$1" = coordinate ] && OPSX_FAKE_LOG="$KL" exec bash "$FAKES/opsx" "\$@"
exec bash "$OPSX_ROOT/bin/opsx" "\$@"
EOF
chmod +x "$FX/fakebin/opsx"
export OPSX_USER=mikaela
export OPSX_DRIVE_MAX=0   # autopilot 會在背景起 drive；0 輪讓它登記完就結束，不在 fixture 上跑迴圈
export OPSX_DRIVE_POLL=0  # drive 起來第一次送出前會先睡間隔下限；要跑 1 輪的案例不能真的睡預設的 300 秒
wait_drive() { # <repo> <slug>：等背景 drive 跑完（log 出現結束那行），最多 5 秒
  local f="$OPSX_STATE_DIR/drive-$1-$2.log" n=0
  until grep -q '跑滿 [01] 輪' "$f" 2>/dev/null; do n=$((n+1)); [ $n -lt 50 ] || fail "drive 沒在背景起來：$f"; sleep 0.1; done
}

R="$(mk_repo Acmecorp-CS git@gitlab.example.com:acmecorp/Acmecorp-CS.git)"
mkdir -p "$R/openspec/changes/retry-backoff" "$OPSX_STATE_DIR"
printf 'schema: opsx\ncreated: 2026-11-05\n' > "$R/openspec/changes/retry-backoff/.openspec.yaml"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$R/openspec/changes/retry-backoff/explore.md"
printf '[repos]\n"Acmecorp-CS" = "acmecorp-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"   # label，dispatch 用 workspace list 換成 w1
printf '[repos."Acmecorp-CS"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"

# --- 邊界：slug 不合法 / 卡不存在 / mode 不對 → rc 2，不碰 herdr ---
cd "$R"
assert_rc 2 opsx dispatch "Bad Slug" --agent claude
assert_rc 2 opsx dispatch nope --agent claude
assert_rc 2 opsx dispatch retry-backoff --mode yolo
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "沒派出去不該碰 herdr"

# --- 正常：autopilot，kind 從對話框給，model 照 kind ---
# 背景 drive 起來第一件事是 herdr agent wait：在那時候抓 dispatch.json，看 drive 有沒有用 dispatch 寫的 key 登記自己
printf 'cp "%s" "%s"\n' "$OPSX_STATE_DIR/dispatch.json" "$FX/drive-snap.json" > "$FX/snap-wait.sh"
out="$(OPSX_DRIVE_MAX=1 OPSX_TEST_ON_WAIT="$FX/snap-wait.sh" opsx dispatch retry-backoff --agent claude --mode autopilot --kind bug-fix 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
case "$out" in *還沒信任*) ;; *) fail "沒信任過的 repo，dispatch 要警告：$out" ;; esac   # fixture 沒有 .claude.json
wait_drive Acmecorp-CS retry-backoff   # autopilot 一律起 drive
# 這一輪送了 propose 但 fixture 的階段不會動，drive 寫 gate 後 kick 一次
assert_eq "$(grep -c '^opsx coordinate --kick$' "$KL")" 1 "drive 的 kick 要進假 coordinate: $(cat "$KL")"
assert_eq "$(jq -r '."Acmecorp-CS/retry-backoff".drive_pid | type' "$FX/drive-snap.json")" number "drive 跑的時候 drive_pid 要登記在 dispatch 寫的 key 下"
assert_grep '^kind: bug-fix$' "$R/openspec/changes/retry-backoff/.openspec.yaml"
[ -d "$R/.claude/worktrees/retry-backoff" ] || fail "worktree 沒開"
assert_eq "$(git -C "$R/.claude/worktrees/retry-backoff" rev-parse --abbrev-ref HEAD)" "fix/retry-backoff/mikaela" "branch 命名"
# herdr 呼叫順序：tab create（在 w1）→ agent start（帶 model + settings）→ agent prompt /propose（explore 待決空 → propose）
assert_grep '^tab create --workspace w1 --cwd .*retry-backoff --label retry-backoff' "$OPSX_FAKE_LOG"
assert_grep '^workspace list$' "$OPSX_FAKE_LOG"
assert_grep '^agent start retry-backoff --kind claude --pane w1:pE -- --model claude-sonnet-5-5 --permission-mode dontAsk --settings '"$OPSX_STATE_DIR"'/settings/Acmecorp-CS-retry-backoff-autopilot.json --add-dir ' "$OPSX_FAKE_LOG"
# 沙盒只准寫 working directories：卡的檔在主 repo 的 openspec/、hook 與 status 寫 state dir，兩個都要 --add-dir
assert_grep "^agent start retry-backoff .* --add-dir $R/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"
assert_grep '^agent prompt retry-backoff /opsx-workflow:propose retry-backoff$' "$OPSX_FAKE_LOG"
assert_not_grep '^workspace create' "$OPSX_FAKE_LOG"
# settings：repo 永遠 push 進 allow；merge 在 allow 不在 deny（deny 會蓋過 grant-gate 的放行，merge 由 gate 單獨把關）
S="$OPSX_STATE_DIR/settings/Acmecorp-CS-retry-backoff-autopilot.json"; assert_file "$S"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert "Bash(git push:*)" in d["allow"],d;assert "Bash(glab mr merge:*)" in d["allow"] and "Bash(gh pr merge:*)" in d["allow"],d;assert not any("merge" in x for x in d["deny"]),d;assert not any("glab mr create" in a for a in d["allow"]),d;assert "Bash(glab issue note:*)" not in d["allow"] and "Bash(gh issue comment:*)" not in d["allow"],d;assert not any("gh pr comment" in x or "glab api" in x for x in d["allow"]),d' "$S"
# dontAsk 下不在 allow 的指令直接被拒：常用唯讀與測試指令要在 allow 裡，不然 agent 連跑測試都不行
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];miss=[x for x in ["Bash(jq:*)","Bash(head:*)","Bash(tail:*)","Bash(wc:*)","Bash(sed -n:*)","Bash(bash tests/:*)","Bash(bash tests/*)","Bash(tests/run.sh:*)","Bash(herdr agent:*)","Bash(glab mr view:*)","Bash(glab ci view:*)","Bash(gh pr view:*)","Bash(git merge-base:*)","Bash(git merge:*)","Bash(git remote:*)"] if x not in a];assert not miss,miss' "$S" || fail "allow 少了常用指令"
# 重啟 / resume 後旗標不在，可寫目錄還要由 settings 供應
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert d["additionalDirectories"]==[sys.argv[2],sys.argv[3]],d' "$S" "$R/openspec" "$OPSX_STATE_DIR" || fail "autopilot settings 缺 additionalDirectories"
# dispatch.json
python3 -I -c '
import json,sys;d=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"]
assert d["pane"]=="w1:pE" and d["tab"]=="w1:tB" and d["workspace"]=="acmecorp-ai" and d["workspace_id"]=="w1" and d["mode"]=="autopilot" and d["kind"]=="bug-fix" and d["model"]=="claude-sonnet-5-5" and d["agent"]=="claude", d
assert d["branch"]=="fix/retry-backoff/mikaela" and d["grants"]==[] and d["once"]==[] and d["drive_pid"] is None, d' "$OPSX_STATE_DIR/dispatch.json"   # drive 跑完清掉自己的 pid
# 另一個 repo 派出同名 slug：herdr 只認名字，會送錯 agent，要拒絕
R4="$(mk_repo Acmecorp-X)"; mkdir -p "$R4/openspec/changes/retry-backoff"; printf 'schema: opsx\n' > "$R4/openspec/changes/retry-backoff/.openspec.yaml"
printf '"Acmecorp-X" = "acmecorp-ai"\n' >> "$OPSX_STATE_DIR/workspaces.toml"
out="$(cd "$R4" && opsx dispatch retry-backoff --agent claude --mode autopilot --kind dev 2>&1)"; [ $? -ne 0 ] || fail "同名 slug 要拒絕"
echo "$out" | grep -q 'Acmecorp-CS/retry-backoff' || fail "要指名撞到哪張: $out"
last_row() { tail -1 "$R/openspec/changes/retry-backoff/decisions.tsv" | cut -f2-3; }
assert_eq "$(last_row)" "你$(printf '\t')已指派"
assert_eq "$(tail -1 "$R/openspec/changes/retry-backoff/decisions.tsv" | awk -F'\t' '{print NF}')" 5

assert_not_grep 'gitlab\.example\.com' "$OPSX_FAKE_LOG"

# --- 同一張卡還在跑就再派：拒絕，說它在哪（herdr 本來就會回 agent_name_taken；板上「指派」按到舊畫面就是這條） ---
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch retry-backoff --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "active card must be refused: $out"
echo "$out" | grep -q 'acmecorp-ai · w1:tB · w1:pE' || fail "要說它在哪: $out"
echo "$out" | grep -q 'opsx stop retry-backoff' || fail "要說怎麼換人: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"

# --- agent start 回 agent_pane_busy（shell 還沒到 prompt）：同一個 pane 重試；一直 busy 就關 tab ---
export OPSX_DISPATCH_RETRY_SLEEP=0
mkdir -p "$R/openspec/changes/busy-card"; printf 'schema: opsx\n' > "$R/openspec/changes/busy-card/.openspec.yaml"
export OPSX_TEST_BUSY_LEFT="$FX/busy-left"
: > "$OPSX_FAKE_LOG"; echo 2 > "$OPSX_TEST_BUSY_LEFT"
out="$(opsx dispatch busy-card --agent claude --mode interactive --kind dev 2>&1)" || fail "busy twice should still dispatch: $out"
assert_eq "$(grep -c '^agent start busy-card ' "$OPSX_FAKE_LOG")" 3 "two busy then ok = three starts"
assert_no_file "$OPSX_STATE_DIR/drive-Acmecorp-CS-busy-card.log"   # interactive 不起 drive
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;assert "Acmecorp-CS/busy-card" in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json"
# 一直 busy：六次後放棄，關掉剛開的 tab，什麼都不記
mkdir -p "$R/openspec/changes/stuck-card"; printf 'schema: opsx\n' > "$R/openspec/changes/stuck-card/.openspec.yaml"
: > "$OPSX_FAKE_LOG"; echo 99 > "$OPSX_TEST_BUSY_LEFT"
out="$(opsx dispatch stuck-card --agent claude --mode interactive --kind dev 2>&1)"; [ $? -ne 0 ] || fail "persistent busy must fail"
assert_eq "$(grep -c '^agent start stuck-card ' "$OPSX_FAKE_LOG")" 6 "six attempts then give up"
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"
echo "$out" | grep -q 'agent_pane_busy' || fail "should print herdr error: $out"
python3 -I -c 'import json,sys;assert "Acmecorp-CS/stuck-card" not in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json"
[ -f "$R/openspec/changes/stuck-card/decisions.tsv" ] && grep -q dispatched "$R/openspec/changes/stuck-card/decisions.tsv" && fail "must not record dispatched"
# 一直 busy 的訊息要指出 shell 啟動卡住、常見原因、等了幾秒（5 次間隔 × 2 秒），並附 pane 畫面；假 sleep 讓測試不真的等
mkdir -p "$FX/nosleep"; printf '#!/usr/bin/env bash\n' > "$FX/nosleep/sleep"; chmod +x "$FX/nosleep/sleep"
echo 99 > "$OPSX_TEST_BUSY_LEFT"
out="$(PATH="$FX/nosleep:$PATH" OPSX_DISPATCH_RETRY_SLEEP=2 OPSX_TEST_PANE_TEXT='pyenv: cannot rehash: couldn'"'"'t acquire lock' opsx dispatch stuck-card --agent claude --mode interactive --kind dev 2>&1)"; [ $? -ne 0 ] || fail "persistent busy must fail"
for w in shell 提示字元 .pyenv-shim '10 秒' agent_pane_busy 'cannot rehash'; do echo "$out" | grep -qF -- "$w" || fail "busy 訊息缺「${w}」: $out"; done
echo 99 > "$OPSX_TEST_BUSY_LEFT"
out="$(opsx dispatch stuck-card --agent claude --mode interactive --kind dev 2>&1)"; [ $? -ne 0 ] || fail "persistent busy must fail"
echo "$out" | grep -qF 'pane 沒有任何輸出' || fail "pane 空的要註明: $out"
# pane 已死、pane read 失敗：當成沒輸出，照樣關 tab、印原文
: > "$OPSX_FAKE_LOG"; echo 99 > "$OPSX_TEST_BUSY_LEFT"
out="$(OPSX_TEST_PANE_READ_FAIL=1 opsx dispatch stuck-card --agent claude --mode interactive --kind dev 2>&1)"; [ $? -ne 0 ] || fail "persistent busy must fail"
echo "$out" | grep -qF 'agent_pane_busy' && echo "$out" | grep -qF 'pane 沒有任何輸出' || fail "pane read 失敗要當成沒輸出並印原文: $out"
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"
# 小數間隔：已等待秒數照算（5 × 0.5），不中止
: > "$OPSX_FAKE_LOG"; echo 99 > "$OPSX_TEST_BUSY_LEFT"
out="$(PATH="$FX/nosleep:$PATH" OPSX_DISPATCH_RETRY_SLEEP=0.5 opsx dispatch stuck-card --agent claude --mode interactive --kind dev 2>&1)"; [ $? -ne 0 ] || fail "persistent busy must fail"
echo "$out" | grep -qF '2.5 秒' || fail "小數間隔的秒數: $out"
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"
# 別的錯：不重試，一樣關 tab
: > "$OPSX_FAKE_LOG"; echo 0 > "$OPSX_TEST_BUSY_LEFT"
out="$(OPSX_TEST_START_FAIL=agent_kind_unsupported opsx dispatch stuck-card --agent claude --mode interactive --kind dev 2>&1)"; [ $? -ne 0 ] || fail "other error must fail"
assert_eq "$(grep -c '^agent start stuck-card ' "$OPSX_FAKE_LOG")" 1 "non-busy error is not retried"
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"
# herdr 還留著同名 agent 而 dispatch.json 沒記（手動開的 / stop 沒關成）：關 tab，錯誤裡印它的 workspace · tab · pane
: > "$OPSX_FAKE_LOG"
out="$(OPSX_TEST_START_FAIL=agent_name_taken opsx dispatch stuck-card --agent claude --mode interactive --kind dev 2>&1)"; [ $? -ne 0 ] || fail "name taken must fail"
echo "$out" | grep -q 'workspace_id=w9 tab_id=w9:t1' && echo "$out" | grep -q 'pane_id=w9:p1' || fail "要印出同名 agent 在哪: $out"
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;assert "Acmecorp-CS/stuck-card" not in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json"
unset OPSX_TEST_BUSY_LEFT

# --- Claude 在新 worktree 停在 trust 對話框（agent_not_ready）：dispatch 替人按 Yes，再等 idle ---
mkdir -p "$R/openspec/changes/trust-card"; printf 'schema: opsx\n' > "$R/openspec/changes/trust-card/.openspec.yaml"
export OPSX_TEST_NOT_READY_ONCE="$FX/not-ready-once"; : > "$OPSX_TEST_NOT_READY_ONCE"
export OPSX_TEST_PANE_TEXT='Quick safety check: Is this a project you created or one you trust?
 ❯ No, exit
   Yes, I trust this folder'
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch trust-card --agent claude --mode interactive --kind dev 2>&1)" || fail "trust dialog should be answered: $out"
assert_eq "$(grep -c '^agent start trust-card ' "$OPSX_FAKE_LOG")" 1 "no second start after the dialog"
assert_grep '^pane wait-output --match trust this folder .*w1:pE$' "$OPSX_FAKE_LOG"
assert_grep '^pane send-keys w1:pE down enter$' "$OPSX_FAKE_LOG"
assert_grep '^agent wait trust-card --until idle' "$OPSX_FAKE_LOG"
assert_grep '^agent prompt trust-card /opsx-workflow:explore trust-card$' "$OPSX_FAKE_LOG"
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;assert "Acmecorp-CS/trust-card" in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json"
# 不是 trust 對話框（例如要登入）：不按鍵，關 tab，把畫面印給人看
mkdir -p "$R/openspec/changes/login-card"; printf 'schema: opsx\n' > "$R/openspec/changes/login-card/.openspec.yaml"
: > "$OPSX_TEST_NOT_READY_ONCE"; export OPSX_TEST_PANE_TEXT='Please log in to continue'
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch login-card --agent claude --mode interactive --kind dev 2>&1)"; [ $? -ne 0 ] || fail "unknown startup screen must fail"
assert_not_grep '^pane send-keys' "$OPSX_FAKE_LOG"
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"
echo "$out" | grep -q 'Please log in' || fail "error should show the pane: $out"
unset OPSX_TEST_NOT_READY_ONCE OPSX_TEST_PANE_TEXT

# --- stop 過的卡重派：worktree 已在就重用，不報錯 ---
opsx stop retry-backoff >/dev/null 2>&1 || fail "stop before redispatch"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch retry-backoff --agent codex --mode interactive 2>&1)" || fail "redispatch: $out"
assert_grep '^agent start retry-backoff --kind codex --pane w1:pE -- -a on-request -s workspace-write --add-dir '"$R"'/openspec --add-dir '"$OPSX_STATE_DIR"'$' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert d["agent"]=="codex" and d["model"]=="gpt-5" and d["mode"]=="interactive",d' "$OPSX_STATE_DIR/dispatch.json" || fail "redispatch must rewrite the entry"
# interactive 的 claude 也要 --add-dir（互動模式一樣在沙盒裡）
opsx stop retry-backoff >/dev/null 2>&1 || fail "stop before redispatch"
: > "$OPSX_FAKE_LOG"
# symlink-safe-writes：settings 檔名被換成 symlink → 換成一般檔、目標不變
mkdir -p "$OPSX_STATE_DIR/settings"; printf 'keep me\n' > "$FX/victim"; rm -f "$OPSX_STATE_DIR/settings/Acmecorp-CS-retry-backoff-interactive.json"; ln -s "$FX/victim" "$OPSX_STATE_DIR/settings/Acmecorp-CS-retry-backoff-interactive.json"
opsx dispatch retry-backoff --agent claude --mode interactive >/dev/null 2>&1 || fail "redispatch interactive claude"
assert_eq "$(cat "$FX/victim")" "keep me" "settings 檔名上的 symlink 不能被寫到目標"
assert_grep "^agent start retry-backoff --kind claude --pane w1:pE -- --model claude-sonnet-5-5 --settings $OPSX_STATE_DIR/settings/Acmecorp-CS-retry-backoff-interactive.json --add-dir $R/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"   # kind 已是 bug-fix → sonnet
assert_not_grep '--permission-mode' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert d=={"additionalDirectories":[sys.argv[2],sys.argv[3]]},d' "$OPSX_STATE_DIR/settings/Acmecorp-CS-retry-backoff-interactive.json" "$R/openspec" "$OPSX_STATE_DIR" || fail "interactive settings 只該有 additionalDirectories"
# interactive 重派不能蓋掉 autopilot 那份的 allow / deny
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert d["allow"] and "Bash(git push --force:*)" in d["deny"],d' "$S" || fail "interactive 重派蓋掉了 autopilot 的 settings"

# symlink-safe-writes：drive log 是 symlink → dispatch 拒絕起 drive，非 0、訊息含路徑、目標不變
wait_drive Acmecorp-CS retry-backoff
opsx stop retry-backoff >/dev/null 2>&1 || fail "stop before drive-log symlink case"
DL="$OPSX_STATE_DIR/drive-Acmecorp-CS-retry-backoff.log"; rm -f "$DL"; printf 'keep me\n' > "$FX/victim"; ln -s "$FX/victim" "$DL"
out="$(opsx dispatch retry-backoff --agent claude --mode autopilot 2>&1)"; [ $? -ne 0 ] || fail "drive log 是 symlink 要失敗：$out"
case "$out" in *drive-Acmecorp-CS-retry-backoff.log*) ;; *) fail "訊息要含 drive log 路徑：$out" ;; esac
sleep 1
assert_eq "$(cat "$FX/victim")" "keep me" "drive log 不能附加到 symlink 的目標"
rm -f "$DL"

# --- 沒掛 workspace 的 repo → 開新 workspace 並記下來 ---
R2="$(mk_repo scam-guard https://github.com/Mikaelaaaaa/scam-guard.git)"
mkdir -p "$R2/openspec/changes/rdap-timeout"; printf 'schema: opsx\n' > "$R2/openspec/changes/rdap-timeout/.openspec.yaml"
: > "$OPSX_FAKE_LOG"; cd "$R2"
# symlink-safe-writes：workspaces.toml 是 symlink → dispatch 拒絕並說出路徑，目標不變
cp "$OPSX_STATE_DIR/workspaces.toml" "$FX/ws.real"; printf '[repos]\n' > "$FX/victim"; rm "$OPSX_STATE_DIR/workspaces.toml"; ln -s "$FX/victim" "$OPSX_STATE_DIR/workspaces.toml"
out="$(opsx dispatch rdap-timeout --agent claude --mode autopilot --kind dev 2>&1)"; [ $? -ne 0 ] || fail "workspaces.toml 是 symlink 要失敗：$out"
case "$out" in *workspaces.toml*) ;; *) fail "訊息要含 workspaces.toml：$out" ;; esac
assert_eq "$(cat "$FX/victim")" "[repos]" "workspaces.toml 不能附加到 symlink 的目標"
assert_grep '^workspace create --label scam-guard' "$OPSX_FAKE_LOG"
assert_not_grep '^tab create' "$OPSX_FAKE_LOG"   # workspace 建好就記，記不下來就不開 tab
rm "$OPSX_STATE_DIR/workspaces.toml"; cp "$FX/ws.real" "$OPSX_STATE_DIR/workspaces.toml"; : > "$OPSX_FAKE_LOG"
# workspace create 沒回 id：dispatch 失敗、workspaces.toml 不記這個 repo，下次派工會再 create（不是卡在「herdr 沒有 workspace」）
mkdir -p "$FX/wsfail"
cat > "$FX/wsfail/herdr" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "workspace create" ] && { printf '%s\n' "$*" >> "$OPSX_FAKE_LOG"; exit 0; }
exec bash "$OPSX_ROOT/tests/fakes/herdr" "$@"
EOF
chmod +x "$FX/wsfail/herdr"
out="$(PATH="$FX/wsfail:$PATH" opsx dispatch rdap-timeout --agent claude --mode autopilot --kind dev 2>&1)"; [ $? -ne 0 ] || fail "workspace create 沒回 id 要失敗：$out"
case "$out" in *"workspace create 沒回 workspace id"*) ;; *) fail "要在 workspace create 這步失敗：$out" ;; esac
assert_not_grep '^tab create' "$OPSX_FAKE_LOG"
assert_not_grep '^"scam-guard"' "$OPSX_STATE_DIR/workspaces.toml"
: > "$OPSX_FAKE_LOG"
# workspace 建好但 agent 起不來：toml 已記，重派走 --workspace-label，不再多開一個同名 workspace
out="$(OPSX_TEST_START_FAIL=nope opsx dispatch rdap-timeout --agent claude --mode autopilot --kind dev 2>&1)"; [ $? -ne 0 ] || fail "agent start 失敗要失敗：$out"
assert_grep '^workspace create --label scam-guard' "$OPSX_FAKE_LOG"
assert_grep '^"scam-guard" = "scam-guard"$' "$OPSX_STATE_DIR/workspaces.toml"
cp "$FX/ws.real" "$OPSX_STATE_DIR/workspaces.toml"   # 下面再測一次沒掛 workspace 的成功派工
: > "$OPSX_FAKE_LOG"
printf '[repos."scam-guard"]\nmr = true\n' >> "$OPSX_STATE_DIR/grants.toml"
opsx dispatch rdap-timeout --agent claude --mode autopilot --kind dev >/dev/null 2>&1 || fail "dispatch unmapped repo"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];miss=[x for x in ["Bash(glab mr create:*)","Bash(glab mr note create:*)","Bash(glab mr note list:*)","Bash(gh pr create:*)","Bash(glab issue note:*)","Bash(glab issue comment:*)","Bash(gh issue comment:*)"] if x not in a];assert not miss,miss' "$OPSX_STATE_DIR/settings/scam-guard-rdap-timeout-autopilot.json" || fail "mr 授權的 allow 要含 issue 留言"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];assert not any("gh pr comment" in x or "glab api" in x for x in a),a;assert "Bash(git -C:*)" not in a,a' "$OPSX_STATE_DIR/settings/scam-guard-rdap-timeout-autopilot.json" || fail "mr 授權的 allow 不含任何 gh pr comment、glab api 規則與 git -C"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];n=[x for x in a if x.startswith("Bash(glab mr note")];assert n==["Bash(glab mr note create:*)","Bash(glab mr note list:*)"],n' "$OPSX_STATE_DIR/settings/scam-guard-rdap-timeout-autopilot.json" || fail "mr 授權的 glab mr note 只放行 create 與 list，不放行裸的 note、delete、update"
assert_grep '^workspace create --label scam-guard' "$OPSX_FAKE_LOG"
assert_grep '^"scam-guard" = "scam-guard"$' "$OPSX_STATE_DIR/workspaces.toml"   # 記 label，id 在 dispatch.json
assert_grep '^tab create --workspace w9 ' "$OPSX_FAKE_LOG"
assert_grep '^agent start rdap-timeout --kind claude --pane w1:pE -- --model claude-opus-5-5 ' "$OPSX_FAKE_LOG"   # dev → opus
# --- workspaces.toml 寫了 herdr 沒有的 label → 明講，不猜 ---
R3="$(mk_repo rag-demo)"; mkdir -p "$R3/openspec/changes/z"; printf 'schema: opsx\n' > "$R3/openspec/changes/z/.openspec.yaml"
printf '"rag-demo" = "develop"\n' >> "$OPSX_STATE_DIR/workspaces.toml"
out="$(cd "$R3" && opsx dispatch z --agent claude --mode autopilot --kind dev 2>&1)"; [ $? -ne 0 ] || fail "沒有的 workspace 要失敗"
echo "$out" | grep -q 'develop' && echo "$out" | grep -q 'acmecorp-ai' || fail "要列出現有 label: $out"
assert_grep '^agent prompt rdap-timeout /opsx-workflow:explore rdap-timeout$' "$OPSX_FAKE_LOG"                       # 沒 explore.md → explore

# --- workplan 有 branch 就用它 ---
R3="$(mk_repo Acmecorp-AI)"; mkdir -p "$R3/openspec/changes/eval-core"; printf 'schema: opsx\nkind: dev\n' > "$R3/openspec/changes/eval-core/.openspec.yaml"
printf 'features:\n  - name: eval\n    prs:\n      - name: eval-core\n        branch: feat/eval-core-v2/mikaela\n        status: pending\n' > "$R3/openspec/workplan.yaml"
printf '"Acmecorp-AI" = "w1"\n' >> "$OPSX_STATE_DIR/workspaces.toml"
cp "$R3/openspec/workplan.yaml" "$FX/wp3.before"
cd "$R3"; opsx dispatch eval-core --agent claude --mode drive >/dev/null 2>&1 || fail "dispatch with workplan"
wait_drive Acmecorp-AI eval-core   # --mode drive 是 autopilot 的別名：照樣起 drive，dispatch.json 寫 autopilot
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["Acmecorp-AI/eval-core"];assert d["mode"]=="autopilot",d' "$OPSX_STATE_DIR/dispatch.json" || fail "--mode drive 要寫成 autopilot"
assert_eq "$(git -C "$R3/.claude/worktrees/eval-core" rev-parse --abbrev-ref HEAD)" "feat/eval-core-v2/mikaela" "workplan branch"
cmp -s "$FX/wp3.before" "$R3/openspec/workplan.yaml" || fail "已在 workplan 的卡派工不動 workplan：$(diff "$FX/wp3.before" "$R3/openspec/workplan.yaml")"

# --- 不在 workplan 的卡派工前先掛進去，branch 用 workplan 上那個 PR 的（specs/workplan-attach「派工時補掛」）---
mkdir -p "$R3/openspec/changes/x"; printf 'schema: opsx\nkind: bug-fix\n' > "$R3/openspec/changes/x/.openspec.yaml"
printf -- '---\ntype: bug\nsource: me\nkind_of_work: planned\n---\n\n## 一句話\n\nx\n' > "$R3/openspec/changes/x/inbox.md"
out="$(OPSX_USER=mika opsx dispatch x --agent claude --mode autopilot 2>&1)" || fail "dispatch 不在 workplan 的卡: $out"
python3 -I - "$OPSX_ROOT/bin/lib" "$R3/openspec/workplan.yaml" <<'PY' || fail "x 要自成 feature、PR branch 是 fix/x/mika：$(cat "$R3/openspec/workplan.yaml")"
import sys
sys.path.insert(0, sys.argv[1]); import chain
f = [x for x in chain.load_workplan(sys.argv[2])["features"] if x["name"] == "x"][0]
assert [(p["name"], p["branch"]) for p in f["prs"]] == [("x", "fix/x/mika")], f
PY
assert_eq "$(git -C "$R3/.claude/worktrees/x" rev-parse --abbrev-ref HEAD)" "fix/x/mika" "worktree 用 workplan 上的 branch"
assert_grep '^priority: P2$' "$R3/openspec/changes/x/inbox.md"
opsx stop x >/dev/null 2>&1
# 前綴照 kind（workplan-attach D8）：type 是 bug、kind 是 chore 的卡，workplan 與 worktree 都是 chore/
mkdir -p "$R3/openspec/changes/xc"; printf 'schema: opsx\nkind: dev\n' > "$R3/openspec/changes/xc/.openspec.yaml"
printf -- '---\ntype: bug\nsource: me\nkind_of_work: planned\n---\n' > "$R3/openspec/changes/xc/inbox.md"
out="$(OPSX_USER=mika opsx dispatch xc --kind chore --agent claude --mode autopilot 2>&1)" || fail "dispatch kind chore: $out"
assert_eq "$(git -C "$R3/.claude/worktrees/xc" rev-parse --abbrev-ref HEAD)" "chore/xc/mika" "kind chore 的前綴是 chore"
grep -q 'branch: "chore/xc/mika"' "$R3/openspec/workplan.yaml" || fail "workplan 的 branch 要是 chore/xc/mika：$(cat "$R3/openspec/workplan.yaml")"
opsx stop xc >/dev/null 2>&1
# 建卡時已掛進 workplan（還沒有 kind，照 type 寫 feat/）：派工的 kind 是 refactoring、branch 還沒建，就改成 refactor/（workplan-attach D14）
mkdir -p "$R3/openspec/changes/xr"; printf 'schema: opsx\n' > "$R3/openspec/changes/xr/.openspec.yaml"
printf -- '---\ntype: 功能\nsource: me\nkind_of_work: planned\n---\n' > "$R3/openspec/changes/xr/inbox.md"
python3 -I "$OPSX_ROOT/bin/lib/workplanwrite.py" attach "$R3" xr "" mika "" || fail "建卡時的掛入"
grep -q 'branch: "feat/xr/mika"' "$R3/openspec/workplan.yaml" || fail "建卡時照 type 是 feat/xr/mika：$(cat "$R3/openspec/workplan.yaml")"
out="$(OPSX_USER=mika opsx dispatch xr --kind refactoring --agent claude --mode autopilot 2>&1)" || fail "dispatch kind refactoring: $out"
assert_eq "$(git -C "$R3/.claude/worktrees/xr" rev-parse --abbrev-ref HEAD)" "refactor/xr/mika" "已掛的卡照 kind 改前綴"
grep -q 'branch: "refactor/xr/mika"' "$R3/openspec/workplan.yaml" || fail "workplan 的 branch 要改成 refactor/xr/mika：$(cat "$R3/openspec/workplan.yaml")"
opsx stop xr >/dev/null 2>&1
# branch 已經建出來就不改
mkdir -p "$R3/openspec/changes/xe"; printf 'schema: opsx\n' > "$R3/openspec/changes/xe/.openspec.yaml"
printf -- '---\ntype: bug\nsource: me\nkind_of_work: planned\n---\n' > "$R3/openspec/changes/xe/inbox.md"
python3 -I "$OPSX_ROOT/bin/lib/workplanwrite.py" attach "$R3" xe "" mika "" || fail "建卡時的掛入 xe"
git -C "$R3" branch fix/xe/mika || fail "先建 branch"
cp "$R3/openspec/workplan.yaml" "$FX/wp3.xe"
out="$(OPSX_USER=mika opsx dispatch xe --kind chore --agent claude --mode autopilot 2>&1)" || fail "dispatch xe: $out"
assert_eq "$(git -C "$R3/.claude/worktrees/xe" rev-parse --abbrev-ref HEAD)" "fix/xe/mika" "branch 已建出來就沿用"
cmp -s "$FX/wp3.xe" "$R3/openspec/workplan.yaml" || fail "branch 已建出來時 workplan 不動：$(diff "$FX/wp3.xe" "$R3/openspec/workplan.yaml")"
opsx stop xe >/dev/null 2>&1

# --- 補掛失敗只警告、照 kind 預設 branch 派（workplan-attach D11）：沒有 inbox frontmatter、milestone 欄位壞掉 ---
mkdir -p "$R3/openspec/changes/nofm"; printf 'schema: opsx\nkind: refactoring\n' > "$R3/openspec/changes/nofm/.openspec.yaml"
out="$(OPSX_USER=mika opsx dispatch nofm --agent claude --mode autopilot 2>&1)" || fail "沒有 frontmatter 的卡要派得出去: $out"
case "$out" in *沒掛進\ workplan*) ;; *) fail "要警告沒掛進 workplan：$out" ;; esac
assert_eq "$(git -C "$R3/.claude/worktrees/nofm" rev-parse --abbrev-ref HEAD)" "refactor/nofm/mika" "掛不進去時用 kind 的預設前綴"
opsx stop nofm >/dev/null 2>&1
cp "$R3/openspec/workplan.yaml" "$FX/wp3.keep"
printf 'current_milestone: "9"\n' >> "$R3/openspec/workplan.yaml"
mkdir -p "$R3/openspec/changes/badms"; printf 'schema: opsx\nkind: dev\n' > "$R3/openspec/changes/badms/.openspec.yaml"
printf -- '---\ntype: 功能\nsource: me\nkind_of_work: planned\n---\n' > "$R3/openspec/changes/badms/inbox.md"
out="$(OPSX_USER=mika opsx dispatch badms --agent claude --mode autopilot 2>&1)" || fail "milestone 欄位壞掉時要派得出去: $out"
case "$out" in *沒掛進\ workplan*) ;; *) fail "要警告沒掛進 workplan：$out" ;; esac
assert_eq "$(git -C "$R3/.claude/worktrees/badms" rev-parse --abbrev-ref HEAD)" "feat/badms/mika"
opsx stop badms >/dev/null 2>&1
cp "$FX/wp3.keep" "$R3/openspec/workplan.yaml"

# --- 分支尾巴：OPSX_USER 沒設就用 git user.name；是 git 的占位字「Your Name」或空的就拒絕，不開 worktree 不碰 herdr ---
# 這段測沒有 workplan 時 dispatch 自己取的 branch：先把 R3 的 workplan 移開，段尾放回
mv "$R3/openspec/workplan.yaml" "$FX/wp3.aside"
mkdir -p "$R3/openspec/changes/noname-card"; printf 'schema: opsx\nkind: dev\n' > "$R3/openspec/changes/noname-card/.openspec.yaml"
: > "$OPSX_FAKE_LOG"
out="$(OPSX_USER= opsx dispatch noname-card --agent claude --mode autopilot 2>&1)" || fail "git user.name t should name the branch: $out"
assert_eq "$(git -C "$R3/.claude/worktrees/noname-card" rev-parse --abbrev-ref HEAD)" "feat/noname-card/t" "branch from git user.name"
opsx stop noname-card >/dev/null 2>&1; rm -rf "$R3/.claude/worktrees/noname-card"; git -C "$R3" worktree prune; git -C "$R3" branch -D feat/noname-card/t >/dev/null 2>&1
git -C "$R3" config user.name "Your Name"; : > "$OPSX_FAKE_LOG"
out="$(OPSX_USER= opsx dispatch noname-card --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "placeholder name must be refused: $out"
echo "$out" | grep -q 'OPSX_USER' && echo "$out" | grep -q 'Your Name' || fail "要說怎麼設名字: $out"
[ ! -d "$R3/.claude/worktrees/noname-card" ] || fail "refused dispatch must not open a worktree"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "refused dispatch must not touch herdr"
# 有 workplan 時，名字是占位字的卡掛不進 workplan，一樣拒絕
mv "$FX/wp3.aside" "$R3/openspec/workplan.yaml"
printf -- '---\ntype: 功能\nsource: me\n---\n' > "$R3/openspec/changes/noname-card/inbox.md"
out="$(OPSX_USER= opsx dispatch noname-card --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "placeholder name must be refused with a workplan: $out"
echo "$out" | grep -q 'OPSX_USER' && echo "$out" | grep -q 'Your Name' || fail "要說怎麼設名字: $out"
[ ! -d "$R3/.claude/worktrees/noname-card" ] || fail "refused dispatch must not open a worktree"
git -C "$R3" config user.name t

# --- 新分支從 fetch 後的 origin/main 開，不從主 checkout 當下的 HEAD（主 checkout 在 feat/x、origin/main 比本機新） ---
B="$FX/upstream.git"; git init -q --bare -b main "$B"
R5="$(mk_repo dep-card "$B")"; git -C "$R5" branch -M main; git -C "$R5" push -q origin main
git -C "$R5" fetch -q origin
git clone -q "$B" "$FX/other"; git -C "$FX/other" -c user.email=t@t -c user.name=t commit -q --allow-empty -m merged-dep; git -C "$FX/other" push -q origin main
up="$(git -C "$FX/other" rev-parse HEAD)"
git -C "$R5" switch -q -c feat/x; git -C "$R5" -c user.email=t@t -c user.name=t commit -q --allow-empty -m wip
mkdir -p "$R5/openspec/changes/dep-card"; printf 'schema: opsx\nkind: dev\n' > "$R5/openspec/changes/dep-card/.openspec.yaml"
printf '"dep-card" = "w1"\n' >> "$OPSX_STATE_DIR/workspaces.toml"
out="$(cd "$R5" && opsx dispatch dep-card --agent claude --mode autopilot 2>&1)" || fail "dispatch dep-card: $out"
assert_eq "$(git -C "$R5/.claude/worktrees/dep-card" rev-parse HEAD)" "$up" "新分支要長在 fetch 後的 origin/main"

# --- stop ---
: > "$OPSX_FAKE_LOG"; cd "$R"
opsx stop retry-backoff >/dev/null 2>&1 || fail "stop"
assert_grep '^pane close w1:pE$' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert d["mode"]=="stopped" and d["stopped_at"],d' "$OPSX_STATE_DIR/dispatch.json"
assert_eq "$(last_row)" "你$(printf '\t')已停止"
assert_rc 2 opsx stop nope

# --- 停下的代管卡重派（auto-dispatch 4.2）：整筆改寫，不再帶 via / herdr_name ---
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));e=d["Acmecorp-CS/retry-backoff"];e.update(mode="stopped",via="p",herdr_name="p");json.dump(d,open(p,"w"))' "$OPSX_STATE_DIR/dispatch.json"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch retry-backoff --agent claude --mode autopilot 2>&1)" || fail "redispatch 代管卡: $out"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert "via" not in e and "herdr_name" not in e and e["mode"]=="autopilot",e' "$OPSX_STATE_DIR/dispatch.json" || fail "重派要整筆改寫"
assert_grep '^agent start retry-backoff ' "$OPSX_FAKE_LOG"

# --- herdr 名不撞（auto-dispatch 4.3）：還在跑的代管卡的 herdr_name 是 coord，就不准再派一張叫 coord 的卡 ---
mkdir -p "$R/openspec/changes/coord"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/coord/.openspec.yaml"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Other-Repo/kid"]={"mode":"autopilot","pane":"w9:p1","via":"coord","herdr_name":"coord"};json.dump(d,open(p,"w"))' "$OPSX_STATE_DIR/dispatch.json"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch coord --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "slug 撞到 herdr_name 要拒絕: $out"
echo "$out" | grep -q 'Other-Repo/kid' || fail "要說撞到哪一筆: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"

# --- 已交接的條目不算撞名（auto-dispatch 6.1）：續接後父卡那筆留著 herdr_name，子卡停掉後要能重派 ---
mkdir -p "$R/openspec/changes/coord2"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/coord2/.openspec.yaml"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Other-Repo/old"]={"mode":"autopilot","pane":"w9:p2","herdr_name":"coord2","handed_to":["coord2"]};json.dump(d,open(p,"w"))' "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx dispatch coord2 --agent claude --mode autopilot 2>&1)" || fail "已交接的條目不該擋重派: $out"

# --- fan-out 的父卡（auto-dispatch 6.7）：handed_to 列了子卡，但 pane 還活著、herdr 名還是父卡，同名的卡照樣不准派 ---
mkdir -p "$R/openspec/changes/coord3"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/coord3/.openspec.yaml"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Other-Repo/coord3"]={"mode":"autopilot","pane":"w9:p3","handed_to":["k1","k2"]};json.dump(d,open(p,"w"))' "$OPSX_STATE_DIR/dispatch.json"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch coord3 --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "fan-out 父卡的 pane 還活著，同名要拒絕: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"

# --- feature session：一個 pane、每個可做的主 change 一筆 ---
RF="$(mk_repo Feat-Repo)"; mkdir -p "$OPSX_STATE_DIR"
cat > "$RF/openspec-wp.yaml" <<'EOF'
features:
  - name: fs
    depends-on: []
    prs:
      - name: m1
        branch: feat/m1/mikaela
        status: pending
        depends-on: []
        changes:
          - name: a1
            status: pending
      - name: m2
        branch: feat/m2/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m2
            status: pending
      - name: m3
        branch: feat/m3/mikaela
        status: pending
        depends-on: [m1]
        changes:
          - name: m3
            status: pending
      - name: m4
        branch: feat/m4/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m4
            status: pending
EOF
mkdir -p "$RF/openspec"; mv "$RF/openspec-wp.yaml" "$RF/openspec/workplan.yaml"
for s in m1 m2 m3 m4; do mkdir -p "$RF/openspec/changes/$s"; printf 'schema: opsx\nkind: dev\n' > "$RF/openspec/changes/$s/.openspec.yaml"; printf -- '- [ ] 1.1 x\n' > "$RF/openspec/changes/$s/tasks.md"; done
# m4 是 P2：沒依賴、有 tasks.md，但 session 不接它（session-dispatch「P2 的主 change 不寫」）
printf -- '---\ntype: 功能\nsource: me\npriority: P2\npriority_reason: 自動掛進 workplan，維持 P2\n---\n' > "$RF/openspec/changes/m4/inbox.md"
cd "$RF"; printf '{}' > "$OPSX_STATE_DIR/dispatch.json"; : > "$OPSX_FAKE_LOG"

# 沒有這個 feature：拒絕，不開 pane
out="$(opsx dispatch --feature nope --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "沒有的 feature 要拒絕: $out"
echo "$out" | grep -q nope || fail "訊息要說 nope: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "沒有的 feature 不碰 herdr"
assert_eq "$(jq -r 'has("Feat-Repo/@nope") | tostring' "$OPSX_STATE_DIR/dispatch.json")" false "沒有的 feature 不寫 session 條目"
assert_rc 2 opsx dispatch --feature "Bad Name" --agent claude
assert_rc 2 opsx dispatch m1 --feature fs --agent claude

# 派 fs：m1、m2 沒依賴，m3 等 m1，不寫
out="$(opsx dispatch --feature fs --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "feature dispatch: $out"
assert_eq "$(grep -c '^agent start' "$OPSX_FAKE_LOG")" 1 "一個 feature 只開一個 agent"
assert_grep '^agent start fs --kind claude ' "$OPSX_FAKE_LOG"
assert_grep '^tab create .* --label fs' "$OPSX_FAKE_LOG"
assert_grep '^agent prompt fs /opsx-workflow:apply m1$' "$OPSX_FAKE_LOG"
J="$OPSX_STATE_DIR/dispatch.json"
assert_eq "$(jq -r '."Feat-Repo/@fs" | [.workspace, .workspace_id, .tab, .pane, .worktree, .agent, .mode, (.drive_pid | tostring), (.started_at | length > 0 | tostring), (.model | length > 0 | tostring)] | join(" ")' "$J")" \
  "Feat-Repo w9 w1:tB w1:pE $RF/.claude/worktrees/fs claude autopilot null true true" "session 條目"
assert_eq "$(jq -r '."Feat-Repo/@fs" | has("branch") or has("kind") or has("via") or has("feature") or has("herdr_name") | tostring' "$J")" false "session 條目不帶卡的欄位"
assert_eq "$(jq -r '."Feat-Repo/m1" | [.herdr_name, .via, .feature, .pane, .branch] | join(" ")' "$J")" "fs @fs fs w1:pE feat/m1/mikaela" "m1 的條目"
assert_eq "$(jq -r '."Feat-Repo/m2" | [.herdr_name, .via, .feature, .pane, .branch] | join(" ")' "$J")" "fs @fs fs w1:pE feat/m2/mikaela" "m2 跟 m1 共用 pane"
assert_eq "$(jq -r 'keys | map(select(startswith("Feat-Repo/"))) | join(" ")' "$J")" "Feat-Repo/@fs Feat-Repo/m1 Feat-Repo/m2" "session 加兩個成員共三筆"
assert_eq "$(jq -r '."Feat-Repo/m3" // "none"' "$J")" none "依賴沒滿足的主 change 不寫"
assert_eq "$(jq -r '."Feat-Repo/m4" // "none"' "$J")" none "P2 的主 change 不寫"
assert_eq "$(git -C "$RF/.claude/worktrees/fs" rev-parse --abbrev-ref HEAD)" "feat/m1/mikaela" "worktree 叫 feature 名，從第一個主 change 的 branch 開"
assert_grep '已指派' "$RF/openspec/changes/m2/decisions.tsv"

# 再派一次：session 還在，拒絕
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch --feature fs --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "session 還在要拒絕: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"

# 人停 m2：只送 [m2] stop 給 session，不關 pane
out="$(opsx stop m2 2>&1)" || fail "stop m2: $out"
assert_grep '^agent prompt fs \[m2\] stop$' "$OPSX_FAKE_LOG"
assert_not_grep '^pane close' "$OPSX_FAKE_LOG"
# 成員都停了、session 條目還活著：再派 --feature 要拒絕（不然 herdr agent start fs 撞 agent_name_taken）
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Feat-Repo/m1"]["mode"]="stopped";json.dump(d,open(p,"w"))' "$J"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch --feature fs --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "成員都停了但 session 還在，要拒絕: $out"
echo "$out" | grep -q '@fs' || fail "訊息要指出 @fs: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Feat-Repo/m1"]["mode"]="autopilot";json.dump(d,open(p,"w"))' "$J"

# 重派人停的成員卡、session 還活著：清掉 stopped、送 [m2] /apply m2 給 session，不開 pane
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch m2 --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "session 活著重派 m2: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "agent prompt fs [m2] /opsx-workflow:apply m2
agent read w1:pE --source visible --format ansi" "只送一句給 session，送出後讀一次輸入框"
assert_eq "$(jq -r '."Feat-Repo/m2" | [.mode, .pane, .via, .herdr_name, (has("stopped_at") | tostring)] | join(" ")' "$J")" "autopilot w1:pE @fs fs false" "m2 不再是 stopped，pane 取自 session"

# opsx stop @fs：關 session pane、標 session 條目 stopped，成員條目不動
jq -S '{m1: ."Feat-Repo/m1", m2: ."Feat-Repo/m2"}' "$J" > "$FX/members-before.json"
: > "$OPSX_FAKE_LOG"
out="$(opsx stop @fs 2>&1)" || fail "stop @fs: $out"
assert_grep '^pane close w1:pE' "$OPSX_FAKE_LOG"
assert_not_grep '^agent prompt' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."Feat-Repo/@fs".mode' "$J")" stopped "session 條目標 stopped"
assert_eq "$(jq -S '{m1: ."Feat-Repo/m1", m2: ."Feat-Repo/m2"}' "$J")" "$(cat "$FX/members-before.json")" "stop @fs 不碰成員條目"
assert_not_grep 'Feat-Repo/@fs.*已歸檔' "$OPSX_STATE_DIR/reap.log"

# 人停的成員卡不被撿回（C-human-stop）：m1 人停了，session 重派 --feature 不寫 m1、第一句不是 m1
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Feat-Repo/m1"]["mode"]="stopped";json.dump(d,open(p,"w"))' "$J"
sed -i.bak 's/^"Feat-Repo" = .*/"Feat-Repo" = "acmecorp-ai"/' "$OPSX_STATE_DIR/workspaces.toml"   # 第一次派新建的 workspace 不在假 herdr 的 workspace list 裡
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch --feature fs --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "session 重派: $out"
assert_eq "$(jq -r '."Feat-Repo/m1".mode' "$J")" stopped "人停的 m1 仍是 stopped"
assert_grep '^agent prompt fs /opsx-workflow:apply m2$' "$OPSX_FAKE_LOG"
assert_not_grep '^agent prompt fs /.* m1$' "$OPSX_FAKE_LOG"

# 重派人停的成員卡、session 不在：照單卡派（m2 的 branch 沒被 session 的 worktree checkout）
out="$(opsx stop m2 2>&1)" || fail "stop m2: $out"
out="$(opsx stop @fs 2>&1)" || fail "stop @fs: $out"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch m2 --agent claude --mode interactive 2>&1)"; assert_eq "$?" 0 "session 不在重派 m2: $out"
assert_grep '^agent start m2 ' "$OPSX_FAKE_LOG"
assert_not_grep '^agent prompt fs' "$OPSX_FAKE_LOG"

# 單卡派過再停掉的條目（沒有 via）不是這個 session 的成員：--feature 照常寫它、可以給它第一句
out="$(opsx stop m2 2>&1)" || fail "stop m2: $out"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch --feature fs --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "單卡留下的 stopped 不算人停的成員: $out"
assert_grep '^agent prompt fs /opsx-workflow:apply m2$' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."Feat-Repo/m2" | [.mode, .via] | join(" ")' "$J")" "autopilot @fs" "m2 寫成 session 成員"
assert_eq "$(jq -r '."Feat-Repo/m1".mode' "$J")" stopped "via @fs 的人停成員照樣跳過"

# 等合併的成員（不在 plan 裡、沒停）在 session 重派後 pane 改抄新 session，collect 不會拿舊 pane 判它 agent 不在
python3 -I -c 'import sys;p=sys.argv[1];t=open(p).read().replace("name: a1\n            status: pending","name: a1\n            status: done");open(p,"w").write(t)' "$RF/openspec/workplan.yaml"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Feat-Repo/m1"].update(mode="autopilot",pane="w1:pOLD");json.dump(d,open(p,"w"))' "$J"
out="$(opsx stop @fs 2>&1)" || fail "stop @fs: $out"
out="$(opsx dispatch --feature fs --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "重派: $out"
assert_eq "$(jq -r '[."Feat-Repo/m1".pane, ."Feat-Repo/m1".mode] | join(" ")' "$J")" "$(jq -r '."Feat-Repo/@fs".pane' "$J") autopilot" "等合併的 m1 的 pane 等於新 session"
python3 -I -c 'import sys;p=sys.argv[1];t=open(p).read().replace("name: a1\n            status: done","name: a1\n            status: pending");open(p,"w").write(t)' "$RF/openspec/workplan.yaml"

# 重派途中人按停止（判斷之後、寫入之前）：寫入時再查一次，人停的 m1 不被蓋回，第一句改給 m2
out="$(opsx stop @fs 2>&1)" || fail "stop @fs: $out"
printf '%s\n' "python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d[\"Feat-Repo/m1\"][\"mode\"]=\"stopped\";json.dump(d,open(p,\"w\"))' \"$J\"" > "$FX/stop-m1-on-wait.sh"
export OPSX_TEST_NOT_READY_ONCE="$FX/not-ready-once"; : > "$OPSX_TEST_NOT_READY_ONCE"
export OPSX_TEST_PANE_TEXT='Yes, I trust this folder'
export OPSX_TEST_ON_WAIT="$FX/stop-m1-on-wait.sh"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch --feature fs --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "重派途中有人停: $out"
unset OPSX_TEST_NOT_READY_ONCE OPSX_TEST_PANE_TEXT OPSX_TEST_ON_WAIT
assert_eq "$(jq -r '."Feat-Repo/m1".mode' "$J")" stopped "途中人停的 m1 不被蓋回"
assert_grep '^agent prompt fs /opsx-workflow:apply m2$' "$OPSX_FAKE_LOG"
assert_not_grep '^agent prompt fs /.* m1$' "$OPSX_FAKE_LOG"

# session 條目被 reap 收掉（mode 還是 autopilot、有 reaped_at）：當作 session 不在，人停的成員照單卡派
out="$(opsx stop m2 2>&1)" || fail "stop m2: $out"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Feat-Repo/@fs"]["reaped_at"]="2026-11-10T16:00:00+08:00";json.dump(d,open(p,"w"))' "$J"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch m2 --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "session 被 reap 後重派 m2: $out"
assert_grep '^agent start m2 ' "$OPSX_FAKE_LOG"
assert_not_grep '^agent prompt fs' "$OPSX_FAKE_LOG"

# 交回 session 時卡的 stage 不在可送的那幾站（例如已拆）：拒絕並寫出 stage，不改送 /explore
out="$(opsx stop m2 2>&1)" || fail "stop m2: $out"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));s=d["Feat-Repo/@fs"];s.pop("reaped_at");s["mode"]="autopilot";m=d["Feat-Repo/m2"];m.update(feature="fs",via="@fs",herdr_name="fs");json.dump(d,open(p,"w"))' "$J"
printf -- '---\nsplit_into: m2a\n---\n' > "$RF/openspec/changes/m2/inbox.md"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch m2 --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "stage split 不能交回 session: $out"
echo "$out" | grep -q split || fail "訊息要寫出 stage: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"
rm "$RF/openspec/changes/m2/inbox.md"

# --feature --only：只寫列出的卡，第一句照列出的順序給第一張；列了不能開工的卡就拒絕
cp "$J" "$FX/j-before-only.json"
printf '{}' > "$J"; : > "$OPSX_FAKE_LOG"
out="$(opsx dispatch --feature fs --only m2 --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "--only m2: $out"
assert_grep '^agent prompt fs /opsx-workflow:apply m2$' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r 'keys | join(" ")' "$J")" "Feat-Repo/@fs Feat-Repo/m2" "只寫 session 與 m2"
printf '{}' > "$J"; : > "$OPSX_FAKE_LOG"
out="$(opsx dispatch --feature fs --only m2,m1 --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "--only m2,m1: $out"
assert_grep '^agent prompt fs /opsx-workflow:apply m2$' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r 'keys | join(" ")' "$J")" "Feat-Repo/@fs Feat-Repo/m1 Feat-Repo/m2" "m1、m2 都寫"
printf '{}' > "$J"; : > "$OPSX_FAKE_LOG"
out="$(opsx dispatch --feature fs --only m3 --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "--only 列了不能開工的卡要拒絕: $out"
echo "$out" | grep -q m3 || fail "訊息要說 m3: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"
assert_rc 2 opsx dispatch m2 --only m2 --agent claude
cp "$FX/j-before-only.json" "$J"

# --- dispatch --note：送第一句之前寫進 inbox.md 的 ## 派工指示（specs/dispatch-note「opsx dispatch --note 在第一句之前寫入」） ---
cd "$R"
N="$R/openspec/changes/note-card"; mkdir -p "$N"; printf 'schema: opsx\nkind: dev\n' > "$N/.openspec.yaml"
printf -- '---\ntype: 功能\n---\n\n## 一句話\n\nx\n' > "$N/inbox.md"
cp "$N/inbox.md" "$FX/note-before.md"; : > "$OPSX_FAKE_LOG"
out="$(opsx dispatch note-card --agent claude --mode interactive --note "  " 2>&1)"; [ $? -ne 0 ] || fail "空白 --note 要拒絕: $out"
[ ! -d "$R/.claude/worktrees/note-card" ] || fail "空白 --note 不該開 worktree"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "空白 --note 不碰 herdr"
cmp -s "$N/inbox.md" "$FX/note-before.md" || fail "空白 --note 不該動 inbox.md"
printf 'cp "%s" "%s"\n' "$N/inbox.md" "$FX/note-at-prompt.md" > "$FX/snap-prompt.sh"
out="$(OPSX_TEST_ON_PROMPT="$FX/snap-prompt.sh" opsx dispatch note-card --agent claude --mode interactive --note "先跑 lint" 2>&1)" || fail "dispatch --note: $out"
assert_grep '^agent prompt note-card /opsx-workflow:explore note-card$' "$OPSX_FAKE_LOG"
assert_file "$FX/note-at-prompt.md"
awk '/^## 派工指示[[:space:]]*$/{f=1;next} /^## /{f=0} f && /^- /' "$FX/note-at-prompt.md" | grep -qE '^- 20[0-9-]+T[0-9:]+[+-][0-9:]+ 先跑 lint$' || fail "第一句送出時要已寫入：$(cat "$FX/note-at-prompt.md")"
cp "$N/inbox.md" "$FX/note-before.md"
out="$(opsx dispatch note-card --agent claude --mode interactive --note "第二條" 2>&1)"; [ $? -ne 0 ] || fail "還在跑的卡重派要拒絕: $out"
cmp -s "$N/inbox.md" "$FX/note-before.md" || fail "重派被拒時不該寫指示"
opsx stop note-card >/dev/null 2>&1 || fail "stop note-card"
opsx dispatch note-card --agent claude --mode interactive >/dev/null 2>&1 || fail "不帶 --note 重派"
cmp -s "$N/inbox.md" "$FX/note-before.md" || fail "不帶 --note 不該動 inbox.md"
opsx --help 2>&1 | grep -q '^  dispatch .*--note' || fail "opsx --help 的 dispatch 行要列 --note"

# --- 分支被別的 worktree 佔著（held-branch-guard/worktree-held-check）：不 worktree add、不開 tab、不寫條目，說出佔著的 worktree 與 pane ---
cd "$R"
mkdir -p "$R/openspec/changes/held"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/held/.openspec.yaml"
git -C "$R" worktree add -q "$R/.claude/worktrees/c" -b feat/held/mikaela
# 條目記的路徑不是 realpath（$FX 底下的 symlink），比對前要兩邊都 resolve
ln -s "$R" "$FX/R-link"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Acmecorp-CS/c"]={"mode":"autopilot","pane":"p1","worktree":sys.argv[2]};json.dump(d,open(p,"w"))' "$OPSX_STATE_DIR/dispatch.json" "$FX/R-link/.claude/worktrees/c"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch held --agent claude --mode autopilot 2>&1)"; [ $? -ne 0 ] || fail "分支被佔要失敗: $out"
echo "$out" | grep -qF '.claude/worktrees/c' || fail "要說佔著的 worktree: $out"
echo "$out" | grep -qF 'Acmecorp-CS/c' && echo "$out" | grep -qF 'p1' || fail "要說對到的條目與 pane: $out"
[ ! -d "$R/.claude/worktrees/held" ] || fail "被佔時不能開 worktree"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "被佔時不碰 herdr"
assert_eq "$(jq -r 'has("Acmecorp-CS/held") | tostring' "$OPSX_STATE_DIR/dispatch.json")" false "被佔時不寫條目"
# 對不到條目：照樣擋，只寫 worktree 路徑
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));del d["Acmecorp-CS/c"];json.dump(d,open(p,"w"))' "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx dispatch held --agent claude --mode autopilot 2>&1)"; [ $? -ne 0 ] || fail "分支被佔、沒條目也要失敗: $out"
echo "$out" | grep -qF '.claude/worktrees/c' || fail "要說佔著的 worktree: $out"
[ ! -d "$R/.claude/worktrees/held" ] || fail "被佔時不能開 worktree"
# --- 人手動派，名額已滿只警告（specs/dispatch-concurrency：人手動派名額已滿只警告）---
# cap_state <活著的 pane 數>：dispatch.json 加 8 個沒停的條目 cap1…cap8（worktree 是 $FX/capwt/capN），
# herdr 只回前 n 個的 agent（idle，cwd 在各自的 worktree 裡）
cap_state() {
  python3 -I - "$OPSX_STATE_DIR/dispatch.json" "$FX/cap-agents.json" "$1" "$FX/capwt" <<'PY'
import json, os, sys
path, agents_path, n, wtroot = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
d = json.load(open(path))
for i in range(1, 9):
    wt = os.path.join(wtroot, "cap%d" % i)
    os.makedirs(wt, exist_ok=True)
    d["Acmecorp-CS/cap%d" % i] = {"mode": "autopilot", "agent": "claude", "pane": "w9:cap%d" % i, "drive_pid": None, "worktree": wt}
json.dump(d, open(path, "w"))
agents = [{"agent": "claude", "agent_status": "idle", "pane_id": "w9:cap%d" % i, "cwd": os.path.join(wtroot, "cap%d" % i)} for i in range(1, n + 1)]
json.dump({"id": "cli:agent:list", "result": {"agents": agents, "type": "agent_list"}}, open(agents_path, "w"))
PY
}
cd "$R"
mkdir -p "$R/openspec/changes/cap-x" "$R/openspec/changes/cap-y" "$R/openspec/changes/cap-z"
printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/cap-x/.openspec.yaml"
printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/cap-y/.openspec.yaml"
printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/cap-z/.openspec.yaml"
cap_state 8
out="$(OPSX_TEST_HERDR_AGENTS="$FX/cap-agents.json" opsx dispatch cap-x --agent claude --mode interactive 2>&1)"; rc=$?
assert_eq "$rc" 0 "名額滿了手動派照派: $out"
echo "$out" | grep -qxF 'dispatch: 已有 8/8 個 pane' || fail "名額滿了要警告: $out"
assert_eq "$(jq -r 'has("Acmecorp-CS/cap-x") | tostring' "$OPSX_STATE_DIR/dispatch.json")" true "名額滿了照寫條目"
cap_state 7
out="$(OPSX_TEST_HERDR_AGENTS="$FX/cap-agents.json" opsx dispatch cap-y --agent claude --mode interactive 2>&1)"; rc=$?
assert_eq "$rc" 0 "名額沒滿照派: $out"
echo "$out" | grep -qF '已有' && fail "名額沒滿不警告: $out"
assert_eq "$(jq -r 'has("Acmecorp-CS/cap-y") | tostring' "$OPSX_STATE_DIR/dispatch.json")" true "名額沒滿照寫條目"
# herdr agent list 失敗：印一行數不出名額到 stdout（看板成功時只顯示 stdout），照派
cap_state 8
out="$(OPSX_TEST_HERDR_LIST_FAIL='socket refused' opsx dispatch cap-z --agent claude --mode interactive 2>/dev/null)"; rc=$?
assert_eq "$rc" 0 "數不出名額照派: $out"
echo "$out" | grep -qF '已有' && fail "數不出名額不印已有: $out"
echo "$out" | grep -qF 'dispatch: 數不出名額：herdr agent list 失敗' || fail "數不出名額要說: $out"
assert_eq "$(jq -r 'has("Acmecorp-CS/cap-z") | tostring' "$OPSX_STATE_DIR/dispatch.json")" true "數不出名額照寫條目"
# agent list 讀不懂：stdout 說原因，照派
mkdir -p "$R/openspec/changes/cap-w"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/cap-w/.openspec.yaml"
printf 'not json\n' > "$FX/cap-bad.json"
out="$(OPSX_TEST_HERDR_AGENTS="$FX/cap-bad.json" opsx dispatch cap-w --agent claude --mode interactive 2>/dev/null)"; rc=$?
assert_eq "$rc" 0 "agent list 讀不懂照派: $out"
echo "$out" | grep -qF 'herdr agent list 讀不懂' || fail "讀不懂要說原因: $out"
mkdir -p "$R/openspec/changes/cap-n"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/cap-n/.openspec.yaml"
printf '{"result":{"agents":null}}\n' > "$FX/cap-bad.json"
out="$(OPSX_TEST_HERDR_AGENTS="$FX/cap-bad.json" opsx dispatch cap-n --agent claude --mode interactive 2>/dev/null)"; rc=$?
assert_eq "$rc" 0 "agents 是 null 照派: $out"
echo "$out" | grep -F 'herdr agent list 讀不懂' | grep -qF 'None' || fail "agents 是 null 要說讀不懂與 None: $out"
# cap_add '<條目 JSON 物件>' '<agent JSON 陣列>'：dispatch.json 併進這些條目，cap_state 寫的 herdr agent list 加上這些 agent
cap_add() {
  python3 -I - "$OPSX_STATE_DIR/dispatch.json" "$FX/cap-agents.json" "$1" "$2" <<'PY'
import json, sys
path, agents_path = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d.update(json.loads(sys.argv[3]))
json.dump(d, open(path, "w"))
a = json.load(open(agents_path))
a["result"]["agents"] += json.loads(sys.argv[4])
json.dump(a, open(agents_path, "w"))
PY
}
# 名額沒滿：7 個單卡 pane，加一筆有 reaped_at 的條目與一筆 agent cwd 只在同前綴隔壁目錄的條目，兩個 pane 都有活 agent，都不佔名額
mkdir -p "$R/openspec/changes/cap-v" "$FX/capwt/rp" "$FX/capwt/ow"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/cap-v/.openspec.yaml"
cap_state 7
cap_add "{\"Acmecorp-CS/cap-rp\":{\"mode\":\"autopilot\",\"agent\":\"claude\",\"pane\":\"w9:rp\",\"drive_pid\":null,\"worktree\":\"$FX/capwt/rp\",\"reaped_at\":\"2026-11-17T09:00:00+08:00\"},\"Acmecorp-CS/cap-ow\":{\"mode\":\"autopilot\",\"agent\":\"claude\",\"pane\":\"w9:ow\",\"drive_pid\":null,\"worktree\":\"$FX/capwt/ow\"}}" \
  "[{\"agent\":\"claude\",\"agent_status\":\"working\",\"pane_id\":\"w9:rp\",\"cwd\":\"$FX/capwt/rp\",\"foreground_cwd\":\"$FX/capwt/rp\"},{\"agent\":\"claude\",\"agent_status\":\"working\",\"pane_id\":\"w9:ow\",\"cwd\":\"$FX/capwt/ow-other\",\"foreground_cwd\":\"$FX/capwt/ow-other\"}]"
out="$(OPSX_TEST_HERDR_AGENTS="$FX/cap-agents.json" opsx dispatch cap-v --agent claude --mode interactive 2>&1)"; rc=$?
assert_eq "$rc" 0 "opsx 關過的與 cwd 對不上的 pane 手動派照派: $out"
echo "$out" | grep -qF '已有' && fail "opsx 關過的與 cwd 對不上的 pane 不佔名額，不警告: $out"
# session pane 在手動派時佔名額：7 個單卡 pane，加 1 個成員全停、session 條目沒停、agent working 的 session pane
mkdir -p "$R/openspec/changes/cap-s" "$FX/capwt/sess"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/cap-s/.openspec.yaml"
cap_state 7
SW="$FX/capwt/sess"
cap_add "{\"Acmecorp-CS/@capf\":{\"mode\":\"autopilot\",\"agent\":\"claude\",\"pane\":\"w9:sess\",\"drive_pid\":null,\"worktree\":\"$SW\"},\"Acmecorp-CS/capm1\":{\"mode\":\"stopped\",\"agent\":\"claude\",\"pane\":\"w9:sess\",\"via\":\"@capf\",\"worktree\":\"$SW\"},\"Acmecorp-CS/capm2\":{\"mode\":\"stopped\",\"agent\":\"claude\",\"pane\":\"w9:sess\",\"via\":\"@capf\",\"worktree\":\"$SW\"}}" \
  "[{\"agent\":\"claude\",\"agent_status\":\"working\",\"pane_id\":\"w9:sess\",\"cwd\":\"$SW\",\"foreground_cwd\":\"$SW\"}]"
out="$(OPSX_TEST_HERDR_AGENTS="$FX/cap-agents.json" opsx dispatch cap-s --agent claude --mode interactive 2>&1)"; rc=$?
assert_eq "$rc" 0 "session pane 佔滿名額手動派照派: $out"
echo "$out" | grep -qxF 'dispatch: 已有 8/8 個 pane' || fail "成員全停的 session pane 要佔名額: $out"
# 協調者與手動派數到同一個數：上限 3；已歸檔、agent blocked 的卡，成員全停的 session 條目，一張活卡。協調者的 collect 只掃到另一個 repo 的 card-new
printf '3\n' > "$OPSX_STATE_DIR/max-working"
CC="$FX/cc"; mkdir -p "$CC/openspec/changes/card-new" "$R/openspec/changes/archive/2026-11-17-same-ar" "$FX/capwt/sa" "$FX/capwt/sf" "$FX/capwt/sl" "$FX/coordbin"
printf -- '- [ ] 1.1 x\n' > "$CC/openspec/changes/card-new/tasks.md"
printf 'created: 2026-11-07\n\nfeatures:\n  - name: cc\n    prs:\n      - name: card-new\n        status: pending\n        depends-on: []\n        changes:\n          - name: card-new\n            status: pending\n' > "$CC/openspec/workplan.yaml"
printf '{"repo_paths":{"cc":"%s"},"cards":[{"repo":"cc","slug":"card-new","kind":"dev","stage":"apply","section":"待指派","archived":false,"waiting":null,"open_gates":[],"dispatch":null,"agent_status":null,"mr":null,"path":"%s/openspec/changes/card-new"}],"errors":[]}' "$CC" "$CC" > "$FX/cc-collect.json"
printf '#!/usr/bin/env bash\nexec bash "%s/opsx" "$@"\n' "$FAKES" > "$FX/coordbin/opsx"; chmod +x "$FX/coordbin/opsx"
cap_state 0
cap_add "{\"Acmecorp-CS/same-ar\":{\"mode\":\"autopilot\",\"agent\":\"claude\",\"pane\":\"w9:sa\",\"drive_pid\":null,\"worktree\":\"$FX/capwt/sa\"},\"Acmecorp-CS/@samef\":{\"mode\":\"autopilot\",\"agent\":\"claude\",\"pane\":\"w9:sf\",\"drive_pid\":null,\"worktree\":\"$FX/capwt/sf\"},\"Acmecorp-CS/same-m1\":{\"mode\":\"stopped\",\"agent\":\"claude\",\"pane\":\"w9:sf\",\"via\":\"@samef\",\"worktree\":\"$FX/capwt/sf\"},\"Acmecorp-CS/same-live\":{\"mode\":\"autopilot\",\"agent\":\"claude\",\"pane\":\"w9:sl\",\"drive_pid\":null,\"worktree\":\"$FX/capwt/sl\"}}" \
  "[{\"agent\":\"claude\",\"agent_status\":\"blocked\",\"pane_id\":\"w9:sa\",\"cwd\":\"$FX/capwt/sa\",\"foreground_cwd\":\"$FX/capwt/sa\"},{\"agent\":\"claude\",\"agent_status\":\"working\",\"pane_id\":\"w9:sf\",\"cwd\":\"$FX/capwt/sf\",\"foreground_cwd\":\"$FX/capwt/sf\"},{\"agent\":\"claude\",\"agent_status\":\"idle\",\"pane_id\":\"w9:sl\",\"cwd\":\"$FX/capwt/sl\",\"foreground_cwd\":\"$FX/capwt/sl\"}]"
PATH="$FX/coordbin:$PATH" OPSX_FAKE_LOG="$FX/cc.log" OPSX_TEST_COLLECT_JSON="$FX/cc-collect.json" OPSX_TEST_HERDR_AGENTS="$FX/cap-agents.json" \
  bash "$OPSX_ROOT/bin/opsx" coordinate > "$FX/cc-out" 2>&1 || fail "coordinate 要跑完: $(cat "$FX/cc-out")"
grep -qF '同時在跑 3 個 pane，達上限 3' "$OPSX_STATE_DIR/coordinator.log" || fail "協調者要記同時在跑 3 個 pane，達上限 3: $(cat "$OPSX_STATE_DIR/coordinator.log")"
assert_not_grep '^opsx dispatch' "$FX/cc.log"
mkdir -p "$R/openspec/changes/card-x"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/card-x/.openspec.yaml"
out="$(OPSX_TEST_HERDR_AGENTS="$FX/cap-agents.json" opsx dispatch card-x --agent claude --mode interactive 2>&1)"; rc=$?
assert_eq "$rc" 0 "上限 3 手動派照派: $out"
echo "$out" | grep -qxF 'dispatch: 已有 3/3 個 pane' || fail "手動派要跟協調者數到同一個 3: $out"
rm -f "$OPSX_STATE_DIR/max-working"

assert_not_grep 'gitlab\.example\.com' "$OPSX_FAKE_LOG"
assert_not_grep 'gitlab\.example\.com' "$FX/glab-all.log"
echo ok
