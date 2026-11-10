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
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：propose · eval-core · bug-fix' || fail "router: bug-fix 待決非空 → propose（不經 grill）: $(reason "$out")"
printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$C/.openspec.yaml"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：grill · eval-core' || fail "router: dev 待決非空 → grill: $(reason "$out")"
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
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
# 模式規則：照 dispatch.json 該卡的 mode 附在那行後面；drive 讀成 autopilot；沒派過不附
mkdir -p "$OPSX_STATE_DIR"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; r="$(reason "$out")"
case "$r" in *"autopilot："*"不用 AskUserQuestion"*) ;; *) fail "router: autopilot 規則: $r" ;; esac
case "$r" in *'approval | decision'*'needs: run'*) ;; *) fail "router: autopilot 規則要寫合法 type 與 needs: run: $r" ;; esac
case "$r" in *"等待決定 / 等待授權"*) fail "router: 不能把看板標籤當 type 值教給 agent: $r" ;; esac
case "$r" in *"interactive："*) fail "router: autopilot 卡不該有 interactive 規則: $r" ;; esac
for tok in "不寫迴圈" "賦值" "命令替換" "{ } 群組" "source" "bash -c" '印 $?' "一個 Bash 呼叫做一件事" "opsx log"; do
  case "$r" in *"$tok"*) ;; *) fail "router: autopilot 的 Bash 寫法規則缺「${tok}」: $r" ;; esac
done
printf '{"Agentory-AI/eval-core":{"mode":"drive"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q 'autopilot：' || fail "router: drive 讀成 autopilot: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "/babysit 看一下 MR")")"; reason "$out" | grep -q 'autopilot：' || fail "router: 平行流程也要附規則: $(reason "$out")"
printf '{"Agentory-AI/eval-core":{"mode":"interactive"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q 'interactive：要授權就直接問' || fail "router: interactive 規則: $(reason "$out")"
reason "$out" | grep -q '不寫迴圈' && fail "router: interactive 卡不附 Bash 寫法規則: $(reason "$out")"
printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; r="$(reason "$out")"
case "$r" in *"autopilot："*|*"interactive："*|*"不寫迴圈"*) fail "router: 沒派過不附規則: $r" ;; esac
rm -f "$OPSX_STATE_DIR/dispatch.json"
# 派工指示（dispatch-note-cli note-router）：段裡有條目就每句帶「派工指示 N 條 · Read <inbox.md> …」
printf -- '---\ntype: 功能\n---\n\n## 一句話\n\n- 不算\n- 不算\n' > "$C/inbox.md"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：babysit' || fail "router: 沒有段落照常注入: $(reason "$out")"
reason "$out" | grep -q '派工指示' && fail "router: 沒有段落不帶派工指示: $(reason "$out")"
printf '\n## 派工指示\n\n' >> "$C/inbox.md"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：babysit' || fail "router: 空段落照常注入: $(reason "$out")"
reason "$out" | grep -q '派工指示' && fail "router: 空段落不帶派工指示: $(reason "$out")"
printf -- '- 2026-11-10T12:00:00+08:00 先跑 lint\n- 2026-11-10T12:05:00+08:00 撤銷上一條\n\n## 備註\n\n- 不算\n- 不算\n' >> "$C/inbox.md"
NOTE="派工指示 2 條 · Read $R/openspec/changes/eval-core/inbox.md ## 派工指示 · 跟 D 衝突開 gate"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; r="$(reason "$out")"
case "$r" in "opsx："*"$NOTE"*) ;; *) fail "router: 主流程行要帶派工指示: $r" ;; esac
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "" SessionStart)")"; r="$(reason "$out")"
case "$r" in *"$NOTE"*) ;; *) fail "router: SessionStart 要帶派工指示: $r" ;; esac
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "/babysit 看一下 MR")")"; r="$(reason "$out")"
case "$r" in *"平行流程：babysit"*"$NOTE"*) ;; *) fail "router: 平行流程行要帶派工指示: $r" ;; esac
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "先 tdd 把測試寫出來")")"; r="$(reason "$out")"
case "$r" in "opsx：tdd"*"$NOTE"*) ;; *) fail "router: tdd 行要帶派工指示: $r" ;; esac
rm -f "$C/inbox.md"
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
# 子殼分支 <主>--<子>：看子殼的 tasks.md，不看主殼
mkdir -p "$C/subs/s1"; printf '## 1. x\n\n- [ ] 1.1 a\n' > "$C/subs/s1/tasks.md"
printf '## 1. x\n\n- [ ] 1.1 s1\n' > "$C/tasks.md"
git -C "$R" checkout -q -b feat/eval-core--s1/mikaela
out="$(cg 'git commit -m "feat: x"')"; assert_eq "$(decision "$out")" deny "commit: 子殼全未勾要擋"
reason "$out" | grep -q 'subs/s1' || fail "commit: 子殼的 deny 要寫子殼路徑: $(reason "$out")"
printf '## 1. x\n\n- [x] 1.1 a\n' > "$C/subs/s1/tasks.md"
out="$(cg 'git commit -m "feat: x"')"; assert_eq "$(decision "$out")" allow "commit: 子殼有勾放行（主殼全未勾）"
printf '## 1. x\n\n- [x] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"; rm -rf "$C/subs"
git -C "$R" checkout -q feat/eval-core/mikaela

# ---------- grant gate ----------
gg() { run_hook opsx-grant-gate.sh "$(j "$R" "$1" "$2")"; }
cmdj() { printf '{"command":%s}' "$(printf '%s' "$1" | jq -Rs .)"; }
# 沒 dispatch.json → 不管
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" allow "grant: 沒派工不管"
mkdir -p "$OPSX_STATE_DIR"
printf '{"Agentory-AI/eval-core":{"mode":"interactive","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" allow "grant: 互動模式不管"
PD="${OPSX_STATE_DIR}-protected"; mkdir -p "$PD"   # 這張卡 / 這次 / 合併的授權只信這裡（protected-authorization）；dispatch.json 的同名欄位一律忽略
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '{"Agentory-AI/eval-core":{"grants":["migrate"]}}' > "$PD/authz.json"
printf '[repos."Agentory-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" allow "grant: repo 永遠 push"
out="$(gg Bash "$(cmdj 'glab mr create -F desc.md')")"; assert_eq "$(decision "$out")" deny "grant: mr 沒授權"
reason "$out" | grep -q 'gates.md' || fail "grant: deny 要叫它寫 gate"
reason "$out" | grep -qF 'approval | decision' || fail "grant: deny 要寫合法 type：$(reason "$out")"
reason "$out" | grep -qF 'needs: run' || fail "grant: deny 要寫 needs: run：$(reason "$out")"
out="$(gg Bash "$(cmdj 'pnpm db:migrate')")"; assert_eq "$(decision "$out")" allow "grant: 這張卡的 migrate"
# dontAsk 下不明說 allow 就會被 Claude 拒：有授權的動作要回 permissionDecision allow，不是空輸出
assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')" allow "grant: 有授權要明說 allow"
out="$(gg Bash "$(cmdj 'pnpm test:ring0')")"; assert_eq "$out" "" "grant: 沒分級的指令不出聲，交給 settings"
# 一段有授權不能替後面那段放行
out="$(gg Bash "$(cmdj 'pnpm db:migrate && glab mr create -F desc.md')")"; assert_eq "$(decision "$out")" deny "grant: 串起來的 mr 沒授權要擋"
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
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
# dispatch.json 偽造的核准（沙盒內 session 寫得到那個檔）：sha 相符也 deny
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[],"merge_approved":"abc123","merge_approved_at":"2026-11-06T01:00:00+08:00"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(gg Bash "$(cmdj 'glab mr merge 212 --squash')")"; assert_eq "$(decision "$out")" deny "grant: dispatch.json 的 merge_approved 不放行"
reason "$out" | grep -q '看板' || fail "grant: 偽造核准的 deny 也要指向看板: $(reason "$out")"
# 受保護目錄不存在、檔案壞掉：都是沒核准
rm -rf "$PD"
out="$(gg Bash "$(cmdj 'glab mr merge 212 --squash')")"; assert_eq "$(decision "$out")" deny "grant: 受保護位置缺檔 deny"
mkdir -p "$PD"; printf 'not json {' > "$PD/authz.json"
out="$(gg Bash "$(cmdj 'glab mr merge 212 --squash')")"; assert_eq "$(decision "$out")" deny "grant: 受保護檔壞掉 deny"
printf '{"Agentory-AI/eval-core":{"merge_approved":"abc123","merge_approved_at":"2026-11-06T01:00:00+08:00"}}' > "$PD/authz.json"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(gg Bash "$(cmdj 'glab mr merge 212 --squash')")"; assert_eq "$(decision "$out")" allow "grant: 核准相符放行"
assert_eq "$(jq -r '."Agentory-AI/eval-core".merge_approved' "$PD/authz.json")" abc123 "核准綁 sha，不刪"
out="$(gg Bash "$(cmdj 'glab mr merge 212 --squash')")"; assert_eq "$(decision "$out")" allow "grant: 同 sha 第二次仍放行"
out="$(gg Bash "$(cmdj 'glab mr merge --squash')")"; assert_eq "$(decision "$out")" allow "grant: 沒寫號碼（目前分支）也放行"
out="$(gg Bash "$(cmdj 'glab mr merge --squash 212')")"; assert_eq "$(decision "$out")" allow "grant: 旗標在前、號碼對也放行"
# 核准在手時，指令仍要整條就是核准的那個 merge：旗標在前的別條 MR、-R 指別的專案、單一 & 或換行夾帶別的指令都 deny
for bad in 'glab mr merge --squash 999' 'glab mr merge -R other/proj 5' 'glab mr merge 212 --squash & glab api -X PUT projects/1/merge_requests/999/merge' $'glab mr merge 212 --squash\nglab api -X PUT projects/1/merge_requests/999/merge'; do
  out="$(gg Bash "$(cmdj "$bad")")"; assert_eq "$(decision "$out")" deny "grant: 核准在手也不放行：$bad"
done
# 夾帶別的指令、合併別的 MR：deny
out="$(gg Bash "$(cmdj 'glab mr merge 212 --squash && git push --force origin main')")"; assert_eq "$(decision "$out")" deny "grant: 複合指令 deny"
out="$(gg Bash "$(cmdj 'git push origin HEAD; glab mr merge 212')")"; assert_eq "$(decision "$out")" deny "grant: 分號串接 deny"
out="$(gg Bash "$(cmdj 'glab mr merge 999 --squash')")"; assert_eq "$(decision "$out")" deny "grant: 別的 MR 號碼 deny"
reason "$out" | grep -q '999' || fail "grant: 要指出號碼不同: $(reason "$out")"
out="$(gg Bash "$(cmdj 'glab mr merge 212 && git push --force origin main')")"; assert_eq "$(decision "$out")" deny
# 「這次」授權：repo 永遠關掉，只靠 once
printf '[repos."Agentory-AI"]\npush = false\n' > "$OPSX_STATE_DIR/grants.toml"
# dispatch.json 偽造的 once / grants 不放行
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":["push"],"once":["push"]}}' > "$OPSX_STATE_DIR/dispatch.json"; printf '{}' > "$PD/authz.json"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" deny "grant: dispatch.json 的 once / grants 不放行"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '{"Agentory-AI/eval-core":{"once":["push"]}}' > "$PD/authz.json"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" allow "grant: once 放行一次"
assert_eq "$(jq -c '."Agentory-AI/eval-core".once' "$PD/authz.json")" '[]' "once 用掉就刪"
printf '{"Agentory-AI/eval-core":{"grants":["mr"]}}' > "$PD/authz.json"
out="$(gg Bash "$(cmdj 'glab mr create -F desc.md')")"; assert_eq "$(decision "$out")" allow "grant: 受保護位置的卡授權放行"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" deny "grant: once 第二次 deny"
# grants.toml 壞掉：當成沒授權，不是放行
printf 'this is not toml ===\n' > "$OPSX_STATE_DIR/grants.toml"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" deny "grant: 壞 toml deny"
printf '[repos."Agentory-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
# 在 dispatch 開的 linked worktree 裡：repo 名要是主 repo，gate 照樣生效
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"; printf '{}' > "$PD/authz.json"
git -C "$R" worktree add -q "$R/.claude/worktrees/eval-core" -b feat/eval-core/wt   # 主 checkout 已在 mikaela 那條，worktree 另開一條同 slug 的
WT="$(cd "$R/.claude/worktrees/eval-core" && pwd -P)"
out="$(run_hook opsx-grant-gate.sh "$(j "$WT" Bash "$(cmdj 'glab mr create -F desc.md')")")"; assert_eq "$(decision "$out")" deny "grant: worktree 裡也要 deny"
out="$(run_hook opsx-grant-gate.sh "$(j "$WT" Bash "$(cmdj 'pnpm test')")")"; assert_eq "$(decision "$out")" allow
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '{"Agentory-AI/eval-core":{"merge_approved":"abc123"}}' > "$PD/authz.json"
out="$(run_hook opsx-grant-gate.sh "$(j "$WT" Bash "$(cmdj 'glab mr merge 212 --squash')")")"; assert_eq "$(decision "$out")" allow "grant: worktree 裡核准相符放行"
# MR 又推了新 commit → deny，核准保留
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"def456","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
out="$(gg Bash "$(cmdj 'glab mr merge 212')")"; assert_eq "$(decision "$out")" deny "grant: sha 不符 deny"
reason "$out" | grep -q '看板' || fail "grant: deny 要指向看板的合併按鈕: $(reason "$out")"
assert_eq "$(jq -r '."Agentory-AI/eval-core".merge_approved' "$PD/authz.json")" abc123 "不符時核准不動"
# 沒有核准 → deny
printf '{}' > "$PD/authz.json"
out="$(gg Bash "$(cmdj 'gh pr merge 12 --squash')")"; assert_eq "$(decision "$out")" deny "grant: 沒核准 deny"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":["migrate"]}}' > "$OPSX_STATE_DIR/dispatch.json"; rm -f "$C/report.md"

# ---------- grant gate：對不到卡（grant-gate-unmapped-branch）----------
# subagent 的 worktree-agent-<id> 與 fanout 子分支 feat/<主>--<子>/<user> 對不到 dispatch.json 的卡
git -C "$R" worktree add -q "$R/.claude/worktrees/agent-x" -b worktree-agent-x
git -C "$R" worktree add -q "$R/.claude/worktrees/bt-as" -b feat/bt--as/u
UW1="$(cd "$R/.claude/worktrees/agent-x" && pwd -P)"; UW2="$(cd "$R/.claude/worktrees/bt-as" && pwd -P)"
ugg() { run_hook opsx-grant-gate.sh "$(j "$1" Bash "$(cmdj "$2")")"; }
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(ugg "$UW1" 'git push --force origin main')"; assert_eq "$(decision "$out")" deny "unmapped: worktree-agent 分支 force-push main"
reason "$out" | grep -q '第三級' || fail "unmapped: 要說第三級: $(reason "$out")"
out="$(ugg "$UW2" 'glab mr merge 212')"; assert_eq "$(decision "$out")" deny "unmapped: fanout 子分支 merge"
out="$(ugg "$UW2" 'git push origin HEAD')"; assert_eq "$(decision "$out")" allow "unmapped: 第二級放行"
out="$(run_hook opsx-grant-gate.sh "$(j "$UW1" Write '{"file_path":"/x/.gitlab-ci.yml","content":"a"}')")"; assert_eq "$(decision "$out")" deny "unmapped: 改 CI 第三級"
out="$(run_hook opsx-grant-gate.sh "$(j "$UW1" Write '{"file_path":"/x/.env.local","content":"A=1"}')")"; assert_eq "$(decision "$out")" allow "unmapped: 寫 .env 屬第二級放行"
printf '{"Agentory-AI/eval-core":{"mode":"stopped"},"Agentory-AI/x":{"mode":"interactive"},"Other/y":{"mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(ugg "$UW1" 'git push --force origin main')"; assert_eq "$(decision "$out")" allow "unmapped: repo 沒有在跑的卡就放行"
printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(ugg "$UW1" 'git push --force origin main')"; assert_eq "$(decision "$out")" allow "unmapped: 空 dispatch.json 放行"
rm -f "$OPSX_STATE_DIR/dispatch.json"
out="$(ugg "$UW1" 'git push --force origin main')"; assert_eq "$(decision "$out")" allow "unmapped: 沒有 dispatch.json 放行"
printf 'not json' > "$OPSX_STATE_DIR/dispatch.json"
out="$(ugg "$UW1" 'git push --force origin main')"; assert_eq "$(decision "$out")" allow "unmapped: dispatch.json 壞掉且沒有這個 repo 的卡，放行"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot"' > "$OPSX_STATE_DIR/dispatch.json"
out="$(ugg "$UW1" 'git push --force origin main')"; assert_eq "$(decision "$out")" deny "unmapped: dispatch.json 壞掉且有這個 repo 的卡，先擋"
printf '{"Agentory-AI/bt":{"mode":"autopilot"' > "$OPSX_STATE_DIR/dispatch.json"
out="$(ugg "$UW2" 'git push --force origin main')"; assert_eq "$(decision "$out")" deny "unmapped: 有 slug 的分支，壞掉的 dispatch.json 裡有這張卡的 key 就擋"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":["migrate"]}}' > "$OPSX_STATE_DIR/dispatch.json"

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
out="$(mg 'opsx answer s g1 -- "之後用 gh pr create 開 MR"')"; assert_eq "$out" "" "mr: 雙引號內的字樣不觸發"
out="$(mg "opsx answer s g1 -- 'glab mr create 之後再開'")"; assert_eq "$out" "" "mr: 單引號內的字樣不觸發"
out="$(mg 'echo "it'"'"'s gh pr create"')"; assert_eq "$out" "" "mr: 雙引號內含單引號的字樣不觸發"
out="$(mg 'cat > inbox.md <<'"'EOF'"'
用 glab mr create 開 MR
EOF')"; assert_eq "$out" "" "mr: heredoc 內的字樣不觸發"
out="$(mg 'cd x && glab mr create -F bad.md')"; assert_eq "$(decision "$out")" deny "mr: && 之後的 create 仍檢查"
out="$(mg 'gh pr create --title "it'"'"'s" --body "just text"')"; assert_eq "$(decision "$out")" deny "mr: 引號內含單引號不讓真的 create 漏掉"
out="$(mg "echo it's ok; if true; then gh pr create --fill --title 'x'; fi")"; assert_eq "$(decision "$out")" deny "mr: 未配對撇號與 then 之後的 create 不漏檢"
out="$(mg 'gh pr create --title t --body "$(cat <<'"'EOF'"'
## Changes

| 編號 | 程式碼改動 | 業務層邏輯 | 對應測試 |
| 1 | a | b | c |
EOF
)"')"; assert_eq "$(decision "$out")" allow "mr: --body \$(cat <<EOF) 合格仍放行"
out="$(mg 'gh pr create --title t --body "$(cat <<'"'EOF'"'
just text
EOF
)"')"; assert_eq "$(decision "$out")" deny "mr: --body \$(cat <<EOF) 不合格仍擋"

# ---------- gate-timestamp ----------
# 有 open 的 gate 時 hook 會叫 $CLAUDE_PLUGIN_ROOT/bin/opsx coordinate --kick：換成假的 plugin 根，bin/opsx 是 fake，記到 kick.log
GP="$FX/gate-plugin"; mkdir -p "$GP/bin/lib"; cp "$OPSX_ROOT/bin/lib/common.sh" "$GP/bin/lib/"
printf '#!/usr/bin/env bash\nOPSX_FAKE_LOG="%s" exec bash "%s/tests/fakes/opsx" "$@"\n' "$FX/kick.log" "$OPSX_ROOT" > "$GP/bin/opsx"
KL="$FX/kick.log"; : > "$KL"
gt() { printf '{"cwd":"%s","tool_name":"%s","tool_input":{"file_path":"%s"},"hook_event_name":"PostToolUse"}' "$R" "${2:-Write}" "$1" | CLAUDE_PLUGIN_ROOT="$GP" OPSX_NOW=2026-11-06T14:05:00+08:00 bash "$H/gate-timestamp.sh" 2>/dev/null; echo "rc=$?"; }
# gt 但連 stderr 一起收：「沒有輸出」要連 stderr 都沒有
gt_all() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "${2:-Write}" "$1" | CLAUDE_PLUGIN_ROOT="$GP" OPSX_NOW=2026-11-06T14:05:00+08:00 bash "$H/gate-timestamp.sh" 2>&1; echo "rc=$?"; }
G="$C/gates.md"
assert_eq "$(jq -r '.hooks.PostToolUse[] | select(.matcher=="Edit|Write") | .hooks[].command' "$OPSX_ROOT/hooks/hooks.json")" '"${CLAUDE_PLUGIN_ROOT}/hooks/gate-timestamp.sh"' "gate-ts: hooks.json 要把它註冊在 PostToolUse 的 Edit|Write"
[ -x "$OPSX_ROOT/hooks/gate-timestamp.sh" ] || fail "gate-ts: hook 要可執行"
printf 'intro\n\n## g1\ntype: decision\nstatus: open\n問題: 哪個？\n' > "$G"
out="$(gt "$G")"; assert_eq "$out" "rc=0" "gate-ts: 沒有輸出"
assert_eq "$(cat "$G")" "$(printf 'intro\n\n## g1\ntype: decision\nstatus: open\nopened_at: 2026-11-06T14:05:00+08:00\n問題: 哪個？')" "gate-ts: 補上缺的時間"
printf '## g1\nstatus: open\nopened_at: 2026-11-01T09:00:00+08:00\n\n## g2\ntype: approval\nstatus:\topen\n問題: push？\n\n## g3\nstatus: answered\nanswer: A\n' > "$G"
gt "$G" Edit >/dev/null
assert_eq "$(cat "$G")" "$(printf '## g1\nstatus: open\nopened_at: 2026-11-01T09:00:00+08:00\n\n## g2\ntype: approval\nstatus:\topen\nopened_at: 2026-11-06T14:05:00+08:00\n問題: push？\n\n## g3\nstatus: answered\nanswer: A')" "gate-ts: 已有時間與 answered 不動，只補 g2"
printf '## g3\nstatus: answered\n' > "$G"; touch -t 202601010000 "$G"; before="$(ls -lT "$G")"
gt "$G" >/dev/null; assert_eq "$(ls -lT "$G")" "$before" "gate-ts: 沒有要補的不寫回"
printf '## g1\nstatus: open (等 push 授權)\n' > "$G"; gt "$G" >/dev/null
assert_eq "$(cat "$G")" "$(printf '## g1\nstatus: open (等 push 授權)')" "gate-ts: status 帶註記不算 open（跟 stop-gate 一致）"
printf '## g1\nstatus: open\n' > "$C/tasks.md"; out="$(gt "$C/tasks.md")"
assert_eq "$out" "rc=0" "gate-ts: 不是 gates.md 沒輸出"
assert_eq "$(cat "$C/tasks.md")" "$(printf '## g1\nstatus: open')" "gate-ts: 不是 gates.md 不動"
rm -f "$G"; out="$(gt "$G")"; assert_eq "$out" "rc=0" "gate-ts: 檔案不存在不擋"
[ ! -e "$G" ] || fail "gate-ts: 不存在的檔不該被建出來"
printf '## g1\nstatus: open\n' > "$G"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$G" | CLAUDE_PLUGIN_ROOT="$GP" env -u OPSX_NOW bash "$H/gate-timestamp.sh" >/dev/null 2>&1
grep -Eq '^opened_at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$' "$G" || fail "gate-ts: 真時間要是帶冒號 offset 的 ISO：$(cat "$G")"

# gate type：同義詞改正、表外與沒寫只提醒（gate-type-normalize）。提醒走 PostToolUse 的 additionalContext，退出碼永遠 0
gts() { printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s"},"hook_event_name":"PostToolUse"}' "$R" "$1" | OPSX_NOW=2026-11-06T14:05:00+08:00 bash "$H/gate-timestamp.sh" 2>/dev/null; }
printf '## g1\ntype: authorization\nneeds: run\nstatus: answered\n\n## g2\ntype: 等待授權\nstatus: answered\n\n## g3\ntype:  Decision \nstatus: answered\n\n## g4\ntype: 決定\nstatus: answered\n\n## g5\ntype: approval\nstatus: answered\n' > "$G"
out="$(gts "$G")"; assert_eq "$out" "" "gate-type: 同義詞改正不出聲"
assert_eq "$(cat "$G")" "$(printf '## g1\ntype: approval\nneeds: run\nstatus: answered\n\n## g2\ntype: approval\nstatus: answered\n\n## g3\ntype: decision\nstatus: answered\n\n## g4\ntype: decision\nstatus: answered\n\n## g5\ntype: approval\nstatus: answered')" "gate-type: 同義詞改正，needs 與其他行不動"
printf '## g1\ntype: approval-ish\nstatus: open\n問題: x\n\n## g2\nstatus: open\n問題: 沒寫\n\n## g3\nstatus: answered\n\n## g4\ntype: decision\nstatus: open\n' > "$G"; cp "$G" "$FX/gt-before.md"
out="$(gts "$G")"; assert_eq "$(cmp -s "$G" "$FX/gt-before.md" && echo same)" "" "gate-type: 表外與沒寫的 type 要補 opened_at 但不改 type"
assert_eq "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out")" PostToolUse
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
for want in g1 approval-ish 'approval | decision' g2 '沒寫 type' 'needs: run'; do case "$ctx" in *"$want"*) ;; *) fail "gate-type: 提醒要含「${want}」：$ctx" ;; esac; done
case "$ctx" in *g3*|*g4*) fail "gate-type: answered 與合法的 gate 不該被提醒：$ctx" ;; esac
assert_eq "$(grep -c '^type: approval-ish$' "$G")" 1 "gate-type: 表外的值原樣保留"
printf '## g1\ntype: approval-ish\nstatus: open\n' > "$G"; printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$G" | OPSX_NOW=2026-11-06T14:05:00+08:00 bash "$H/gate-timestamp.sh" >/dev/null 2>&1
assert_eq "$?" 0 "gate-type: 提醒時退出碼仍是 0"
# 兩份同義詞表一致：hook 的 SYN 與 bin/lib/gatetype.py 的 SYNONYMS
hook_tbl="$(sed -n "s/^SYN='\(.*\)'$/\1/p" "$H/gate-timestamp.sh" | tr ' ' '\n' | sort)"
py_tbl="$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c 'import os,sys;sys.path.insert(0,os.environ["OPSX_LIB"]);import gatetype;print("\n".join("%s=%s"%kv for kv in gatetype.SYNONYMS.items()))' | sort)"
[ -n "$hook_tbl" ] || fail "gate-type: 在 hook 裡找不到 SYN= 那一行"
assert_eq "$hook_tbl" "$py_tbl" "gate-type: hook 與 python 的同義詞表要一致"
rm -f "$G" "$C/tasks.md"

# gate 寫入觸發一輪
printf '## g1\ntype: decision\nstatus: open\n問題: 哪個？\n' > "$G"; : > "$KL"
out="$(gt_all "$G")"; assert_eq "$out" "rc=0" "gate-ts kick: 退出碼 0、沒有輸出"
assert_eq "$(cat "$KL")" "opsx coordinate --kick" "gate-ts kick: 有 open 的 gate 要 kick 一次"
# 已經補過 opened_at、檔案沒變，還有 open 的 gate 照樣 kick
: > "$KL"; out="$(gt_all "$G" Edit)"; assert_eq "$out" "rc=0"
assert_eq "$(cat "$KL")" "opsx coordinate --kick" "gate-ts kick: 沒補時間也要 kick"
# 都答完了不觸發
printf '## g1\nstatus: answered\nanswer: A\n' > "$G"; : > "$KL"
out="$(gt_all "$G" Edit)"; assert_eq "$out" "rc=0"
assert_not_grep coordinate "$KL"
# status 帶註記不算 open、不是 gates.md、檔案不存在都不觸發
printf '## g1\nstatus: open (等 push 授權)\n' > "$G"; gt "$G" >/dev/null
printf '## g1\nstatus: open\n' > "$C/tasks.md"; gt "$C/tasks.md" >/dev/null
rm -f "$G"; gt "$G" >/dev/null
assert_eq "$(cat "$KL")" "" "gate-ts kick: 沒有 open 的 gate 不叫 coordinate"
# kick 失敗不擋 agent
printf '## g1\ntype: decision\nstatus: open\n' > "$G"
out="$(OPSX_TEST_FAIL_coordinate="kick boom" gt_all "$G")"; assert_eq "$out" "rc=0" "gate-ts kick 失敗: 退出碼 0、沒有輸出"
assert_grep '^opsx coordinate --kick$' "$KL"
assert_grep '^opened_at: 2026-11-06T14:05:00+08:00$' "$G"
rm -f "$G" "$C/tasks.md"

# ---------- security guard：路徑不算 AI 署名 ----------
sd() { run_hook security-guard.sh "$(j "$R" Bash "$(cmdj "$1")")"; }
# 路徑含 claude、message 乾淨 → 放行
out="$(sd 'cd /private/tmp/claude-502/x && git commit -m "fix: clean"')"; assert_eq "$(decision "$out")" allow "guard: 絕對路徑"
out="$(sd 'cd .claude/worktrees/x && git commit -m "fix: clean"')"; assert_eq "$(decision "$out")" allow "guard: cd 相對路徑"
out="$(sd 'cd claude-wt && git commit -m "fix: clean"')"; assert_eq "$(decision "$out")" allow "guard: cd 後的目錄名"
out="$(sd 'git -C claude-wt commit -m "fix: clean"')"; assert_eq "$(decision "$out")" allow "guard: -C 後的目錄名"
out="$(sd 'git add skills/claude-x.md && git commit -m "fix: clean"')"; assert_eq "$(decision "$out")" allow "guard: 檔名含 claude"
out="$(sd 'git commit -F /private/tmp/claude-502/msg.txt')"; assert_eq "$(decision "$out")" allow "guard: -F 路徑含 claude"
# 署名寫法 → 擋（舊版擋得到的都要擋得到）
out="$(sd 'git commit -m "feat: x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"')"; assert_eq "$(decision "$out")" deny "guard: -m 含署名"
reason "$out" | grep -q Claude || fail "guard: 理由要提到 Claude"
out="$(sd 'cd /private/tmp/claude-502/x && git commit -m "Generated with Claude"')"; assert_eq "$(decision "$out")" deny "guard: 路徑含 claude 且 message 含署名"
out="$(sd 'git commit -m x --trailer "Co-authored-by: Claude"')"; assert_eq "$(decision "$out")" deny "guard: --trailer"
out="$(sd 'git commit -m x --author="Claude <a@b.c>"')"; assert_eq "$(decision "$out")" deny "guard: --author"
out="$(sd 'GIT_AUTHOR_NAME=Claude git commit -m x')"; assert_eq "$(decision "$out")" deny "guard: GIT_AUTHOR_NAME"
out="$(sd 'git commit --mes "Co-Authored-By: Claude"')"; assert_eq "$(decision "$out")" deny "guard: 長旗標縮寫"
out="$(sd 'git commit --author ";" -m "Co-Authored-By: Claude"')"; assert_eq "$(decision "$out")" deny "guard: 引號內的分隔字元"
out="$(sd 'bash -c "git add a && git commit -m '"'"'Co-Authored-By: Claude'"'"'"')"; assert_eq "$(decision "$out")" deny "guard: bash -c"
out="$(sd 'printf "Co-Authored-By: Claude" | git commit -F -')"; assert_eq "$(decision "$out")" deny "guard: -F - 加 pipe"
out="$(sd 'git commit -m "$(cat <<'"'"'EOF'"'"'
feat: x

Co-Authored-By: Claude
EOF
)"')"; assert_eq "$(decision "$out")" deny "guard: heredoc"

# ---------- stop gate ----------
STOP_STATE="$OPSX_STATE_DIR/stop-chain"
# 每次呼叫先清擋的次數；要測次數的 case 用 KEEP=1 sg 保留
sg() { [ -n "${KEEP:-}" ] || rm -rf "$STOP_STATE"; printf '{"cwd":"%s","stop_hook_active":%s}' "$R" "${1:-false}" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
done_report() { printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/a/b/-/merge_requests/212 · opened 2026-11-10 · auto-merge: no\nbabysit: 2026-11-10T14:00:00+08:00\n' > "$C/report.md"; }
printf '## 1. x\n\n- [x] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 有未勾"; reason "$out" | grep -q '1 個 task 沒勾' || fail "stop: 沒 gates.md 要說幾個 task 沒勾"
out="$(sg true)"; assert_eq "$(decision "$out")" block "stop: stop_hook_active 不再是放行條件"
printf '## real-herdr\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$out" "" "stop: 有未勾但有 open gate 放行"
printf '## real-herdr\nstatus: answered\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: gate 都 answered 仍擋未勾"; reason "$out" | grep -q '1 個 task 沒勾' || fail "stop: answered gate 要說幾個 task 沒勾"
printf '## real-herdr\nstatus: open (等 push 授權)\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: status 帶註記不算 open"; reason "$out" | grep -q '1 個 task 沒勾' || fail "stop: 帶註記的 gate 要說幾個 task 沒勾"
printf '## real-herdr\nstatus:\topen\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$out" "" "stop: status 冒號後 tab 也算 open"
printf '## 1. x\n\n- [x] 1.1 a\n- [x] 1.2 b\n' > "$C/tasks.md"
printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"red","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: tests red"; reason "$out" | grep -q 'opsx status apply' || fail "stop: 要印出 opsx status apply 指令"
printf '## real-herdr\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: open gate 不放行 tests red"; reason "$out" | grep -q green || fail "stop: open gate 下也要說要綠"
rm -f "$C/gates.md"
printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
rm -f "$C/report.md"; out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 沒 report"; reason "$out" | grep -q '/review' || fail "stop: 要叫跑 review"
done_report; sleep 1
out="$(sg)"; assert_eq "$out" "" "stop: 全齊放行"
git -C "$R" commit -q --allow-empty -m "feat: later"   # report 之後又 commit
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: report 後有新 commit"
# report 在、卡的階段是 babysit，但 hook 要的是 /review：擋滿後的 gate 要指 /review，不指 /babysit
rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
out="$(KEEP=1 sg)"; assert_eq "$out" "" "stop: report 後有新 commit 擋滿後放行"
assert_grep '^## 卡在接 /review' "$C/gates.md"; assert_not_grep '卡在接 /babysit' "$C/gates.md"
rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
# reviewer 在背景跑（status.json 是 review 且步數未到最後一步）：主 agent 結束 turn 不是沒接下一站，不計次、不寫 gate
printf '{"phase":"review","step":2,"total":7,"label":"三個 reviewer 已派出","tests":"green","at":"2026-11-10T14:28:10+08:00"}' > "$C/status.json"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
assert_eq "$out" "" "stop: reviewer 在跑連停五次都放行"
assert_eq "$([ -e "$C/gates.md" ] && echo y || echo n)" n "stop: reviewer 在跑不寫「卡在接 /review」gate"
assert_eq "$([ -e "$STOP_STATE/Agentory-AI-eval-core" ] && echo y || echo n)" n "stop: reviewer 在跑不留擋的次數"
# review 走到最後一步仍沒有 report.md：不再是「在等 reviewer」，照擋
printf '{"phase":"review","step":7,"total":7,"label":"report.md 寫好","tests":"green","at":"2026-11-10T14:40:00+08:00"}' > "$C/status.json"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: review 最後一步 report 後有新 commit 照擋"
printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
# 子 change 的 subagent 在背景做：主殼未勾但只能等通知，不計次、不寫 gate
mk_sub() { # <子> <worker> <at>
  local s="$C/subs/$1"; mkdir -p "$s/specs/x"
  printf 'schema: opsx\nparent: eval-core\n' > "$s/.openspec.yaml"
  printf '## Why\n' > "$s/proposal.md"; printf '## Context\n' > "$s/design.md"
  printf '## 1. a\n\n- [ ] 1.1 t\n  - 驗收：a\n  - 測試：b\n' > "$s/tasks.md"
  printf '### Requirement: r\n\n#### Scenario: s\n' > "$s/specs/x/spec.md"
  printf '{"phase":"apply","step":0,"total":4,"label":"x","tests":"unknown","at":"%s","worker":"%s"}' "$3" "$2" > "$s/status.json"
}
FRESH="$( source "$OPSX_ROOT/bin/lib/common.sh"; now_iso )"
printf '## 1. x\n\n- [ ] 1.1 `attach-cli`：a\n- [x] 1.2 `attach-board`：b\n' > "$C/tasks.md"
mk_sub attach-cli subagent-attach-cli "$FRESH"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
assert_eq "$out" "" "stop: subagent 在做未疊的子 change，連停五次都放行"
assert_eq "$([ -e "$C/gates.md" ] && echo y || echo n)" n "stop: subagent 在做不寫「卡在接 /apply」gate"
assert_eq "$([ -e "$STOP_STATE/Agentory-AI-eval-core" ] && echo y || echo n)" n "stop: subagent 在做不留擋的次數"
printf '## 1. x\n\n- [x] 1.1 `attach-cli`：a\n- [ ] 1.2 `attach-board`：b\n' > "$C/tasks.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 子 change 已疊（主殼已勾）、沒有別的 subagent 在跑"; reason "$out" | grep -q '1 個 task 沒勾' || fail "stop: 已疊要說幾個 task 沒勾"
mk_sub attach-board subagent-attach-board "$FRESH"
out="$(sg)"; assert_eq "$out" "" "stop: 另一個子 change 的 subagent 還在做"
printf '## 1. x\n\n- [ ] 1.1 `attach-cli`：a\n- [x] 1.2 `attach-board`：b\n' > "$C/tasks.md"
mk_sub attach-cli subagent-attach-cli "2020-01-01T00:00:00+08:00"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: subagent status 超過 120 分鐘"
mk_sub attach-cli session "$FRESH"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 子殼 worker 是 session"
mk_sub attach-cli subagent-attach-cli "not-a-time"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: at 解析不了照擋"
rm -rf "$C/subs"; rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
# hook 自己寫的「卡在接」gate：建議是選項之一，不是 hook 內部說明
printf '## 1. x\n\n- [ ] 1.1 a\n' > "$C/tasks.md"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
assert_grep '^建議: 重做 /apply 一次，做不完就把卡在哪寫進 gates.md$' "$C/gates.md"
assert_not_grep '先看 pane' "$C/gates.md"
printf '## 1. x\n\n- [x] 1.1 a\n- [x] 1.2 b\n' > "$C/tasks.md"
rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
# 卡在 linked worktree：只算卡自己 branch 的 commit，主 checkout 是別的 session 在用
sgw() { [ -n "${KEEP:-}" ] || rm -rf "$STOP_STATE"; printf '{"cwd":"%s","stop_hook_active":false}' "$WT" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
done_report; sleep 1
git -C "$WT" commit -q --allow-empty -m "feat: card later"
out="$(sgw)"; assert_eq "$(decision "$out")" block "stop: worktree 卡 report 後自己有新 commit"; reason "$out" | grep -q '/review' || fail "stop: worktree 卡要叫重跑 review"
done_report; sleep 1
git -C "$R" commit -q --allow-empty -m "feat: other session"
out="$(sgw)"; assert_eq "$out" "" "stop: worktree 卡不看主 checkout 的新 commit"

# ---------- stop gate：下一站 ----------
rm -f "$C/tasks.md" "$C/report.md" "$C/status.json" "$C/gates.md" "$C/grill.md"
# explore.md 寫好、待決空、沒有 tasks.md → /propose
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: explore 完待決空 → 擋"; reason "$out" | grep -q '/propose' || fail "stop: 要叫 /propose"
# dev 卡待決非空 → /grill
printf '## 已知\n- x\n\n## 待決\n- 選 A 還是 B\n\n## 不做\n' > "$C/explore.md"
printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$C/.openspec.yaml"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: dev 待決非空 → 擋"; reason "$out" | grep -q '/grill' || fail "stop: 要叫 /grill"
# bug-fix 同一張 explore.md → 跳過 grill 直接 /propose
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: bug-fix 待決非空 → 擋"
reason "$out" | grep -q '/propose' || fail "stop: bug-fix 要叫 /propose"
reason "$out" | grep -q '/grill' && fail "stop: bug-fix 不提 /grill"
# 沒有 explore.md → 不擋
mv "$C/explore.md" "$C/explore.md.bak"; out="$(sg)"; assert_eq "$out" "" "stop: 沒 explore.md 不擋"
mv "$C/explore.md.bak" "$C/explore.md"
# 一般 open gate 放行；問「要不要接」的 gate 不算
printf '## 要選 A 還是 B\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$out" "" "stop: chain 站有一般 open gate 放行"
printf '## 要不要接 /propose\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 「要不要接」的 gate 不算 open"; reason "$out" | grep -q '/propose' || fail "stop: 要不要接的 gate 下仍要叫 /propose"
printf '## propose-done\ntype: decision\nstatus: open\n問題: 要不要接 /apply？\n選項: 接 (Recommended) | 不接\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 真實 gate 格式（問題:）問要不要接也不算 open"
printf '## g1\ntype: decision\nstatus: open\n問題: 要不要接受舊版 API 不相容？\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$out" "" "stop: 要不要接受 X 是真的產品問題，算 open"
printf '## merge-head-moved\ntype: approval\naction: merge\nstatus: open\n問題: MR head 變了，要不要繼續？\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$out" "" "stop: approval gate 只有人能答，問要不要繼續也算 open"
# apply 站（tasks.md 一個都沒勾）：「要不要接 /apply」的 gate 不放行，reason 叫 /apply
printf '## 1. x\n\n- [ ] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"
printf '## 要不要接 /apply\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: apply 站「要不要接」gate 不放行"; reason "$out" | grep -q 'invoke /apply' || fail "stop: apply 站 reason 要叫 invoke /apply"
rm -f "$C/gates.md" "$C/tasks.md"

# 擋的次數：同一站 3 次，第 4 次 hook 寫 gate 放行；第 5 次不寫第二個
rm -rf "$STOP_STATE"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: 第 1 次擋"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: 第 2 次擋"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: 第 3 次擋"
assert_no_file "$C/gates.md"
out="$(KEEP=1 sg)"; assert_eq "$out" "" "stop: 第 4 次放行"
assert_grep '^## 卡在接 /propose' "$C/gates.md"; assert_grep '^status: open$' "$C/gates.md"; assert_grep '^opened_at: ' "$C/gates.md"
assert_grep '^type: decision$' "$C/gates.md"; assert_grep '^問題: ' "$C/gates.md"; assert_grep '^選項: ' "$C/gates.md"
assert_eq "$( source "$OPSX_ROOT/bin/lib/stage.sh"; st_open_gates "$C" )" 1 "stop: 自動 gate 被 st_open_gates 數到"
out="$(KEEP=1 sg)"; assert_eq "$out" "" "stop: 第 5 次放行"
assert_eq "$(grep -c '^## 卡在接 /propose' "$C/gates.md")" 1 "stop: 不寫第二個 gate"
# gate 被回答後次數歸零：再擋，不再寫新 gate
sed -i.bak 's/^status: open$/status: answered/' "$C/gates.md"; rm -f "$C/gates.md.bak"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: gate 答完後重新擋"
assert_eq "$(grep -c '^## 卡在接 /propose' "$C/gates.md")" 1 "stop: 答完後第一次擋不寫新 gate"
# 第二輪擋滿：新 gate 的標題要跟答完的不同，opsx answer 才找得到
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
out="$(KEEP=1 sg)"; assert_eq "$out" "" "stop: 第二輪擋滿放行"
assert_grep '^## 卡在接 /propose #1$' "$C/gates.md"; assert_grep '^## 卡在接 /propose #2$' "$C/gates.md"
rm -f "$C/gates.md"
# stop_hook_active 為 true 次數未滿仍擋
out="$(sg true)"; assert_eq "$(decision "$out")" block "stop: stop_hook_active 為 true 仍擋"
# propose 站 commit 不算進度：中間 commit 不能讓次數歸零
rm -rf "$STOP_STATE"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
git -C "$R" commit -q --allow-empty -m "chore: between stops"
out="$(KEEP=1 sg)"
assert_eq "$(cut -d' ' -f1,2 "$STOP_STATE/Agentory-AI-eval-core")" "propose 3" "stop: propose 站 commit 不算進度"
# 站換了從 1 起算
rm -rf "$STOP_STATE"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
assert_eq "$(cut -d' ' -f1,2 "$STOP_STATE/Agentory-AI-eval-core")" "propose 2" "stop: propose 站記 2 次"
printf '## 1. x\n\n- [ ] 1.1 a\n' > "$C/tasks.md"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: 換站後擋"
assert_eq "$(cut -d' ' -f1,2 "$STOP_STATE/Agentory-AI-eval-core")" "apply 1" "stop: 換站從 1 起算"
# 同一站有進度（勾了 task）次數重算，不把有在做事算成「連續卡住」
printf '## 1. x\n\n- [ ] 1.1 a\n- [ ] 1.2 b\n- [ ] 1.3 c\n' > "$C/tasks.md"; rm -rf "$STOP_STATE"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
assert_eq "$(cut -d' ' -f1,2 "$STOP_STATE/Agentory-AI-eval-core")" "apply 2" "stop: 進度前 apply 記 2 次"
printf '## 1. x\n\n- [x] 1.1 a\n- [ ] 1.2 b\n- [ ] 1.3 c\n' > "$C/tasks.md"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: 勾了 task 後仍擋"
assert_eq "$(cut -d' ' -f1,2 "$STOP_STATE/Agentory-AI-eval-core")" "apply 1" "stop: 有進度次數重算"
# 現有檢查共用次數：tests red 擋 3 次，第 4 次寫「卡在接 /apply」
printf '## 1. x\n\n- [x] 1.1 a\n' > "$C/tasks.md"
printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"red","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
rm -rf "$STOP_STATE"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: tests red 第 1 次"; reason "$out" | grep -q green || fail "stop: tests red 要說 green"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: tests red 第 3 次"
out="$(KEEP=1 sg)"; assert_eq "$out" "" "stop: tests red 第 4 次放行"
assert_grep '^## 卡在接 /apply' "$C/gates.md"
# 狀態檔被清掉但 gate 還開著（tests 綠過又紅）：擋滿後不寫第二個
rm -rf "$STOP_STATE"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
out="$(KEEP=1 sg)"; assert_eq "$out" "" "stop: gate 還開著，狀態檔清掉後擋滿也放行"
assert_eq "$(grep -c '^## 卡在接 /apply' "$C/gates.md")" 1 "stop: 狀態檔清掉後不寫第二個 gate"
# gate 開著時再停（gated 路徑）：放行、不寫第二個、狀態不變
out="$(KEEP=1 sg)"; assert_eq "$out" "" "stop: gated 後 gate 還開著放行"
assert_eq "$(cut -d' ' -f1,2,3 "$STOP_STATE/Agentory-AI-eval-core")" "apply 3 gated" "stop: gated 狀態保留"
# 人答完：次數歸零，重新擋，不寫新 gate
sed -i.bak 's/^status: open$/status: answered/' "$C/gates.md"; rm -f "$C/gates.md.bak"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: gate 答完後 apply 站重新擋"
assert_eq "$(cut -d' ' -f1,2 "$STOP_STATE/Agentory-AI-eval-core")" "apply 1" "stop: 答完後次數從 1 起算"
assert_eq "$(grep -c '^## 卡在接 /apply' "$C/gates.md")" 1 "stop: 答完後不寫新 gate"
rm -f "$C/gates.md"

# pr 站：report.md 在、沒有 ## MR
printf '{"phase":"apply","step":8,"total":8,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
printf '# report\n四桶…\n' > "$C/report.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: report 沒 MR → 擋"; reason "$out" | grep -q '/pr' || fail "stop: 要叫 /pr"
printf '# report\n### 待修（範圍內）\n- a.sh:1 task 沒做 · 回 `/apply eval-core` 做完\n### Consider\n' > "$C/report.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 待修（範圍內）有項目 → 擋"; reason "$out" | grep -q '/apply' || fail "stop: 待修要叫 /apply"; reason "$out" | grep -q '/pr' && fail "stop: 待修不叫 /pr"
printf '# report\n### 待修（範圍內）\n### Consider\n- a.sh:1 設計疑問\n' > "$C/report.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 待修空了 → 照一般 pr 站"; reason "$out" | grep -q '/pr' || fail "stop: 待修空了要叫 /pr"
# 確認: <sha>：HEAD 等於該 sha 時 report 之後的新 commit 不要求重審
printf '# report\n### 待修（範圍內）\n' > "$C/report.md"; sleep 1
git -C "$R" commit -q --allow-empty -m "fix: review items"
out="$(sg)"; reason "$out" | grep -q '再跑一次 /review' || fail "stop: 沒有確認行，report 後新 commit 要求重審"
printf '# report\n### 待修（範圍內）\n確認: %s\n' "$(git -C "$R" rev-parse HEAD)" > "$C/report.md"; touch -t 200001010000 "$C/report.md"
out="$(sg)"; reason "$out" | grep -q '/review' && fail "stop: 確認 sha 等於 HEAD 不再要求重審"
git -C "$R" commit -q --allow-empty -m "fix: after confirm"
out="$(sg)"; reason "$out" | grep -q '再跑一次 /review' || fail "stop: 確認後又有新 commit 要重審"
printf '# report\n' > "$C/report.md"
# babysit 站：有 MR 沒有 babysit: 行
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/a/b/-/merge_requests/212 · opened 2026-11-10 · auto-merge: no\n' > "$C/report.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: MR 已開沒 babysit → 擋"; reason "$out" | grep -q '/babysit' || fail "stop: 要叫 /babysit"
done_report
out="$(sg)"; assert_eq "$out" "" "stop: 有 babysit: 行放行"
# 沒有卡的 branch 不擋
git -C "$R" checkout -q -b scratch-x; out="$(sg)"; assert_eq "$out" "" "stop: branch 對不到卡不擋"
git -C "$R" checkout -q "feat/eval-core/mikaela"

# ---------- herdr 佇列（auto-dispatch D5）：PostToolUse 看到 opsx chain 才執行，依序、失敗就停 ----------
use_fakes herdr; export OPSX_FAKE_LOG="$FX/herdr.log"
QD="$OPSX_STATE_DIR/herdr-queue"; mkdir -p "$QD"; CD="$R/openspec/changes/qc"; mkdir -p "$CD"
mkq() { printf 'rename\tp\tqc\nprompt\tqc\t/apply qc\n' > "$QD/Agentory-AI-qc.tsv"; }
post() { printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"hook_event_name":"PostToolUse"}' "$R" "$1" | bash "$H/opsx-herdr-queue.sh" 2>/dev/null; true; }
# 別的指令不碰佇列
mkq; : > "$OPSX_FAKE_LOG"; out="$(post "git status")"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "別的指令不叫 herdr"; assert_file "$QD/Agentory-AI-qc.tsv"
# opsx chain 之後：依序 rename、prompt，佇列清掉
out="$(post "opsx chain p")"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "$(printf 'agent rename p qc\nagent prompt qc /apply qc')" "依序執行佇列"
assert_no_file "$QD/Agentory-AI-qc.tsv"
# herdr 失敗：停在那一步，佇列留成 .failed，decisions 記一行，additionalContext 說失敗
mkq; : > "$OPSX_FAKE_LOG"; out="$(OPSX_TEST_RENAME_FAIL=1 post "opsx chain p")"
assert_not_grep '^agent prompt' "$OPSX_FAKE_LOG"
assert_no_file "$QD/Agentory-AI-qc.tsv"; assert_file "$QD/Agentory-AI-qc.tsv.failed"
assert_grep 'rename' "$CD/decisions.tsv"; assert_grep 'agent_not_found' "$CD/decisions.tsv"
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '失敗' || fail "要用 additionalContext 說失敗: $out"

# ---------- 當前卡：dispatch worktree 根優先，否則 branch 第二段 ----------
K="$(mk_repo Cards)"
mk_change "$K" eval-core; mk_change "$K" other-card; mkdir -p "$K/openspec/changes/eval-core/subs/api"
printf '## 派工指示\n\n- 子殼的指示\n' > "$K/openspec/changes/eval-core/subs/api/inbox.md"
SUBNOTE="派工指示 1 條 · Read $K/openspec/changes/eval-core/subs/api/inbox.md"
git -C "$K" checkout -q -b trunk
git -C "$K" worktree add -q "$K/.claude/worktrees/eval-core" -b feat/core-pr/mikaela
KW="$K/.claude/worktrees/eval-core"
rt() { reason "$(run_hook openspec-router.sh "$(j "$1" "" '{}' "下一步")")"; }
kg() { decision "$(run_hook opsx-grant-gate.sh "$(j "$1" Bash "$(cmdj 'glab mr create -F desc.md')")")"; }
r="$(rt "$KW")"
case "$r" in "opsx："*"· eval-core"*) ;; *) fail "card: worktree 名是卡、branch 第二段不是 → 對到 worktree 的卡: $r" ;; esac
case "$r" in *core-pr*) fail "card: 不該用 branch 第二段 core-pr: $r" ;; esac
mkdir -p "$KW/hooks"
r="$(rt "$KW/hooks")"; case "$r" in "opsx："*"· eval-core"*) ;; *) fail "card: cwd 在 worktree 子目錄: $r" ;; esac
printf '{"Cards/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
assert_eq "$(kg "$KW")" deny "card: authz 閘門在 PR 名不同的 worktree 裡仍生效"
git -C "$KW" checkout -q feat/other-card/mikaela
printf '{"Cards/eval-core":{"mode":"autopilot","grants":[]},"Cards/other-card":{"mode":"interactive","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
# feature session 的形狀：worktree 名是一張卡，branch 已切到另一張卡
r="$(rt "$KW")"; case "$r" in "opsx："*"· other-card"*) ;; *) fail "card: worktree 與 branch 指向不同卡 → 聽 branch: $r" ;; esac
assert_eq "$(kg "$KW")" deny "card: 授權閘門取兩張卡裡受管的那個（worktree autopilot、branch interactive）"
printf '{"Cards/eval-core":{"mode":"interactive","grants":[]},"Cards/other-card":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
assert_eq "$(kg "$KW")" deny "card: 授權閘門取兩張卡裡受管的那個（worktree interactive、branch autopilot）"
git -C "$KW" checkout -q feat/core-pr/mikaela
# 不在 dispatch worktree：主 checkout、名稱對不到卡的 worktree、巢狀在卡 worktree 底下的 subagent worktree
printf '{"Cards/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
git -C "$K" checkout -q feat/eval-core/mikaela
r="$(rt "$K")"; case "$r" in "opsx："*"· eval-core"*) ;; *) fail "card: 主 checkout 照舊用 branch: $r" ;; esac
git -C "$K" checkout -q trunk
git -C "$K" worktree add -q "$K/.claude/worktrees/agent-x" -b feat/eval-core--api/mikaela
r="$(rt "$K/.claude/worktrees/agent-x")"; case "$r" in *"$SUBNOTE"*) ;; *) fail "card: worktree 名對不到卡時用 branch，子殼照舊: $r" ;; esac
assert_eq "$(kg "$K/.claude/worktrees/agent-x")" deny "card: 子殼照主殼的 autopilot"
git -C "$K" worktree add -q "$KW/.claude/worktrees/agent-y" -b feat/eval-core--api/nested
r="$(rt "$KW/.claude/worktrees/agent-y")"; case "$r" in *"$SUBNOTE"*) ;; *) fail "card: 巢狀 subagent worktree 是子殼不是主殼: $r" ;; esac
rm -f "$OPSX_STATE_DIR/dispatch.json"
echo ok
