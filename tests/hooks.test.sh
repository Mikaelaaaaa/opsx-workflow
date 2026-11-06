#!/usr/bin/env bash
# 五支 hook：router / commit-gate / grant-gate / mr-format-gate / stop-gate。要求檔 §8.5。
# 每個 case 餵一段 hook JSON 到 stdin，看輸出的 JSON 決定。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

run_hook() { # <hook> <json> → stdout
  printf '%s' "$2" | bash "$H/$1" 2>/dev/null; true
}
j() { python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name=sys.argv[2],tool_input=json.loads(sys.argv[3]),prompt=sys.argv[4],hook_event_name=sys.argv[5])))' "$1" "$2" "${3:-{\}}" "${4:-}" "${5:-UserPromptSubmit}"; }
decision() { [ -z "$1" ] && { echo allow; return; }; printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // .decision // "allow"'; }
reason()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // .reason // .hookSpecificOutput.additionalContext // ""'; }

R="$(mk_repo Agentory-AI git@gitlab.tsg-navigator.com:agentory/Agentory-AI.git)"
mkdir -p "$R/openspec/changes/archive"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"

# ---------- router ----------
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "繼續")")"
reason "$out" | grep -q '^opsx：explore · eval-core · bug-fix' || fail "router: inbox-only → explore: $(reason "$out")"
printf '## 已知\n- x\n\n## 待決\n- 選 A 還是 B\n\n## 不做\n' > "$C/explore.md"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：grill · eval-core' || fail "router: 待決非空 → grill: $(reason "$out")"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$C/explore.md"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：propose · eval-core' || fail "router: 待決空 → propose: $(reason "$out")"
printf '## 1. x\n\n- [ ] 1.1 a\n  - 驗收：R1\n  - 測試：tests/a.test.ts\n- [ ] 1.2 b\n' > "$C/tasks.md"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "做")")"
reason "$out" | grep -q '^opsx：apply · eval-core · bug-fix · skills/apply/SKILL.md · skills/apply/references/playbooks/bug-fix.md · skills/tdd/SKILL.md' || fail "router: apply + playbook + tdd: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "先 tdd 把測試寫出來")")"; reason "$out" | grep -q '^opsx：tdd · eval-core' || fail "router: tdd 關鍵詞: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "/babysit 看一下 MR")")"; reason "$out" | grep -q '平行流程：babysit' || fail "router: 平行流程關鍵詞: $(reason "$out")"
printf '## 1. x\n\n- [x] 1.1 a\n- [x] 1.2 b\n' > "$C/tasks.md"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q 'tests 不是 green' || fail "router: 全勾但沒 tests: $(reason "$out")"
printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：review · eval-core' || fail "router: review: $(reason "$out")"
printf '# report\n四桶…\n' > "$C/report.md"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：pr · eval-core' || fail "router: pr: $(reason "$out")"
printf '# report\nMR: https://gitlab.tsg-navigator.com/a/b/-/merge_requests/212\n' > "$C/report.md"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：babysit · eval-core' || fail "router: MR 已開 → babysit: $(reason "$out")"
# 不是 opsx repo → 不印
P="$(mk_repo plain)"; out="$(run_hook openspec-router.sh "$(j "$P" "" '{}' "hi")")"; assert_eq "$out" "" "router: 非 opsx repo 要安靜"
# 沒對到卡的 branch
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" checkout -q main
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "hi")")"; reason "$out" | grep -q '沒有對到卡' || fail "router: no card: $(reason "$out")"
git -C "$R" checkout -q feat/eval-core/mikaela

# ---------- commit gate ----------
cg() { run_hook openspec-commit-gate.sh "$(j "$R" Bash "{\"command\":$(printf '%s' "$1" | jq -Rs .)}")"; }
out="$(cg 'git commit -m "feat: x" -- a.ts')"; reason "$out" | grep -q '閘門未啟用' || fail "commit: no workplan → 不擋: $out"
assert_eq "$(decision "$out")" allow
printf 'prs:\n  - name: eval-core\n    status: in-progress\n' > "$R/openspec/workplan.yaml"
printf '## 1. x\n\n- [ ] 1.1 a\n' > "$C/tasks.md"
out="$(cg 'git commit -m "feat: x" -- a.ts')"; assert_eq "$(decision "$out")" deny "commit: tasks 全未勾要擋"
printf '## 1. x\n\n- [x] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"
out="$(cg 'git commit -m "feat: x" -- a.ts')"; assert_eq "$(decision "$out")" allow "commit: 有勾放行"
out="$(cg 'git -C /x commit -m "feat: x"')"; assert_eq "$(decision "$out")" allow "commit: git -C 也認得"
git -C "$R" checkout -q main
out="$(cg 'git commit -m "chore: bump"')"; assert_eq "$(decision "$out")" deny "commit: branch 對不到卡要擋"
out="$(cg 'git commit -m "chore: bump [no-change] 只是改 README"')"; assert_eq "$(decision "$out")" allow "commit: [no-change] 放行"
assert_grep "Agentory-AI" "$OPSX_STATE_DIR/bypass.log"
out="$(cg 'ls -la')"; assert_eq "$out" "" "commit: 非 commit 指令不出聲"
git -C "$R" checkout -q feat/eval-core/mikaela

# ---------- grant gate ----------
gg() { run_hook opsx-grant-gate.sh "$(j "$R" "$1" "$2")"; }
cmdj() { printf '{"command":%s}' "$(printf '%s' "$1" | jq -Rs .)"; }
# 沒 dispatch.json → 不管
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" allow "grant: 沒派工不管"
mkdir -p "$OPSX_STATE_DIR"
printf '{"Agentory-AI/eval-core":{"mode":"interactive","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" allow "grant: 互動模式不管"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":["migrate"]}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '[repos."Agentory-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" allow "grant: repo 永遠 push"
out="$(gg Bash "$(cmdj 'glab mr create -F desc.md')")"; assert_eq "$(decision "$out")" deny "grant: mr 沒授權"
reason "$out" | grep -q 'gates.md' || fail "grant: deny 要叫它寫 gate"
out="$(gg Bash "$(cmdj 'pnpm db:migrate')")"; assert_eq "$(decision "$out")" allow "grant: 這張卡的 migrate"
out="$(gg Bash "$(cmdj 'glab mr merge 212')")"; assert_eq "$(decision "$out")" deny "grant: merge 第三級"
reason "$out" | grep -q '第三級' || fail "grant: merge 要說第三級"
out="$(gg Bash "$(cmdj 'git push --force gitlab main')")"; assert_eq "$(decision "$out")" deny "grant: force push"
out="$(gg Bash "$(cmdj 'pnpm add left-pad')")"; assert_eq "$(decision "$out")" deny "grant: 裝套件第二級沒授權"
out="$(gg Bash "$(cmdj 'pnpm test:ring0')")"; assert_eq "$(decision "$out")" allow "grant: 跑測試直接做"
out="$(gg Bash "$(cmdj 'curl -s http://localhost:3000/api/health')")"; assert_eq "$(decision "$out")" allow "grant: localhost 不算外部"
out="$(gg Bash "$(cmdj 'curl https://api.example.com/x')")"; assert_eq "$(decision "$out")" deny "grant: 外部 API"
out="$(gg Write '{"file_path":"/x/.env.local","content":"A=1"}')"; assert_eq "$(decision "$out")" deny "grant: 寫 .env"
out="$(gg Write '{"file_path":"/x/.env.example","content":"A="}')"; assert_eq "$(decision "$out")" allow "grant: .env.example 可以"
out="$(gg Edit '{"file_path":"/x/.gitlab-ci.yml","old_string":"a","new_string":"b"}')"; assert_eq "$(decision "$out")" deny "grant: 改 CI 第三級"
out="$(gg Edit '{"file_path":"/x/src/a.ts","old_string":"a","new_string":"b"}')"; assert_eq "$(decision "$out")" allow "grant: 一般檔直接做"

# ---------- grant gate：合併的一次性核准（herdr-board D5 / 3.3）----------
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
printf '#!/usr/bin/env bash\nexec bash "%s/glab" "$@"\n' "$FAKES" > "$FX/fakebin/glab"; chmod +x "$FX/fakebin/glab"
export PATH="$FX/fakebin:$PATH" OPSX_FAKE_LOG="$FX/fake.log" OPSX_TEST_GLAB_JSON="$FX/mr.json"; : > "$OPSX_FAKE_LOG"
printf '# report\nMR: https://gitlab.tsg-navigator.com/a/b/-/merge_requests/212\n' > "$C/report.md"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
# 核准相符，單一指令，MR 號碼對：放行；核准綁 sha 不刪，同一個 sha 再合一次還是放行（合併過的 MR 第二次 glab 自己會拒）
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[],"merge_approved":"abc123","merge_approved_at":"2026-11-06T01:00:00+08:00"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(gg Bash "$(cmdj 'glab mr merge 212 --squash')")"; assert_eq "$(decision "$out")" allow "grant: 核准相符放行"
assert_eq "$(jq -r '."Agentory-AI/eval-core".merge_approved' "$OPSX_STATE_DIR/dispatch.json")" abc123 "核准綁 sha，不刪"
out="$(gg Bash "$(cmdj 'glab mr merge 212 --squash')")"; assert_eq "$(decision "$out")" allow "grant: 同 sha 第二次仍放行"
out="$(gg Bash "$(cmdj 'glab mr merge --squash')")"; assert_eq "$(decision "$out")" allow "grant: 沒寫號碼（目前分支）也放行"
# 夾帶別的指令、合併別的 MR：deny
out="$(gg Bash "$(cmdj 'glab mr merge 212 --squash && git push --force origin main')")"; assert_eq "$(decision "$out")" deny "grant: 複合指令 deny"
out="$(gg Bash "$(cmdj 'git push origin HEAD; glab mr merge 212')")"; assert_eq "$(decision "$out")" deny "grant: 分號串接 deny"
out="$(gg Bash "$(cmdj 'glab mr merge 999 --squash')")"; assert_eq "$(decision "$out")" deny "grant: 別的 MR 號碼 deny"
reason "$out" | grep -q '999' || fail "grant: 要指出號碼不同: $(reason "$out")"
out="$(gg Bash "$(cmdj 'glab mr merge 212 && git push --force origin main')")"; assert_eq "$(decision "$out")" deny
# 「這次」授權：repo 永遠關掉，只靠 once
printf '[repos."Agentory-AI"]\npush = false\n' > "$OPSX_STATE_DIR/grants.toml"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[],"once":["push"]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" allow "grant: once 放行一次"
assert_eq "$(jq -c '."Agentory-AI/eval-core".once' "$OPSX_STATE_DIR/dispatch.json")" '[]' "once 用掉就刪"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" deny "grant: once 第二次 deny"
# grants.toml 壞掉：當成沒授權，不是放行
printf 'this is not toml ===\n' > "$OPSX_STATE_DIR/grants.toml"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" deny "grant: 壞 toml deny"
printf '[repos."Agentory-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
# 在 dispatch 開的 linked worktree 裡：repo 名要是主 repo，gate 照樣生效
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
git -C "$R" worktree add -q "$R/.claude/worktrees/eval-core" -b feat/eval-core/wt   # 主 checkout 已在 mikaela 那條，worktree 另開一條同 slug 的
WT="$(cd "$R/.claude/worktrees/eval-core" && pwd -P)"
out="$(run_hook opsx-grant-gate.sh "$(j "$WT" Bash "$(cmdj 'glab mr create -F desc.md')")")"; assert_eq "$(decision "$out")" deny "grant: worktree 裡也要 deny"
out="$(run_hook opsx-grant-gate.sh "$(j "$WT" Bash "$(cmdj 'pnpm test')")")"; assert_eq "$(decision "$out")" allow
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[],"merge_approved":"abc123"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(run_hook opsx-grant-gate.sh "$(j "$WT" Bash "$(cmdj 'glab mr merge 212 --squash')")")"; assert_eq "$(decision "$out")" allow "grant: worktree 裡核准相符放行"
# MR 又推了新 commit → deny，核准保留
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[],"merge_approved":"abc123"}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"def456","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
out="$(gg Bash "$(cmdj 'glab mr merge 212')")"; assert_eq "$(decision "$out")" deny "grant: sha 不符 deny"
reason "$out" | grep -q '看板' || fail "grant: deny 要指向看板的合併按鈕: $(reason "$out")"
assert_eq "$(jq -r '."Agentory-AI/eval-core".merge_approved' "$OPSX_STATE_DIR/dispatch.json")" abc123 "不符時核准不動"
# 沒有核准 → deny
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(gg Bash "$(cmdj 'gh pr merge 12 --squash')")"; assert_eq "$(decision "$out")" deny "grant: 沒核准 deny"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":["migrate"]}}' > "$OPSX_STATE_DIR/dispatch.json"; rm -f "$C/report.md"

# ---------- mr format gate ----------
mg() { run_hook mr-format-gate.sh "$(j "$R" Bash "$(cmdj "$1")")"; }
out="$(mg 'glab mr create --fill')"; assert_eq "$(decision "$out")" deny "mr: --fill 沒 description"
printf '# t\n\n## Summary\nx\n\n## Changes\n\n| 編號 | 程式碼改動 | 業務層邏輯 | 對應測試 |\n|---|---|---|---|\n| 1 | a | b | c |\n' > "$R/desc.md"
out="$(mg 'glab mr create -F desc.md --title "feat: x"')"; assert_eq "$(decision "$out")" allow "mr: 合格檔案"
printf '# t\n\n## Summary\nx\n' > "$R/bad.md"
out="$(mg 'glab mr create -F bad.md')"; assert_eq "$(decision "$out")" deny "mr: 缺 Changes"
out="$(mg 'gh pr create --title t --body "## Changes

| 編號 | 程式碼改動 | 業務層邏輯 | 對應測試 |
| 1 | a | b | c |"')"; assert_eq "$(decision "$out")" allow "mr: --body 內嵌"
out="$(mg 'gh pr create --title t --body "just text"')"; assert_eq "$(decision "$out")" deny "mr: body 不合格"
out="$(mg 'glab mr list')"; assert_eq "$out" "" "mr: 其他 glab 指令不出聲"

# ---------- security guard：AI 署名只看 commit message ----------
sd() { run_hook security-guard.sh "$(j "$R" Bash "$(cmdj "$1")")"; }
out="$(sd 'cd /private/tmp/claude-502/x && git commit -m "fix: clean"')"; assert_eq "$(decision "$out")" allow "guard: 路徑含 claude、message 乾淨"
out="$(sd 'git commit -m "feat: x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"')"; assert_eq "$(decision "$out")" deny "guard: message 含署名"
reason "$out" | grep -q Claude || fail "guard: 理由要提到 Claude"
out="$(sd 'cd /x/claude-502 && git commit -m clean && git push origin feat/x')"; assert_eq "$(decision "$out")" allow "guard: 串接指令只取 commit 段"
sd_heredoc() { sd "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfeat: x\n\n%s\nEOF\n)"' "$1")"; }
out="$(sd_heredoc 'Co-Authored-By: Claude <noreply@anthropic.com>')"; assert_eq "$(decision "$out")" deny "guard: heredoc 含署名"
out="$(sd_heredoc 'Refs: #12')"; assert_eq "$(decision "$out")" allow "guard: heredoc 乾淨"
out="$(sd 'git commit -am "ok"')"; assert_eq "$(decision "$out")" allow "guard: -am 乾淨"
out="$(sd 'git commit -am "Generated with Claude"')"; assert_eq "$(decision "$out")" deny "guard: -am 含署名"
out="$(sd 'git commit --message=ok')"; assert_eq "$(decision "$out")" allow "guard: --message= 乾淨"
out="$(sd 'git commit --message "Generated with Claude Code"')"; assert_eq "$(decision "$out")" deny "guard: --message 含署名"
out="$(sd 'git commit -m ";" -m "Co-Authored-By: Claude"')"; assert_eq "$(decision "$out")" deny "guard: 值是分隔字元不截斷後面的 -m"
out="$(sd 'git commit -m a && git commit -m "Co-Authored-By: Claude"')"; assert_eq "$(decision "$out")" deny "guard: 第二個 commit 也掃"
printf 'fix: clean\n' > "$R/msg-ok.txt"; printf 'feat: x\n\nCo-Authored-By: Claude\n' > "$R/msg-bad.txt"
out="$(sd 'git commit -F msg-ok.txt')"; assert_eq "$(decision "$out")" allow "guard: -F 乾淨"
out="$(sd 'git commit -F msg-bad.txt')"; assert_eq "$(decision "$out")" deny "guard: -F 含署名"
out="$(sd 'git commit -F nope.txt')"; assert_eq "$(decision "$out")" deny "guard: -F 檔案不存在"
reason "$out" | grep -q -- '-F' && reason "$out" | grep -q 'nope.txt' || fail "guard: 理由要有旗標和值"
out="$(sd 'git commit -F -')"; assert_eq "$(decision "$out")" deny "guard: -F - 讀不到"
reason "$out" | grep -q -- '-F' || fail "guard: -F - 理由要有旗標"
out="$(sd 'git commit -m "oops')"; assert_eq "$(decision "$out")" deny "guard: 引號不平衡"
reason "$out" | grep -q 'cannot parse command' || fail "guard: 要說 cannot parse command"
out="$(OPSX_STATE_DIR="$FX/no-such-state" sd 'git commit -m clean')"; assert_eq "$(decision "$out")" deny "guard: 沒有 python 路徑檔"
reason "$out" | grep -q 'opsx init --global' || fail "guard: 要說跑 opsx init --global"
out="$(OPSX_STATE_DIR="$FX/no-such-state" sd 'git status')"; assert_eq "$(decision "$out")" allow "guard: 不是 commit 就不載入 python"

# ---------- stop gate ----------
sg() { printf '{"cwd":"%s","stop_hook_active":%s}' "$R" "${1:-false}" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
printf '## 1. x\n\n- [x] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 有未勾"
out="$(sg true)"; assert_eq "$out" "" "stop: stop_hook_active 放行"
printf '## 1. x\n\n- [x] 1.1 a\n- [x] 1.2 b\n' > "$C/tasks.md"
printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"red","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: tests red"; reason "$out" | grep -q green || fail "stop: 要說要綠"
printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
rm -f "$C/report.md"; out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 沒 report"; reason "$out" | grep -q '/review' || fail "stop: 要叫跑 review"
printf '# report\n' > "$C/report.md"; sleep 1
out="$(sg)"; assert_eq "$out" "" "stop: 全齊放行"
git -C "$R" commit -q --allow-empty -m "feat: later"   # report 之後又 commit
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: report 後有新 commit"
# 還沒到 apply（沒 tasks.md）→ 不擋
rm -f "$C/tasks.md"; out="$(sg)"; assert_eq "$out" "" "stop: 沒 tasks 不擋"
echo ok
