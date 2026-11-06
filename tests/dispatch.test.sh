#!/usr/bin/env bash
# opsx dispatch / stop：用假 herdr 驗呼叫順序和寫下的檔。要求檔 §3.6「派」、§3.1。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela

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
out="$(opsx dispatch retry-backoff --agent claude --mode autopilot --kind bug-fix 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
assert_grep '^kind: bug-fix$' "$R/openspec/changes/retry-backoff/.openspec.yaml"
[ -d "$R/.claude/worktrees/retry-backoff" ] || fail "worktree 沒開"
assert_eq "$(git -C "$R/.claude/worktrees/retry-backoff" rev-parse --abbrev-ref HEAD)" "fix/retry-backoff/mikaela" "branch 命名"
# herdr 呼叫順序：tab create（在 w1）→ agent start（帶 model + settings）→ agent prompt /propose（explore 待決空 → propose）
assert_grep '^tab create --workspace w1 --cwd .*retry-backoff --label retry-backoff' "$OPSX_FAKE_LOG"
assert_grep '^workspace list$' "$OPSX_FAKE_LOG"
assert_grep '^agent start retry-backoff --kind claude --pane w1:pE -- --model claude-sonnet-5-5 --permission-mode acceptEdits --settings ' "$OPSX_FAKE_LOG"
# 沙盒只准寫 working directories：卡的檔在主 repo 的 openspec/、hook 與 status 寫 state dir，兩個都要 --add-dir
assert_grep "^agent start retry-backoff .* --add-dir $R/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"
assert_grep '^agent prompt retry-backoff /propose retry-backoff$' "$OPSX_FAKE_LOG"
assert_not_grep '^workspace create' "$OPSX_FAKE_LOG"
# settings：repo 永遠 push 進 allow；merge 在 allow 不在 deny（deny 會蓋過 grant-gate 的放行，merge 由 gate 單獨把關）
S="$OPSX_STATE_DIR/settings/Agentory-CS-retry-backoff.json"; assert_file "$S"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert "Bash(git push:*)" in d["allow"],d;assert "Bash(glab mr merge:*)" in d["allow"] and "Bash(gh pr merge:*)" in d["allow"],d;assert not any("merge" in x for x in d["deny"]),d;assert not any("glab mr create" in a for a in d["allow"]),d' "$S"
# dispatch.json
python3 -I -c '
import json,sys;d=json.load(open(sys.argv[1]))["Agentory-CS/retry-backoff"]
assert d["pane"]=="w1:pE" and d["tab"]=="w1:tB" and d["workspace"]=="agnetory-ai" and d["workspace_id"]=="w1" and d["mode"]=="autopilot" and d["kind"]=="bug-fix" and d["model"]=="claude-sonnet-5-5" and d["agent"]=="claude", d
assert d["branch"]=="fix/retry-backoff/mikaela" and d["grants"]==[] and d["once"]==[] and d["drive_pid"] is None, d' "$OPSX_STATE_DIR/dispatch.json"
# 另一個 repo 派出同名 slug：herdr 只認名字，會送錯 agent，要拒絕
R4="$(mk_repo Agentory-X)"; mkdir -p "$R4/openspec/changes/retry-backoff"; printf 'schema: opsx\n' > "$R4/openspec/changes/retry-backoff/.openspec.yaml"
printf '"Agentory-X" = "agnetory-ai"\n' >> "$OPSX_STATE_DIR/workspaces.toml"
out="$(cd "$R4" && opsx dispatch retry-backoff --agent claude --mode autopilot --kind dev 2>&1)"; [ $? -ne 0 ] || fail "同名 slug 要拒絕"
echo "$out" | grep -q 'Agentory-CS/retry-backoff' || fail "要指名撞到哪張: $out"
assert_grep 'dispatched' "$R/openspec/changes/retry-backoff/decisions.tsv"

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
assert_grep '^agent start retry-backoff --kind codex --pane w1:pE -- -a on-request -s workspace-write$' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["Agentory-CS/retry-backoff"];assert d["agent"]=="codex" and d["model"]=="gpt-5" and d["mode"]=="interactive",d' "$OPSX_STATE_DIR/dispatch.json" || fail "redispatch must rewrite the entry"
# interactive 的 claude 也要 --add-dir（互動模式一樣在沙盒裡）
opsx stop retry-backoff >/dev/null 2>&1 || fail "stop before redispatch"
: > "$OPSX_FAKE_LOG"
opsx dispatch retry-backoff --agent claude --mode interactive >/dev/null 2>&1 || fail "redispatch interactive claude"
assert_grep "^agent start retry-backoff --kind claude --pane w1:pE -- --model claude-sonnet-5-5 --add-dir $R/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"   # kind 已是 bug-fix → sonnet

# --- 沒掛 workspace 的 repo → 開新 workspace 並記下來 ---
R2="$(mk_repo scam-guard https://github.com/Mikaelaaaaa/scam-guard.git)"
mkdir -p "$R2/openspec/changes/rdap-timeout"; printf 'schema: opsx\n' > "$R2/openspec/changes/rdap-timeout/.openspec.yaml"
: > "$OPSX_FAKE_LOG"; cd "$R2"
opsx dispatch rdap-timeout --agent claude --mode autopilot --kind dev >/dev/null 2>&1 || fail "dispatch unmapped repo"
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
cd "$R3"; opsx dispatch eval-core --agent claude --mode autopilot >/dev/null 2>&1 || fail "dispatch with workplan"
assert_eq "$(git -C "$R3/.claude/worktrees/eval-core" rev-parse --abbrev-ref HEAD)" "feat/eval-core-v2/mikaela" "workplan branch"

# --- stop ---
: > "$OPSX_FAKE_LOG"; cd "$R"
opsx stop retry-backoff >/dev/null 2>&1 || fail "stop"
assert_grep '^pane close w1:pE$' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["Agentory-CS/retry-backoff"];assert d["mode"]=="stopped" and d["stopped_at"],d' "$OPSX_STATE_DIR/dispatch.json"
assert_grep 'stopped' "$R/openspec/changes/retry-backoff/decisions.tsv"
assert_rc 2 opsx stop nope
echo ok
