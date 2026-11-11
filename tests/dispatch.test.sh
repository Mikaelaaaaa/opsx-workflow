#!/usr/bin/env bash
# opsx dispatch / stop：用假 herdr 驗呼叫順序和寫下的檔。要求檔 §3.6「派」、§3.1。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela
export OPSX_DRIVE_MAX=0   # autopilot 會在背景起 drive；0 輪讓它登記完就結束，不在 fixture 上跑迴圈
wait_drive() { # <repo> <slug>：等背景 drive 跑完（log 出現結束那行），最多 5 秒
  local f="$OPSX_STATE_DIR/drive-$1-$2.log" n=0
  until grep -q '跑滿 [01] 輪' "$f" 2>/dev/null; do n=$((n+1)); [ $n -lt 50 ] || fail "drive 沒在背景起來：$f"; sleep 0.1; done
}

R="$(mk_repo Agentory-CS git@gitlab.tsg-navigator.com:agentory/Agentory-CS.git)"
mkdir -p "$R/openspec/changes/retry-backoff" "$OPSX_STATE_DIR"
printf 'schema: opsx\ncreated: 2026-11-05\n' > "$R/openspec/changes/retry-backoff/.openspec.yaml"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$R/openspec/changes/retry-backoff/explore.md"
printf '[repos]\n"Agentory-CS" = "agnetory-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"   # label，dispatch 用 workspace list 換成 w1
printf '[repos."Agentory-CS"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"

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
wait_drive Agentory-CS retry-backoff   # autopilot 一律起 drive
assert_eq "$(jq -r '."Agentory-CS/retry-backoff".drive_pid | type' "$FX/drive-snap.json")" number "drive 跑的時候 drive_pid 要登記在 dispatch 寫的 key 下"
assert_grep '^kind: bug-fix$' "$R/openspec/changes/retry-backoff/.openspec.yaml"
[ -d "$R/.claude/worktrees/retry-backoff" ] || fail "worktree 沒開"
assert_eq "$(git -C "$R/.claude/worktrees/retry-backoff" rev-parse --abbrev-ref HEAD)" "fix/retry-backoff/mikaela" "branch 命名"
# herdr 呼叫順序：tab create（在 w1）→ agent start（帶 model + settings）→ agent prompt /propose（explore 待決空 → propose）
assert_grep '^tab create --workspace w1 --cwd .*retry-backoff --label retry-backoff' "$OPSX_FAKE_LOG"
assert_grep '^workspace list$' "$OPSX_FAKE_LOG"
assert_grep '^agent start retry-backoff --kind claude --pane w1:pE -- --model claude-sonnet-5-5 --permission-mode dontAsk --settings '"$OPSX_STATE_DIR"'/settings/Agentory-CS-retry-backoff-autopilot.json --add-dir ' "$OPSX_FAKE_LOG"
# 沙盒只准寫 working directories：卡的檔在主 repo 的 openspec/、hook 與 status 寫 state dir，兩個都要 --add-dir
assert_grep "^agent start retry-backoff .* --add-dir $R/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"
assert_grep '^agent prompt retry-backoff /propose retry-backoff$' "$OPSX_FAKE_LOG"
assert_not_grep '^workspace create' "$OPSX_FAKE_LOG"
# settings：repo 永遠 push 進 allow；merge 在 allow 不在 deny（deny 會蓋過 grant-gate 的放行，merge 由 gate 單獨把關）
S="$OPSX_STATE_DIR/settings/Agentory-CS-retry-backoff-autopilot.json"; assert_file "$S"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert "Bash(git push:*)" in d["allow"],d;assert "Bash(glab mr merge:*)" in d["allow"] and "Bash(gh pr merge:*)" in d["allow"],d;assert not any("merge" in x for x in d["deny"]),d;assert not any("glab mr create" in a for a in d["allow"]),d;assert "Bash(glab issue note:*)" not in d["allow"] and "Bash(gh issue comment:*)" not in d["allow"],d' "$S"
# dontAsk 下不在 allow 的指令直接被拒：常用唯讀與測試指令要在 allow 裡，不然 agent 連跑測試都不行
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];miss=[x for x in ["Bash(jq:*)","Bash(head:*)","Bash(tail:*)","Bash(wc:*)","Bash(sed -n:*)","Bash(bash tests/:*)","Bash(herdr agent:*)","Bash(glab mr view:*)","Bash(glab ci:*)","Bash(gh pr view:*)","Bash(git merge-base:*)","Bash(git remote:*)"] if x not in a];assert not miss,miss' "$S" || fail "allow 少了常用指令"
# 重啟 / resume 後旗標不在，可寫目錄還要由 settings 供應
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert d["additionalDirectories"]==[sys.argv[2],sys.argv[3]],d' "$S" "$R/openspec" "$OPSX_STATE_DIR" || fail "autopilot settings 缺 additionalDirectories"
# dispatch.json
python3 -I -c '
import json,sys;d=json.load(open(sys.argv[1]))["Agentory-CS/retry-backoff"]
assert d["pane"]=="w1:pE" and d["tab"]=="w1:tB" and d["workspace"]=="agnetory-ai" and d["workspace_id"]=="w1" and d["mode"]=="autopilot" and d["kind"]=="bug-fix" and d["model"]=="claude-sonnet-5-5" and d["agent"]=="claude", d
assert d["branch"]=="fix/retry-backoff/mikaela" and d["grants"]==[] and d["once"]==[] and d["drive_pid"] is None, d' "$OPSX_STATE_DIR/dispatch.json"   # drive 跑完清掉自己的 pid
# 另一個 repo 派出同名 slug：herdr 只認名字，會送錯 agent，要拒絕
R4="$(mk_repo Agentory-X)"; mkdir -p "$R4/openspec/changes/retry-backoff"; printf 'schema: opsx\n' > "$R4/openspec/changes/retry-backoff/.openspec.yaml"
printf '"Agentory-X" = "agnetory-ai"\n' >> "$OPSX_STATE_DIR/workspaces.toml"
out="$(cd "$R4" && opsx dispatch retry-backoff --agent claude --mode autopilot --kind dev 2>&1)"; [ $? -ne 0 ] || fail "同名 slug 要拒絕"
echo "$out" | grep -q 'Agentory-CS/retry-backoff' || fail "要指名撞到哪張: $out"
last_row() { tail -1 "$R/openspec/changes/retry-backoff/decisions.tsv" | cut -f2-3; }
assert_eq "$(last_row)" "你$(printf '\t')已指派"
assert_eq "$(tail -1 "$R/openspec/changes/retry-backoff/decisions.tsv" | awk -F'\t' '{print NF}')" 5

# --- 同一張卡還在跑就再派：拒絕，說它在哪（herdr 本來就會回 agent_name_taken；板上「指派」按到舊畫面就是這條） ---
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch retry-backoff --agent claude --mode autopilot 2>&1)"; [ $? -eq 2 ] || fail "active card must be refused: $out"
echo "$out" | grep -q 'agnetory-ai · w1:tB · w1:pE' || fail "要說它在哪: $out"
echo "$out" | grep -q 'opsx stop retry-backoff' || fail "要說怎麼換人: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"

# --- agent start 回 agent_pane_busy（shell 還沒到 prompt）：同一個 pane 重試；一直 busy 就關 tab ---
export OPSX_DISPATCH_RETRY_SLEEP=0
mkdir -p "$R/openspec/changes/busy-card"; printf 'schema: opsx\n' > "$R/openspec/changes/busy-card/.openspec.yaml"
export OPSX_TEST_BUSY_LEFT="$FX/busy-left"
: > "$OPSX_FAKE_LOG"; echo 2 > "$OPSX_TEST_BUSY_LEFT"
out="$(opsx dispatch busy-card --agent claude --mode interactive --kind dev 2>&1)" || fail "busy twice should still dispatch: $out"
assert_eq "$(grep -c '^agent start busy-card ' "$OPSX_FAKE_LOG")" 3 "two busy then ok = three starts"
assert_no_file "$OPSX_STATE_DIR/drive-Agentory-CS-busy-card.log"   # interactive 不起 drive
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;assert "Agentory-CS/busy-card" in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json"
# 一直 busy：六次後放棄，關掉剛開的 tab，什麼都不記
mkdir -p "$R/openspec/changes/stuck-card"; printf 'schema: opsx\n' > "$R/openspec/changes/stuck-card/.openspec.yaml"
: > "$OPSX_FAKE_LOG"; echo 99 > "$OPSX_TEST_BUSY_LEFT"
out="$(opsx dispatch stuck-card --agent claude --mode interactive --kind dev 2>&1)"; [ $? -ne 0 ] || fail "persistent busy must fail"
assert_eq "$(grep -c '^agent start stuck-card ' "$OPSX_FAKE_LOG")" 6 "six attempts then give up"
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"
echo "$out" | grep -q 'agent_pane_busy' || fail "should print herdr error: $out"
python3 -I -c 'import json,sys;assert "Agentory-CS/stuck-card" not in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json"
[ -f "$R/openspec/changes/stuck-card/decisions.tsv" ] && grep -q dispatched "$R/openspec/changes/stuck-card/decisions.tsv" && fail "must not record dispatched"
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
python3 -I -c 'import json,sys;assert "Agentory-CS/stuck-card" not in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json"
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
assert_grep '^agent prompt trust-card /explore trust-card$' "$OPSX_FAKE_LOG"
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;assert "Agentory-CS/trust-card" in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json"
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
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["Agentory-CS/retry-backoff"];assert d["agent"]=="codex" and d["model"]=="gpt-5" and d["mode"]=="interactive",d' "$OPSX_STATE_DIR/dispatch.json" || fail "redispatch must rewrite the entry"
# interactive 的 claude 也要 --add-dir（互動模式一樣在沙盒裡）
opsx stop retry-backoff >/dev/null 2>&1 || fail "stop before redispatch"
: > "$OPSX_FAKE_LOG"
# symlink-safe-writes：settings 檔名被換成 symlink → 換成一般檔、目標不變
mkdir -p "$OPSX_STATE_DIR/settings"; printf 'keep me\n' > "$FX/victim"; rm -f "$OPSX_STATE_DIR/settings/Agentory-CS-retry-backoff-interactive.json"; ln -s "$FX/victim" "$OPSX_STATE_DIR/settings/Agentory-CS-retry-backoff-interactive.json"
opsx dispatch retry-backoff --agent claude --mode interactive >/dev/null 2>&1 || fail "redispatch interactive claude"
assert_eq "$(cat "$FX/victim")" "keep me" "settings 檔名上的 symlink 不能被寫到目標"
assert_grep "^agent start retry-backoff --kind claude --pane w1:pE -- --model claude-sonnet-5-5 --settings $OPSX_STATE_DIR/settings/Agentory-CS-retry-backoff-interactive.json --add-dir $R/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"   # kind 已是 bug-fix → sonnet
assert_not_grep '--permission-mode' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert d=={"additionalDirectories":[sys.argv[2],sys.argv[3]]},d' "$OPSX_STATE_DIR/settings/Agentory-CS-retry-backoff-interactive.json" "$R/openspec" "$OPSX_STATE_DIR" || fail "interactive settings 只該有 additionalDirectories"
# interactive 重派不能蓋掉 autopilot 那份的 allow / deny
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert d["allow"] and "Bash(git push --force:*)" in d["deny"],d' "$S" || fail "interactive 重派蓋掉了 autopilot 的 settings"

# symlink-safe-writes：drive log 是 symlink → dispatch 拒絕起 drive，非 0、訊息含路徑、目標不變
wait_drive Agentory-CS retry-backoff
opsx stop retry-backoff >/dev/null 2>&1 || fail "stop before drive-log symlink case"
DL="$OPSX_STATE_DIR/drive-Agentory-CS-retry-backoff.log"; rm -f "$DL"; printf 'keep me\n' > "$FX/victim"; ln -s "$FX/victim" "$DL"
out="$(opsx dispatch retry-backoff --agent claude --mode autopilot 2>&1)"; [ $? -ne 0 ] || fail "drive log 是 symlink 要失敗：$out"
case "$out" in *drive-Agentory-CS-retry-backoff.log*) ;; *) fail "訊息要含 drive log 路徑：$out" ;; esac
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
rm "$OPSX_STATE_DIR/workspaces.toml"; cp "$FX/ws.real" "$OPSX_STATE_DIR/workspaces.toml"; : > "$OPSX_FAKE_LOG"
printf '[repos."scam-guard"]\nmr = true\n' >> "$OPSX_STATE_DIR/grants.toml"
opsx dispatch rdap-timeout --agent claude --mode autopilot --kind dev >/dev/null 2>&1 || fail "dispatch unmapped repo"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];miss=[x for x in ["Bash(glab mr create:*)","Bash(gh pr create:*)","Bash(glab issue note:*)","Bash(glab issue comment:*)","Bash(gh issue comment:*)"] if x not in a];assert not miss,miss' "$OPSX_STATE_DIR/settings/scam-guard-rdap-timeout-autopilot.json" || fail "mr 授權的 allow 要含 issue 留言"
assert_grep '^workspace create --label scam-guard' "$OPSX_FAKE_LOG"
assert_grep '^"scam-guard" = "scam-guard"$' "$OPSX_STATE_DIR/workspaces.toml"   # 記 label，id 在 dispatch.json
assert_grep '^tab create --workspace w9 ' "$OPSX_FAKE_LOG"
assert_grep '^agent start rdap-timeout --kind claude --pane w1:pE -- --model claude-opus-5-5 ' "$OPSX_FAKE_LOG"   # dev → opus
# --- workspaces.toml 寫了 herdr 沒有的 label → 明講，不猜 ---
R3="$(mk_repo gmtc-rag)"; mkdir -p "$R3/openspec/changes/z"; printf 'schema: opsx\n' > "$R3/openspec/changes/z/.openspec.yaml"
printf '"gmtc-rag" = "develop"\n' >> "$OPSX_STATE_DIR/workspaces.toml"
out="$(cd "$R3" && opsx dispatch z --agent claude --mode autopilot --kind dev 2>&1)"; [ $? -ne 0 ] || fail "沒有的 workspace 要失敗"
echo "$out" | grep -q 'develop' && echo "$out" | grep -q 'agnetory-ai' || fail "要列出現有 label: $out"
assert_grep '^agent prompt rdap-timeout /explore rdap-timeout$' "$OPSX_FAKE_LOG"                       # 沒 explore.md → explore

# --- workplan 有 branch 就用它 ---
R3="$(mk_repo Agentory-AI)"; mkdir -p "$R3/openspec/changes/eval-core"; printf 'schema: opsx\nkind: dev\n' > "$R3/openspec/changes/eval-core/.openspec.yaml"
printf 'features:\n  - name: eval\n    prs:\n      - name: eval-core\n        branch: feat/eval-core-v2/mikaela\n        status: pending\n' > "$R3/openspec/workplan.yaml"
printf '"Agentory-AI" = "w1"\n' >> "$OPSX_STATE_DIR/workspaces.toml"
cd "$R3"; opsx dispatch eval-core --agent claude --mode drive >/dev/null 2>&1 || fail "dispatch with workplan"
wait_drive Agentory-AI eval-core   # --mode drive 是 autopilot 的別名：照樣起 drive，dispatch.json 寫 autopilot
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["Agentory-AI/eval-core"];assert d["mode"]=="autopilot",d' "$OPSX_STATE_DIR/dispatch.json" || fail "--mode drive 要寫成 autopilot"
assert_eq "$(git -C "$R3/.claude/worktrees/eval-core" rev-parse --abbrev-ref HEAD)" "feat/eval-core-v2/mikaela" "workplan branch"

# --- 分支尾巴：OPSX_USER 沒設就用 git user.name；是 git 的占位字「Your Name」或空的就拒絕，不開 worktree 不碰 herdr ---
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
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["Agentory-CS/retry-backoff"];assert d["mode"]=="stopped" and d["stopped_at"],d' "$OPSX_STATE_DIR/dispatch.json"
assert_eq "$(last_row)" "你$(printf '\t')已停止"
assert_rc 2 opsx stop nope

# --- 停下的代管卡重派（auto-dispatch 4.2）：整筆改寫，不再帶 via / herdr_name ---
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));e=d["Agentory-CS/retry-backoff"];e.update(mode="stopped",via="p",herdr_name="p");json.dump(d,open(p,"w"))' "$OPSX_STATE_DIR/dispatch.json"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch retry-backoff --agent claude --mode autopilot 2>&1)" || fail "redispatch 代管卡: $out"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Agentory-CS/retry-backoff"];assert "via" not in e and "herdr_name" not in e and e["mode"]=="autopilot",e' "$OPSX_STATE_DIR/dispatch.json" || fail "重派要整筆改寫"
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
EOF
mkdir -p "$RF/openspec"; mv "$RF/openspec-wp.yaml" "$RF/openspec/workplan.yaml"
for s in m1 m2 m3; do mkdir -p "$RF/openspec/changes/$s"; printf 'schema: opsx\nkind: dev\n' > "$RF/openspec/changes/$s/.openspec.yaml"; printf -- '- [ ] 1.1 x\n' > "$RF/openspec/changes/$s/tasks.md"; done
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
assert_grep '^agent prompt fs /apply m1$' "$OPSX_FAKE_LOG"
J="$OPSX_STATE_DIR/dispatch.json"
assert_eq "$(jq -r '."Feat-Repo/@fs" | [.workspace, .workspace_id, .tab, .pane, .worktree, .agent, .mode, (.drive_pid | tostring), (.started_at | length > 0 | tostring), (.model | length > 0 | tostring)] | join(" ")' "$J")" \
  "Feat-Repo w9 w1:tB w1:pE $RF/.claude/worktrees/fs claude autopilot null true true" "session 條目"
assert_eq "$(jq -r '."Feat-Repo/@fs" | has("branch") or has("kind") or has("via") or has("feature") or has("herdr_name") | tostring' "$J")" false "session 條目不帶卡的欄位"
assert_eq "$(jq -r '."Feat-Repo/m1" | [.herdr_name, .via, .feature, .pane, .branch] | join(" ")' "$J")" "fs @fs fs w1:pE feat/m1/mikaela" "m1 的條目"
assert_eq "$(jq -r '."Feat-Repo/m2" | [.herdr_name, .via, .feature, .pane, .branch] | join(" ")' "$J")" "fs @fs fs w1:pE feat/m2/mikaela" "m2 跟 m1 共用 pane"
assert_eq "$(jq -r 'keys | map(select(startswith("Feat-Repo/"))) | join(" ")' "$J")" "Feat-Repo/@fs Feat-Repo/m1 Feat-Repo/m2" "session 加兩個成員共三筆"
assert_eq "$(jq -r '."Feat-Repo/m3" // "none"' "$J")" none "依賴沒滿足的主 change 不寫"
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
assert_eq "$(cat "$OPSX_FAKE_LOG")" "agent prompt fs [m2] /apply m2" "只送一句給 session"
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
sed -i.bak 's/^"Feat-Repo" = .*/"Feat-Repo" = "agnetory-ai"/' "$OPSX_STATE_DIR/workspaces.toml"   # 第一次派新建的 workspace 不在假 herdr 的 workspace list 裡
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch --feature fs --agent claude --mode autopilot 2>&1)"; assert_eq "$?" 0 "session 重派: $out"
assert_eq "$(jq -r '."Feat-Repo/m1".mode' "$J")" stopped "人停的 m1 仍是 stopped"
assert_grep '^agent prompt fs /apply m2$' "$OPSX_FAKE_LOG"
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
assert_grep '^agent prompt fs /apply m2$' "$OPSX_FAKE_LOG"
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
assert_grep '^agent prompt fs /apply m2$' "$OPSX_FAKE_LOG"
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
assert_grep '^agent prompt note-card /explore note-card$' "$OPSX_FAKE_LOG"
assert_file "$FX/note-at-prompt.md"
awk '/^## 派工指示[[:space:]]*$/{f=1;next} /^## /{f=0} f && /^- /' "$FX/note-at-prompt.md" | grep -qE '^- 20[0-9-]+T[0-9:]+[+-][0-9:]+ 先跑 lint$' || fail "第一句送出時要已寫入：$(cat "$FX/note-at-prompt.md")"
cp "$N/inbox.md" "$FX/note-before.md"
out="$(opsx dispatch note-card --agent claude --mode interactive --note "第二條" 2>&1)"; [ $? -ne 0 ] || fail "還在跑的卡重派要拒絕: $out"
cmp -s "$N/inbox.md" "$FX/note-before.md" || fail "重派被拒時不該寫指示"
opsx stop note-card >/dev/null 2>&1 || fail "stop note-card"
opsx dispatch note-card --agent claude --mode interactive >/dev/null 2>&1 || fail "不帶 --note 重派"
cmp -s "$N/inbox.md" "$FX/note-before.md" || fail "不帶 --note 不該動 inbox.md"
opsx --help 2>&1 | grep -q '^  dispatch .*--note' || fail "opsx --help 的 dispatch 行要列 --note"
echo ok
