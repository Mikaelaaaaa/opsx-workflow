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
reason "$out" | grep -qF "Read $OPSX_ROOT/skills/babysit/SKILL.md" || fail "router: 平行流程的 Read 路徑要帶 plugin 根目錄: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "幫我反思一下")")"; reason "$out" | grep -q '平行流程：reflect' || fail "router: 反思 → reflect: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "糾正這個重複犯的錯")")"; reason "$out" | grep -q '平行流程：correct' || fail "router: 糾正 → correct: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "修正這個 bug")")"; reason "$out" | grep -q '平行流程' && fail "router: 一般句子不誤觸平行流程: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "/opsx-workflow:babysit 看一下 MR")")"; reason "$out" | grep -q '平行流程：babysit' || fail "router: 帶前綴的平行流程關鍵詞: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "/opsx-workflow:pickup")")"; reason "$out" | grep -q '平行流程：pickup' || fail "router: 帶前綴、後面沒有空白: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "為什麼 Foo::pause() 和 EventBus::dispatch 沒被呼叫")")"; reason "$out" | grep -q '平行流程' && fail "router: 程式碼裡的 ::kw 不該進平行流程: $(reason "$out")"
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
case "$r" in *'waits-on:'*) ;; *) fail "router: autopilot 規則要教等別張卡的 gate 寫 waits-on: $r" ;; esac
case "$r" in *'action:'*'deny 訊息'*) ;; *) fail "router: autopilot 規則要教授權 gate 寫 action:、值取自 deny 訊息: $r" ;; esac
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

# 沒對到卡時列進行中 change 與下一步（session-change-list）
L="$(mk_repo Listing)"; LC="$L/openspec/changes"
git -C "$L" checkout -q -b main 2>/dev/null || git -C "$L" checkout -q main
mkdir -p "$LC/archive"
lr() { reason "$(run_hook openspec-router.sh "$(j "$L" "" '{}' "hi" "${1:-UserPromptSubmit}")")"; }
assert_eq "$(lr)" "opsx：explore · 沒有對到卡 · 進行中 0 張 · 新工作先建殼 · skills/explore/SKILL.md" "router: 沒有進行中 change"
mkdir -p "$LC/eval-core" "$LC/kb-export"
printf 'schema: opsx\ncreated: 2026-11-05\n' > "$LC/eval-core/.openspec.yaml"
printf '## 1. x\n\n- [ ] 1.1 a\n' > "$LC/eval-core/tasks.md"
printf -- '---\ntype: 功能\n---\n\n## 一句話\n\nx\n' > "$LC/kb-export/inbox.md"
r="$(lr)"
assert_eq "$r" "opsx：explore · 沒有對到卡 · 進行中 2 張：/opsx-workflow:apply eval-core · /opsx-workflow:explore kb-export · 新工作先建殼 · skills/explore/SKILL.md" "router: 沒對到卡列清單"
assert_eq "$(lr SessionStart)" "$r" "router: SessionStart 與 UserPromptSubmit 同一段"
rm -rf "$LC/kb-export"
mkdir -p "$LC/archive/2026-11-01-old" "$LC/big" "$LC/legacy" "$LC/eval-core/subs/core"
printf 'schema: opsx\ncreated: 2026-11-01\n' > "$LC/archive/2026-11-01-old/.openspec.yaml"
printf 'schema: opsx\ncreated: 2026-11-05\n' > "$LC/big/.openspec.yaml"
printf -- '---\ntype: 功能\nsplit_into: a, b\n---\n\n## 一句話\n\nx\n' > "$LC/big/inbox.md"
printf 'schema: spec-driven\ncreated: 2026-10-01\n' > "$LC/legacy/.openspec.yaml"
printf 'schema: opsx\ncreated: 2026-11-05\n' > "$LC/eval-core/subs/core/.openspec.yaml"
r="$(lr)"
case "$r" in *"進行中 1 張：/opsx-workflow:apply eval-core · 新工作先建殼"*) ;; *) fail "router: archive、已拆、舊卡、子殼不列: $r" ;; esac
case "$r" in *old*|*big*|*legacy*|*" core"*|*/core*) fail "router: 清單不該有 old、big、legacy、core: $r" ;; esac
# 對到卡時維持一行
mkdir -p "$LC/kb-export"; printf -- '---\ntype: 功能\n---\n\nx\n' > "$LC/kb-export/inbox.md"
git -C "$L" checkout -q -b feat/eval-core/mikaela
r="$(lr)"
case "$r" in "opsx：apply · eval-core · "*) ;; *) fail "router: 對到卡時維持一行: $r" ;; esac
case "$r" in *進行中*|*kb-export*) fail "router: 對到卡時不附清單: $r" ;; esac

# ---------- commit gate ----------
cg() { run_hook openspec-commit-gate.sh "$(j "$R" Bash "{\"command\":$(printf '%s' "$1" | jq -Rs .)}")"; }
out="$(cg 'git commit -m "feat: x" -- a.ts')"; reason "$out" | grep -q '閘門未啟用' || fail "commit: no workplan → 不擋: $out"
assert_eq "$(decision "$out")" allow
out="$(cg 'git -C "/a b" commit -m x')"; assert_eq "$(decision "$out")" allow "commit: 沒有 workplan 時目錄含空白也不擋"
reason "$out" | grep -q '閘門未啟用' || fail "commit: 沒有 workplan 時目錄含空白要印未啟用: $(reason "$out")"
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
# symlink-safe-writes：bypass.log 是 symlink → 不寫到目標
rm -f "$OPSX_STATE_DIR/bypass.log"; printf 'keep me\n' > "$FX/victim"; ln -s "$FX/victim" "$OPSX_STATE_DIR/bypass.log"
cg 'git commit -m "chore: bump [no-change] 再一次"' >/dev/null 2>&1 || true
assert_eq "$(cat "$FX/victim")" "keep me" "commit: bypass.log 不能附加到 symlink 的目標"
rm -f "$OPSX_STATE_DIR/bypass.log"
# commit-gate-cwd：session cwd 在 main，commit 實際作用的目錄（git -C / cd）在卡的 branch 上 → 看那個目錄
git -C "$R" worktree add -q "$FX/wt" feat/eval-core/mikaela
out="$(cg "git -C $FX/wt commit -m x")"; assert_eq "$(decision "$out")" allow "commit: git -C 指到 worktree 要看 worktree 的 branch"
out="$(cg 'git commit -m x')"; assert_eq "$(decision "$out")" deny "commit: 沒有目錄參數仍看 session cwd"
reason "$out" | grep -q "branch 'main'" || fail "commit: 沒有目錄參數的 deny 要帶 branch 'main': $(reason "$out")"
out="$(cg "cd $FX/wt && git commit -m x")"; assert_eq "$(decision "$out")" allow "commit: cd 進 worktree 再 commit 要看 worktree 的 branch"
out="$(cg "cd $R && git commit -m x")"; assert_eq "$(decision "$out")" deny "commit: cd 進沒有卡的 main 仍擋"
out="$(cg "cd $R && git -C $FX/wt commit -m x")"; assert_eq "$(decision "$out")" allow "commit: -C 優先於 cd"
out="$(cg "cd $FX && git -C wt commit -m x")"; assert_eq "$(decision "$out")" allow "commit: -C 相對路徑以 cd 的目錄為基準"
out="$(cg "cd $FX/wt && git add f && git commit -m x")"; assert_eq "$(decision "$out")" allow "commit: cd 之後還有別的指令仍看 cd 的目錄"
out="$(cg "cd $FX/wt; git commit -m x")"; assert_eq "$(decision "$out")" allow "commit: cd 用 ; 接 commit 也看 cd 的目錄"
out="$(cg "cd $R && git add f && git commit -m x")"; assert_eq "$(decision "$out")" deny "commit: cd 到沒有卡的 main、中間隔著別的指令仍擋"
out="$(cg "git -C $FX/wt commit-tree x && git commit -m y")"; assert_eq "$(decision "$out")" deny "commit: commit-tree 不是 commit，不能拿它的 -C 目錄"
out="$(cg "echo legit commit now; git -C $FX/wt commit -m x")"; assert_eq "$(decision "$out")" allow "commit: legit commit 裡的 git commit 不是 commit，目錄取自真正的 -C"
for c in 'git -C ~/wt commit -m x' 'cd ~/wt && git commit -m x' 'git -C /tmp/a\b commit -m x' 'git -C /tmp/wt-* commit -m x' 'git -C /tmp/wt? commit -m x' 'git -C /tmp/{a,b} commit -m x'; do
  out="$(cg "$c")"; assert_eq "$(decision "$out")" deny "commit: 目錄含 ~、反斜線或萬用字元要 deny（${c}）"
  reason "$out" | grep -qF "$(printf '%s' "$c" | sed -E 's/^.*(-C|cd) ([^ ]+).*$/\2/')" || fail "commit: deny 要點名讀不出來的值（${c}）: $(reason "$out")"
done
out="$(cg 'cd "$A" && git -C "$B" commit -m x')"; assert_eq "$(decision "$out")" deny "commit: cd 與 -C 都讀不出來要 deny"
assert_eq "$(reason "$out" | grep -o '引號包住的路徑' | wc -l | tr -d ' ')" 2 "commit: deny 要兩個值都點名: $(reason "$out")"
for c in 'git -C "/path with space" commit -m x' 'cd "/path with space" && git commit -m x' 'cd $WT && git commit -m x' 'git -C "$WT" commit -m x'; do
  out="$(cg "$c")"; assert_eq "$(decision "$out")" deny "commit: 目錄讀不出來要 deny（${c}）"
  reason "$out" | grep -q '空白' && reason "$out" | grep -q '不含空白的字面路徑' || fail "commit: 目錄讀不出來的 deny 要說明原因與改法（${c}）: $(reason "$out")"
done
git -C "$R" worktree add -q -b feat/no-such-card/mikaela "$FX/wt2"
out="$(cg "git -C $FX/wt2 commit -m x")"; assert_eq "$(decision "$out")" deny "commit: 目標目錄的 branch 對不到卡要擋"
reason "$out" | grep -q 'feat/no-such-card/mikaela' || fail "commit: deny 要帶目標目錄的 branch: $(reason "$out")"
reason "$out" | grep -q "'main'" && fail "commit: deny 不能帶 session cwd 的 branch: $(reason "$out")"
rm -f "$OPSX_STATE_DIR/bypass.log"
cg "git -C $FX/wt2 commit -m 'x [no-change] y'" >/dev/null
assert_grep 'feat/no-such-card/mikaela' "$OPSX_STATE_DIR/bypass.log"
rm -f "$OPSX_STATE_DIR/bypass.log"
git -C "$R" worktree remove --force "$FX/wt2"; git -C "$R" branch -q -D feat/no-such-card/mikaela
git -C "$R" worktree remove --force "$FX/wt"
out="$(cg 'ls -la')"; assert_eq "$out" "" "commit: 非 commit 指令不出聲"
out="$(cg 'echo "之後再 git commit -m x"')"; assert_eq "$out" "" "commit: 引號內的 git commit 不出聲"
out="$(cg 'bash -c "git commit -m x"')"; assert_eq "$(decision "$out")" deny "commit: bash -c 內的 commit 仍擋"
# 三種容器（grill D2）：commit 訊息、opsx answer 答案、寫檔 heredoc 內提到 git commit 不觸發
out="$(cg 'opsx answer s g1 -- "之後再 git commit -m x，不要 git commit --amend"')"; assert_eq "$out" "" "commit: answer 答案文字提到 git commit 不觸發"
out="$(cg 'cat > n.md <<'"'EOF'"'
git commit -m x
EOF')"; assert_eq "$out" "" "commit: 寫檔 heredoc 內提到 git commit 不觸發"
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
# 回 issue 留 MR 連結歸在 mr 底下，不另開 action
out="$(gg Bash "$(cmdj 'glab issue note 12 -m x')")"; assert_eq "$(decision "$out")" deny "grant: glab issue note 沒 mr 授權"
reason "$out" | grep -qF 'action: mr' || fail "grant: issue note 的 deny 要帶 action: mr：$(reason "$out")"
out="$(gg Bash "$(cmdj 'gh issue comment https://github.com/o/r/issues/3 --body x')")"; assert_eq "$(decision "$out")" deny "grant: gh issue comment 沒 mr 授權"
reason "$out" | grep -qF 'action: mr' || fail "grant: issue comment 的 deny 要帶 action: mr：$(reason "$out")"
out="$(gg Bash "$(cmdj 'glab issue comment 12 -m x')")"; assert_eq "$(decision "$out")" deny "grant: glab issue comment 是 note 的別名，沒 mr 授權"
out="$(gg Bash "$(cmdj 'glab issue view 12')")"; assert_eq "$out" "" "grant: glab issue view 不是第二級"
out="$(gg Bash "$(cmdj 'gh issue list')")"; assert_eq "$out" "" "grant: gh issue list 不是第二級"
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
# 字樣只在引號 / heredoc 內 → 不管；字串裡真的在執行的仍照第三級擋
out="$(gg Bash "$(cmdj 'git commit -m "docs: 說明 glab mr merge 與 gh pr merge 的核准流程"')")"; assert_eq "$out" "" "grant: commit 訊息提到 merge 不觸發"
out="$(gg Bash "$(cmdj 'opsx answer s g1 -- "不要 git push --force origin main，也不要 pnpm add x"')")"; assert_eq "$out" "" "grant: answer 文字提到 force-push / 裝套件不觸發"
out="$(gg Bash "$(cmdj 'cat > inbox.md <<'"'EOF'"'
drop table users; deploy.sh; curl https://api.example.com/x; rm -rf /
EOF')")"; assert_eq "$out" "" "grant: heredoc 內的字樣不觸發"
out="$(gg Bash "$(cmdj 'git push gitlab "main"')")"; assert_eq "$(decision "$out")" deny "grant: 引號包住的 main 仍是 push main"
out="$(gg Bash "$(cmdj "git push --force gitlab 'feat/x'")")"; assert_eq "$(decision "$out")" deny "grant: 單引號分支名不讓 force-push 漏掉"
out="$(gg Bash "$(cmdj 'bash -c "glab mr merge 212"')")"; assert_eq "$(decision "$out")" deny "grant: bash -c 內的 merge 仍擋"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela && bash <<EOF
git push --force gitlab main
EOF')")"; assert_eq "$(decision "$out")" deny "grant: 已授權的 push 後面串 bash heredoc 的 force-push 仍擋（本體會被執行）"
out="$(gg Bash "$(cmdj 'echo "$(gh pr merge 12)"')")"; assert_eq "$(decision "$out")" deny "grant: 雙引號內 \$(…) 的 merge 仍擋"
out="$(gg Bash "$(cmdj 'eval "git push --force gitlab main"')")"; assert_eq "$(decision "$out")" deny "grant: eval 內的 force-push 仍擋"
out="$(gg Bash "$(cmdj 'echo ok && sh -c '"'"'pnpm add left-pad'"'"'')")"; assert_eq "$(decision "$out")" deny "grant: sh -c 單引號內的裝套件仍擋"

# 第三級白名單容器（grill D1）：三種容器的資料部分不算，其他寫法一律照原文比對
out="$(gg Bash "$(cmdj 'git commit -m "$(cat <<'"'EOF'"'
fix: glab mr merge、drop table users、git push --force origin main
EOF
)"')")"; assert_eq "$out" "" "grant 白名單: 標準 commit heredoc 寫法不觸發"
out="$(gg Bash "$(cmdj "git commit -m 'it is glab mr merge' -m \"second: git push --force origin main\"")")"; assert_eq "$out" "" "grant 白名單: 多個 -m 不觸發"
out="$(gg Bash "$(cmdj "opsx answer s g1 -- 'glab mr merge 之後再做'")")"; assert_eq "$out" "" "grant 白名單: answer 單引號文字不觸發"
out="$(gg Bash "$(cmdj 'cat > notes.md <<'"'EOF'"'
git push --force origin main
EOF')")"; assert_eq "$out" "" "grant 白名單: cat 寫檔 heredoc（quoted delimiter）不觸發"
out="$(gg Bash "$(cmdj 'cat >> notes.md <<EOF
./deploy.sh spark1-prod
EOF')")"; assert_eq "$out" "" "grant 白名單: cat 寫檔 heredoc（unquoted、沒有命令替換）不觸發"
out="$(gg Bash "$(cmdj 'git commit -m "$(git push --force gitlab main)"')")"; assert_eq "$(decision "$out")" deny "grant 白名單: commit 訊息內的 \$(…) 仍擋"
out="$(gg Bash "$(cmdj 'opsx answer s g1 -- "$(gh pr merge 12)"')")"; assert_eq "$(decision "$out")" deny "grant 白名單: answer 內的 \$(…) 仍擋"
out="$(gg Bash "$(cmdj 'cat > f <<EOF
$(git push --force gitlab main)
EOF')")"; assert_eq "$(decision "$out")" deny "grant 白名單: unquoted heredoc 內的 \$(…) 仍擋"
out="$(gg Bash "$(cmdj 'cat <<EOF | sh
git push --force gitlab main
EOF')")"; assert_eq "$(decision "$out")" deny "grant 白名單: heredoc 接 pipe 進 sh 仍擋"
out="$(gg Bash "$(cmdj 'psql <<SQL
DROP TABLE users;
SQL')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: heredoc 餵 psql"
out="$(gg Bash "$(cmdj 'ssh spark1 bash <<EOF
cd /srv && ./deploy.sh spark1-prod
EOF')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: heredoc 餵 ssh bash"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela && psql -c "DROP TABLE users"')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: 已授權 push 串 psql -c DROP TABLE"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela && ssh spark1 "cd /srv && ./deploy.sh spark1-prod"')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: 已授權 push 串 ssh deploy"
out="$(gg Bash "$(cmdj 'c="git push --force gitlab main"; $c')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: 變數展開"
out="$(gg Bash "$(cmdj 'source <(echo "git push --force gitlab main")')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: source <(…)"
out="$(gg Bash "$(cmdj 'bash -e -c "git push --force gitlab main"')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: bash -e -c"
out="$(gg Bash "$(cmdj 'bash --norc -c "git push --force gitlab main"')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: bash --norc -c"
out="$(gg Bash "$(cmdj 'dash -c "git push --force gitlab main"')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: dash -c"
out="$(gg Bash "$(cmdj 'bash -lc "git push --force gitlab main"')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: bash -lc"
out="$(gg Bash "$(cmdj "bash -c \$'git push --force gitlab main'")")"; assert_eq "$(decision "$out")" deny "grant 繞過口: bash -c \$'…'"
out="$(gg Bash "$(cmdj 'echo "$(echo "a b" ; git push -f gitlab main)"')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: \$(…) 內有帶空白的引號"
out="$(gg Bash "$(cmdj "echo hi # 'x
git push --force gitlab main
echo 'y'")")"; assert_eq "$(decision "$out")" deny "grant 繞過口: 註解內的引號吃掉下一行"
out="$(gg Bash "$(cmdj 'git add ".github/workflows/my ci.yml"')")"; assert_eq "$(decision "$out")" deny "grant 繞過口: 帶空白的引號 CI 路徑"
out="$(gg Bash "$(cmdj 'bash -c "bash -c \"bash -c '"'"'git push --force gitlab main'"'"'\""')")"; assert_eq "$(decision "$out")" deny "grant 遞迴: 3 層巢狀"
out="$(gg Bash "$(cmdj 'bash -c "bash -c \"bash -c '"'"'bash -c \"git push --force gitlab main\"'"'"'\""')")"; assert_eq "$(decision "$out")" deny "grant 遞迴: 4 層巢狀"
out="$(gg Bash "$(cmdj "$(printf 'git push --force gitlab main\r')")")"; assert_eq "$(decision "$out")" deny "grant: CRLF 指令照擋"
out="$(gg Bash '{"command":""}')"; assert_eq "$out" "" "grant: 空指令不出聲"
mkdir -p "$FX/noperl"; printf '#!/usr/bin/env bash\nexit 127\n' > "$FX/noperl/perl"; chmod +x "$FX/noperl/perl"
out="$(PATH="$FX/noperl:$PATH" gg Bash "$(cmdj 'ls')")"; assert_eq "$(decision "$out")" deny "grant: perl 失敗要 deny，不是放行"
reason "$out" | grep -q perl || fail "grant: perl 失敗的 deny 要說是 perl: $(reason "$out")"
mkdir -p "$FX/noperl-l3"
printf '#!/usr/bin/env bash\ncase "$1" in *cmd-containers.pl) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v perl)" > "$FX/noperl-l3/perl"; chmod +x "$FX/noperl-l3/perl"
out="$(PATH="$FX/noperl-l3:$PATH" gg Bash "$(cmdj 'ls')")"; assert_eq "$(decision "$out")" deny "grant: 只有 cmd-containers.pl 失敗也要 deny"

# 白名單容器的「容器本身」不能變成繞過口（review 第 2 輪）：已授權 push 串在前面時閘門會明確 allow，所以每個都要 deny
deny3() { local cmd out; cmd="$(cat)"; out="$(gg Bash "$(cmdj "$cmd")")"; assert_eq "$(decision "$out")" deny "$1"; }
allow3() { local cmd out; cmd="$(cat)"; out="$(gg Bash "$(cmdj "$cmd")")"; assert_eq "$out" "" "$1"; }
deny3 "grant 容器: 引號內的 git commit -m 不是容器" <<'X'
git push gitlab feat/eval-core/mikaela && echo "git commit -m '" && git push --force gitlab main && echo "'"
X
deny3 "grant 容器: eval 後的 git commit -m 不是容器" <<'X'
git push gitlab feat/eval-core/mikaela && eval git commit -m '; git push --force gitlab main'
X
deny3 "grant 容器: 引號內 git commit -m 字串裡的命令替換仍會執行" <<'X'
git push gitlab feat/eval-core/mikaela && echo "git commit -m '$(git push --force gitlab main)'"
X
deny3 "grant 容器: 註解內的 git commit -m 不是容器" <<'X'
git push gitlab feat/eval-core/mikaela
# git commit -m '
git push --force gitlab main
# '
X
deny3 "grant 容器: 引號內的 opsx answer 不是容器" <<'X'
git push gitlab feat/eval-core/mikaela && echo "opsx answer a b -- "; git push --force gitlab main; echo ""
X
deny3 "grant 容器: 同上，換成 merge（merge_gate 也不能被繞過）" <<'X'
git push gitlab feat/eval-core/mikaela && echo "git commit -m '" && glab mr merge 212 && echo "'"
X
deny3 "grant 容器: commit 標準寫法後面緊接命令替換" <<'X'
git commit -m "$(cat <<'EOF'
msg
EOF
)$(git push --force gitlab main)$(cat <<'EOF'
EOF
)"
X
deny3 "grant 容器: commit heredoc 在第一個結尾行就結束，後面的行會執行" <<'X'
git commit -m "$(cat <<'EOF'
msg
EOF
xx; git push -f gitlab main
EOF
)"
X
deny3 "grant 容器: 跨行單引號內的假 heredoc opener" <<'X'
echo '
cat > f <<EOF
'; git push -f gitlab main
EOF
X
deny3 "grant 容器: opener 行尾反斜線續行接 pipe 進 sh" <<'X'
cat <<EOF \
| sh
git push --force gitlab main
EOF
X
deny3 "grant 容器: delimiter 是混合寫法 <<\"E\"OF" <<'X'
cat > f <<"E"OF
x
EOF
git push --force gitlab main
E
X
deny3 "grant 容器: delimiter 是 EOF-1" <<'X'
cat > f <<EOF-1
x
EOF-1
git push --force gitlab main
EOF
X
deny3 "grant 容器: 前面定義了 cat 函式" <<'X'
git push gitlab feat/eval-core/mikaela
cat() { bash; }
cat <<'EOF'
git push --force gitlab main
EOF
X
deny3 "grant 容器: 扣掉 commit 訊息後，串在後面的第三級仍擋" <<'X'
git commit -m 'a' && git push --force gitlab main
X
deny3 "grant 容器: 扣掉 answer 答案後，串在後面的第三級仍擋" <<'X'
opsx answer s --gate g1 'a' ; git push --force gitlab main
X
deny3 "grant 容器: 扣掉 heredoc 本體後，後面的第三級仍擋" <<'X'
cat > f <<'EOF'
x
EOF
git push --force gitlab main
X
allow3 "grant 容器: opsx answer 真實用法（--gate、單引號文字）不觸發" <<'X'
opsx answer s --gate g1 'git push --force gitlab main 之後再說'
X
allow3 "grant 容器: opsx answer 帶 --grant 與雙引號文字不觸發" <<'X'
opsx answer s --gate g1 --grant this "glab mr merge 之後再說"
X
allow3 "grant 容器: cd 之後的 cat heredoc 不觸發" <<'X'
cd x && cat > f <<'EOF'
git push --force gitlab main
EOF
X
big="$(head -c 40000 /dev/zero | tr '\0' a)"
out="$(gg Bash "$(cmdj "git commit -m \"$big git push --force gitlab main\"")")"; assert_eq "$(decision "$out")" deny "grant 容器: 超過長度上限就整段原樣比對（不扣容器）"
many="$(printf 'cat > f <<EOF\n%.0s' $(seq 1 1500))"
out="$(gg Bash "$(cmdj "$many")")"; assert_eq "$(decision "$out")" allow "grant 容器: 一堆沒有結尾的 heredoc opener 不會拖到逾時"

# 第二級 deny 帶精確的 action 值，agent 照抄寫 gate（grant-action）；一個授權都沒有的狀態下九個動作各擋一次
printf '# grants\n' > "$OPSX_STATE_DIR/grants.toml"; printf '{}' > "$PD/authz.json"
for pair in "push|git push gitlab feat/eval-core/mikaela" "mr|glab mr create -F desc.md" "migrate|pnpm db:migrate" "delete|rm -rf build" \
            "install|pnpm add left-pad" "rebase|git rebase main" "external|curl https://api.example.com/x"; do
  out="$(gg Bash "$(cmdj "${pair#*|}")")"; assert_eq "$(decision "$out")" deny "grant-action: ${pair%%|*}"
  reason "$out" | grep -qF "action: ${pair%%|*}" || fail "grant-action: ${pair%%|*} 的 deny 要帶 action: ${pair%%|*}：$(reason "$out")"
  assert_eq "$(reason "$out" | grep -oE 'action: [a-z-]+' | wc -l | tr -d ' ')" 1 "grant-action: ${pair%%|*} 只能帶自己的一個 action"
done
out="$(gg Write '{"file_path":"/x/.env.local","content":"A=1"}')"
reason "$out" | grep -qF "action: env" || fail "grant-action: env 的 deny 要帶 action: env：$(reason "$out")"
out="$(gg Write "{\"file_path\":\"$R/src/newdir/foo.test.ts\",\"content\":\"x\"}")"; assert_eq "$(decision "$out")" deny "grant-action: test-path"
assert_eq "$(reason "$out" | grep -oE 'action: [a-z-]+')" "action: test-path" "grant-action: test-path 只帶自己的 action：$(reason "$out")"
out="$(gg Bash "$(cmdj 'git push --force gitlab main')")"
reason "$out" | grep -qF 'action:' && fail "grant-action: 第三級不帶 action：$(reason "$out")"
printf '[repos."Agentory-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
printf '{"Agentory-AI/eval-core":{"grants":["migrate"]}}' > "$PD/authz.json"

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
out="$(gg Bash "$(cmdj 'glab issue note 12 -m x')")"; assert_eq "$(decision "$out")" allow "grant: mr 授權放行 glab issue note"
out="$(gg Bash "$(cmdj 'gh issue comment https://github.com/o/r/issues/3 --body x')")"; assert_eq "$(decision "$out")" allow "grant: mr 授權放行 gh issue comment"
out="$(gg Bash "$(cmdj 'glab issue comment 12 -m x')")"; assert_eq "$(decision "$out")" allow "grant: mr 授權放行 glab issue comment"
out="$(gg Bash "$(cmdj 'git push gitlab feat/eval-core/mikaela')")"; assert_eq "$(decision "$out")" deny "grant: once 第二次 deny"
# once mr 只放行一次：開 MR 用掉後，回寫 issue 會被擋，deny 訊息帶 action: mr（/pr 5b 靠它分辨原因）
printf '{"Agentory-AI/eval-core":{"once":["mr"]}}' > "$PD/authz.json"
out="$(gg Bash "$(cmdj 'glab mr create -F desc.md')")"; assert_eq "$(decision "$out")" allow "grant: once mr 開 MR"
out="$(gg Bash "$(cmdj 'glab issue note 12 -m x')")"; assert_eq "$(decision "$out")" deny "grant: once mr 用掉後 issue note deny"
reason "$out" | grep -qF 'action: mr' || fail "grant: once mr 用掉後的 deny 要帶 action: mr：$(reason "$out")"
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
printf '{"Agentory-AI/@g":{"mode":"autopilot"},"Agentory-AI/m1":{"mode":"stopped","feature":"g","via":"@g"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(ugg "$UW1" 'git push --force origin main')"; assert_eq "$(decision "$out")" allow "unmapped: session 條目不是卡，成員都停了就放行"
printf '{"Agentory-AI/@g":{"mode":"autopilot"},"Agentory-AI/m1":{"mode":"autopilot","feature":"g","via":"@g"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(ugg "$UW1" 'git push --force origin main')"; assert_eq "$(decision "$out")" deny "unmapped: session 的成員還在跑就照擋"
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

# ---------- grant gate：測試檔放非慣例位置（grant-test-path）----------
# R 的分支追蹤 tests/a.test.sh 與 src/sub/d.test.ts；WT、UW1 的分支在這之前開出來，沒有這兩個檔
tw() { run_hook opsx-grant-gate.sh "$(j "${2:-$R}" Write "{\"file_path\":\"$1\",\"content\":\"x\"}")"; }
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"; printf '{}' > "$PD/authz.json"
mkdir -p "$R/tests" "$R/src/sub" "$R/src/newdir" "$R/lib"
printf 'x\n' > "$R/tests/a.test.sh"; printf 'x\n' > "$R/src/sub/d.test.ts"; printf 'x\n' > "$R/lib/u.test.ts"
git -C "$R" add tests/a.test.sh src/sub/d.test.ts; git -C "$R" commit -q -m "fixture: tests"
out="$(tw "$R/src/newdir/foo.test.ts")"; assert_eq "$(decision "$out")" deny "test-path: 沒有測試的目錄寫測試檔"
reason "$out" | grep -qF 'action: test-path' || fail "test-path: deny 要帶 action: test-path：$(reason "$out")"
reason "$out" | grep -qF 'src/newdir/foo.test.ts' || fail "test-path: deny 要帶檔案路徑：$(reason "$out")"
reason "$out" | grep -qF 'gates.md' || fail "test-path: deny 要叫它寫 gate：$(reason "$out")"
for f in src/newdir/x.spec.ts src/newdir/test_x.py src/newdir/x_test.go; do
  out="$(tw "$R/$f")"; assert_eq "$(decision "$out")" deny "test-path: ${f} 檔名像測試"
done
out="$(tw "$R/nope/deeper/x.test.ts")"; assert_eq "$(decision "$out")" deny "test-path: 目錄還不存在也算沒有測試"
reason "$out" | grep -qF 'action: test-path' || fail "test-path: 不存在的目錄也帶 action: test-path：$(reason "$out")"
out="$(tw "$R/tests/b.test.sh")"; assert_eq "$out" "" "test-path: 有測試的目錄不出聲"
out="$(tw "$R/src/c.test.ts")"; assert_eq "$(decision "$out")" deny "test-path: 只有子目錄有測試不算"
out="$(tw "$R/lib/v.test.ts")"; assert_eq "$(decision "$out")" deny "test-path: 沒被追蹤的測試檔不算慣例"
out="$(tw "$R/src/newdir/helper.ts")"; assert_eq "$out" "" "test-path: 檔名不像測試不管"
out="$(tw "$R/src/newdir/contest.py")"; assert_eq "$out" "" "test-path: contest.py 不是 test_*.py"
ln -s "$R" "$FX/rlink"
out="$(tw "$FX/rlink/src/newdir/foo.test.ts")"; assert_eq "$(decision "$out")" deny "test-path: 經 symlink 寫進 worktree 也要判"
out="$(tw "$FX/rlink/tests/b.test.sh")"; assert_eq "$out" "" "test-path: 經 symlink 寫進有測試的目錄不出聲"
# 相對路徑：hook 不能卡住到逾時（逾時等於放行），要 deny 並點名原值。alarm 讓卡住的 hook 在 10 秒被砍，輸出空字串就算放行
twt() { printf '%s' "$(j "$R" Write "{\"file_path\":\"$1\",\"content\":\"x\"}")" | perl -e 'alarm 10; exec @ARGV' bash "$H/opsx-grant-gate.sh" 2>/dev/null; true; }
for f in x.test.ts src/nope/x.test.ts; do
  out="$(twt "$f")"; assert_eq "$(decision "$out")" deny "test-path: 相對路徑 ${f} 要 deny，不能逾時放行"
  reason "$out" | grep -qF "$f" || fail "test-path: 相對路徑的 deny 要點名 ${f}：$(reason "$out")"
done
# 經 `..` 繞到 worktree 外再繞回來：檔案實際落在 worktree 裡沒有測試的目錄，不能因為往上找存在目錄時爬到外面就放行
dotdot="$(dirname "$R")/nope/../$(basename "$R")/src/newdir/x.test.ts"
out="$(tw "$dotdot")"; assert_eq "$(decision "$out")" deny "test-path: 含 .. 的路徑要 deny"
reason "$out" | grep -qF "$dotdot" || fail "test-path: 含 .. 的 deny 要點名原值：$(reason "$out")"
# 目標目錄還不存在時，上層有被追蹤的測試也不算這一層有
out="$(tw "$R/tests/newsub/x.test.ts")"; assert_eq "$(decision "$out")" deny "test-path: 新子目錄的上層有測試也不算"
# 這一層的被追蹤測試檔排在大量子目錄檔案前面（清單超過 pipe buffer）時仍要放行
mkdir -p "$R/big/sub"; printf 'x\n' > "$R/big/a.test.sh"
( cd "$R/big/sub" && seq -f 'padding-padding-padding-%06g.ts' 1 3000 | xargs touch )
git -C "$R" add big; git -C "$R" commit -q -m "fixture: big dir"
out="$(tw "$R/big/b.test.sh")"; assert_eq "$out" "" "test-path: 有測試的目錄、清單很大也不出聲"
out="$(tw "$R/big/sub/c.test.ts")"; assert_eq "$(decision "$out")" deny "test-path: 大目錄底下只有上層有測試，這一層仍算沒有"
# 進不去的目錄（cd 失敗）不能讓 hook 以非 0 結束而放行
mkdir -p "$R/locked"; chmod 000 "$R/locked"
out="$(tw "$R/locked/x.test.ts")"; chmod 755 "$R/locked"
assert_eq "$(decision "$out")" deny "test-path: 進不去的目錄要 deny"
# 有授權：repo 永遠、這張卡
printf '[repos."Agentory-AI"]\ntest-path = true\n' > "$OPSX_STATE_DIR/grants.toml"
out="$(tw "$R/src/newdir/foo.test.ts")"; assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')" allow "test-path: grants.toml 有授權要明說 allow"
printf '# grants\n' > "$OPSX_STATE_DIR/grants.toml"; printf '{"Agentory-AI/eval-core":{"grants":["test-path"]}}' > "$PD/authz.json"
out="$(tw "$R/src/newdir/foo.test.ts")"; assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')" allow "test-path: 這張卡的授權要明說 allow"
printf '{}' > "$PD/authz.json"
# 只看 hook cwd 所在的 worktree
mkdir -p "$FX/scratch"
out="$(tw "$FX/scratch/x.test.ts")"; assert_eq "$out" "" "test-path: worktree 外的檔不判"
out="$(tw "$WT/src/newdir/x.test.ts")"; assert_eq "$out" "" "test-path: 主 checkout 寫巢狀在底下的別的 worktree 不判"
out="$(tw "$WT/tests/b.test.sh" "$WT")"; assert_eq "$(decision "$out")" deny "test-path: 照 cwd 所在 worktree 的追蹤檔，不是主 repo 的"
out="$(tw "$R/src/newdir/x.test.ts" "$WT")"; assert_eq "$out" "" "test-path: worktree 裡寫主 checkout 的檔不判"
out="$(tw "$UW1/src/newdir/x.test.ts" "$UW1")"; assert_eq "$out" "" "test-path: 對不到卡放行"
printf '{"Agentory-AI/eval-core":{"mode":"interactive","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(tw "$R/src/newdir/foo.test.ts")"; assert_eq "$out" "" "test-path: 互動模式不判"
# 對外發話（grant-outbound-speech）：閘門不判，沒被其他規則分級的發話類指令照舊不出聲
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(gg Bash "$(cmdj 'mail -s "進度" customer@example.com < note.txt')")"; assert_eq "$out" "" "outbound: 寄信的本機 CLI 判定不變"
printf '[repos."Agentory-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
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
out="$(mg 'git commit -m "docs: gh pr create 與 glab mr create 的格式"')"; assert_eq "$out" "" "mr: commit 訊息提到 create 不觸發"
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
# 字串裡真的在執行的指令仍檢查（骨架遞迴）
out="$(mg 'bash -c "gh pr create --fill"')"; assert_eq "$(decision "$out")" deny "mr: bash -c 內的 create 仍擋"
out="$(mg "sh -c 'glab mr create --fill'")"; assert_eq "$(decision "$out")" deny "mr: sh -c 單引號內的 create 仍擋"
out="$(mg 'eval "gh pr create --fill"')"; assert_eq "$(decision "$out")" deny "mr: eval 內的 create 仍擋"
out="$(mg 'echo "$(gh pr create --fill)"')"; assert_eq "$(decision "$out")" deny "mr: 雙引號內 \$(…) 的 create 仍擋"
out="$(mg 'echo "`gh pr create --fill`"')"; assert_eq "$(decision "$out")" deny "mr: 雙引號內反引號的 create 仍擋"
out="$(mg 'echo "$(echo "$(echo "$(echo "$(gh pr create --fill)")")")"')"; assert_eq "$(decision "$out")" deny "mr: 超過 3 層的 create 原樣比對仍擋"
out="$(mg 'echo "$(echo hi) 之後用 gh pr create"')"; assert_eq "$out" "" "mr: 雙引號內 \$(…) 之外的字樣不觸發"
out="$(mg "echo 'gh pr create' | xargs -I{} echo {}")"; assert_eq "$out" "" "mr: 單引號字樣餵 xargs 不觸發"

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
# symlink-safe-writes：暫存檔與 warn 檔名帶 pid（可猜）。exec 保留 pid，所以在同一個 pid 下先放好 symlink
printf '## g1\ntype: decision\nstatus: open\n' > "$G"; printf 'keep me\n' > "$FX/victim"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$G" | CLAUDE_PLUGIN_ROOT="$GP" OPSX_NOW=2026-11-06T14:05:00+08:00 bash -c 'ln -s "$1" "$2.tmp.$$"; ln -s "$1" "$2.warn.$$"; exec bash "$3"' _ "$FX/victim" "$G" "$H/gate-timestamp.sh" >/dev/null 2>&1
assert_eq "$(cat "$FX/victim")" "keep me" "gate-ts: 帶 pid 的舊檔名上的 symlink 不能被寫"
assert_grep '^opened_at: 2026-11-06T14:05:00+08:00$' "$G"
rm -f "$G".tmp.* "$G".warn.*

# gate type：同義詞改正、表外與沒寫只提醒（gate-type-normalize）。提醒走 PostToolUse 的 additionalContext，退出碼永遠 0
gts() { printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s"},"hook_event_name":"PostToolUse"}' "$R" "$1" | CLAUDE_PLUGIN_ROOT="$GP" OPSX_NOW=2026-11-06T14:05:00+08:00 bash "$H/gate-timestamp.sh" 2>/dev/null; }
printf '## g1\ntype: authorization\nneeds: run\nstatus: answered\n\n## g2\ntype: 等待授權\nstatus: answered\n\n## g3\ntype:  Decision \nstatus: answered\n\n## g4\ntype: 決定\nstatus: answered\n\n## g5\ntype: approval\nstatus: answered\n' > "$G"
out="$(gts "$G")"; assert_eq "$out" "" "gate-type: 同義詞改正不出聲"
assert_eq "$(cat "$G")" "$(printf '## g1\ntype: approval\nneeds: run\nstatus: answered\n\n## g2\ntype: approval\nstatus: answered\n\n## g3\ntype: decision\nstatus: answered\n\n## g4\ntype: decision\nstatus: answered\n\n## g5\ntype: approval\nstatus: answered')" "gate-type: 同義詞改正，needs 與其他行不動"
: > "$KL"
printf '## g1\ntype: approval-ish\nstatus: open\n問題: x\n\n## g2\nstatus: open\n問題: 沒寫\n\n## g3\nstatus: answered\n\n## g4\ntype: decision\nstatus: open\n' > "$G"; cp "$G" "$FX/gt-before.md"
out="$(gts "$G")"; assert_eq "$(cmp -s "$G" "$FX/gt-before.md" && echo same)" "" "gate-type: 表外與沒寫的 type 要補 opened_at 但不改 type"
assert_eq "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out")" PostToolUse
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
for want in g1 approval-ish 'approval | decision' g2 '沒寫 type' 'needs: run'; do case "$ctx" in *"$want"*) ;; *) fail "gate-type: 提醒要含「${want}」：$ctx" ;; esac; done
case "$ctx" in *g3*|*g4*) fail "gate-type: answered 與合法的 gate 不該被提醒：$ctx" ;; esac
assert_eq "$(grep -c '^type: approval-ish$' "$G")" 1 "gate-type: 表外的值原樣保留"
printf '## g1\ntype: approval-ish\nstatus: open\n' > "$G"; printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$G" | CLAUDE_PLUGIN_ROOT="$GP" OPSX_NOW=2026-11-06T14:05:00+08:00 bash "$H/gate-timestamp.sh" >/dev/null 2>&1
assert_eq "$?" 0 "gate-type: 提醒時退出碼仍是 0"
assert_eq "$(cat "$KL")" "$(printf 'opsx coordinate --kick\nopsx coordinate --kick')" "gate-type: 有 open 的 gate 兩次寫入各 kick 一次，且只叫到假的 bin/opsx"
# gate 標題只放 slug：open 的「slug 加其餘文字」被縮成 slug，其餘進 問題:；第一個詞不是 slug 只提醒（gate-id-slug）
printf '## G1 瀏覽器確認精靈畫出來了\ntype: decision\nstatus: open\n\n## g2 測試跑不起來\ntype: decision\nstatus: open\n問題: 需要你在終端機跑\n' > "$G"
out="$(gts "$G")"; assert_eq "$out" "" "gate-slug: 縮標題不出聲"
assert_eq "$(sed -n '1,2p' "$G")" "$(printf '## G1\n問題: 瀏覽器確認精靈畫出來了')" "gate-slug: 沒有問題欄時標題縮成 slug、其餘成為 問題:"
assert_eq "$(grep -c '^## g2$' "$G")" 1 "gate-slug: 有問題欄的 gate 標題也縮成 slug"
assert_eq "$(grep -c '^問題: 測試跑不起來：需要你在終端機跑$' "$G")" 1 "gate-slug: 既有問題欄時其餘接在前面、用「：」分開"
assert_eq "$(grep -c '^問題:' "$G")" 2 "gate-slug: 每個 gate 只有一行 問題:"
cp "$G" "$FX/gs-before.md"; out="$(gts "$G")"; assert_eq "$out" "" "gate-slug: 已是 slug 再跑不出聲"
assert_eq "$(cmp -s "$G" "$FX/gs-before.md" && echo same)" same "gate-slug: 冪等，第二次不改檔"
printf '## G1 舊的標題\ntype: decision\nstatus: answered\nanswer: A\n' > "$G"; cp "$G" "$FX/gs-before.md"
out="$(gts "$G")"; assert_eq "$out" "" "gate-slug: answered 的 gate 不提醒"
assert_eq "$(cmp -s "$G" "$FX/gs-before.md" && echo same)" same "gate-slug: answered 的標題不動"
printf '## 測試跑不起來，需要你在終端機跑\ntype: decision\nstatus: open\n' > "$G"
out="$(gts "$G")"; ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
for want in '測試跑不起來，需要你在終端機跑' slug; do case "$ctx" in *"$want"*) ;; *) fail "gate-slug: 第一個詞不是 slug 的提醒要含「${want}」：$ctx" ;; esac; done
assert_eq "$(sed -n 1p "$G")" '## 測試跑不起來，需要你在終端機跑' "gate-slug: 第一個詞不是 slug 不改標題"
# review R1.1：縮出來的 slug 撞到同檔另一個 gate 就都不縮，只提醒（不然 answer 會默默回第一個）
printf '## G1 甲\ntype: decision\nstatus: open\n\n## G1 乙\ntype: decision\nstatus: open\n' > "$G"
out="$(gts "$G")"; ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_eq "$(grep -c '^## G1 [甲乙]$' "$G")" 2 "gate-slug: 縮出來會撞名的兩個標題都不縮"
case "$ctx" in *G1*) ;; *) fail "gate-slug: 撞名要提醒並點名 G1：$ctx" ;; esac
printf '## g1\ntype: decision\nstatus: answered\n\n## g1 新題\ntype: decision\nstatus: open\n' > "$G"
out="$(gts "$G")"; assert_eq "$(grep -c '^## g1 新題$' "$G")" 1 "gate-slug: 撞到已答的 gate 標題也不縮"
# review R1.2：stop-gate 自己寫的「卡在接」標題是它找 gate 的鑰匙，不提醒、不改
printf '## 卡在接 /review #1\ntype: decision\nstatus: open\n' > "$G"
out="$(gts "$G")"; assert_eq "$out" "" "gate-slug: 卡在接 的標題不提醒"
assert_eq "$(sed -n 1p "$G")" '## 卡在接 /review #1' "gate-slug: 卡在接 的標題不動"
# review R1.4：既有 問題: 是空的就不加尾端「：」；整個檔案內容照 spec 比對；續行不碰
printf '## g1 foo bar\ntype: decision\nstatus: open\n問題:\n  續行一\n' > "$G"
out="$(gts "$G")"; assert_eq "$(grep -c '^問題: foo bar$' "$G")" 1 "gate-slug: 空的 問題: 不留尾端「：」"
assert_eq "$(grep -c '^  續行一$' "$G")" 1 "gate-slug: 問題: 後面的續行原樣保留"
printf '## G1 瀏覽器確認精靈畫出來了\ntype: decision\nstatus: open\n\n## g2 測試跑不起來\ntype: decision\nstatus: open\n問題: 需要你在終端機跑\n' > "$G"; gts "$G" >/dev/null
assert_eq "$(cat "$G")" "$(printf '## G1\n問題: 瀏覽器確認精靈畫出來了\ntype: decision\nstatus: open\nopened_at: 2026-11-06T14:05:00+08:00\n\n## g2\ntype: decision\nstatus: open\nopened_at: 2026-11-06T14:05:00+08:00\n問題: 測試跑不起來：需要你在終端機跑')" "gate-slug: 縮標題只動標題與 問題: 兩處，其他行與順序不變"
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
# 字樣只在引號 / heredoc 內 → 不擋
out="$(sd 'echo "git push origin main"')"; assert_eq "$(decision "$out")" allow "guard: 引號內的 push main"
out="$(sd 'opsx answer s g1 -- "git add .env 之後再說"')"; assert_eq "$(decision "$out")" allow "guard: 引號內的 git add .env"
out="$(sd 'bash -c "git push origin main"')"; assert_eq "$(decision "$out")" deny "guard: bash -c 內的 push main 仍擋"
out="$(sd 'git push origin "main"')"; assert_eq "$(decision "$out")" deny "guard: 引號包住的 main 仍擋"
# 三種容器（grill D2）：提到 push main、claude 不擋；真的署名寫在 heredoc 餵給 commit 的訊息裡仍擋
out="$(sd 'git commit -m "docs: git push origin main 與 git add .env 的說明"')"; assert_eq "$(decision "$out")" allow "guard: commit 訊息提到 push main / add .env"
out="$(sd 'opsx answer s g1 -- "git push origin main，Co-Authored-By: Claude 都只是文字"')"; assert_eq "$(decision "$out")" allow "guard: answer 答案文字提到 push main 與署名字樣"
out="$(sd 'cat > n.md <<'"'EOF'"'
git push origin main
Co-Authored-By: Claude
EOF')"; assert_eq "$(decision "$out")" allow "guard: 寫檔 heredoc 內的字樣"
out="$(sd 'git commit -F - <<'"'EOF'"'
feat: x

Co-Authored-By: Claude <noreply@anthropic.com>
EOF')"; assert_eq "$(decision "$out")" deny "guard: heredoc 餵給 git commit -F - 的署名仍擋"
out="$(PATH="$FX/noperl:$PATH" sd 'git commit -m x')"; assert_eq "$(decision "$out")" deny "guard: perl 失敗要 deny"
out="$(PATH="$FX/noperl:$PATH" mg 'ls')"; assert_eq "$(decision "$out")" deny "mr: perl 失敗要 deny"
out="$(PATH="$FX/noperl:$PATH" cg 'git commit -m x')"; assert_eq "$(decision "$out")" deny "commit: perl 失敗要 deny"
# 署名寫法的變體（spec 署名寫法的變體）
out="$(sd "git commit -m \$'x\nCo-Authored-By: Claude <a@b.c>'")"; assert_eq "$(decision "$out")" deny "guard: \$'…' 內的字面 \\n 後接署名"
out="$(sd 'printf "x\n\nCo-Authored-By: Claude <a@b.c>\n" | git commit -F -')"; assert_eq "$(decision "$out")" deny "guard: printf 的 \\n 後接署名"
out="$(sd 'echo -e "x\nCo-Authored-By: Claude" | git commit -F -')"; assert_eq "$(decision "$out")" deny "guard: echo -e 的 \\n 後接署名"
out="$(sd 'git commit -m "x
   Co-Authored-By: Claude <a@b.c>"')"; assert_eq "$(decision "$out")" deny "guard: 署名行前面有縮排空白"
out="$(sd 'GIT_AUTHOR_EMAIL=noreply@anthropic.com git commit -m x')"; assert_eq "$(decision "$out")" deny "guard: GIT_AUTHOR_EMAIL"
# 骨架的寫法（bash -e -c、bash -lc、$'…'、heredoc 餵 bash）由第二級、MR 閘門、commit 閘門用，各自要看得到
out="$(mg 'bash -e -c "gh pr create --fill"')"; assert_eq "$(decision "$out")" deny "mr: bash -e -c 內的 create 仍擋"
out="$(mg 'bash -lc "gh pr create --fill"')"; assert_eq "$(decision "$out")" deny "mr: bash -lc 內的 create 仍擋"
out="$(mg "bash -c \$'gh pr create --fill'")"; assert_eq "$(decision "$out")" deny "mr: bash -c \$'…' 內的 create 仍擋"
out="$(mg 'bash <<EOF
gh pr create --fill
EOF')"; assert_eq "$(decision "$out")" deny "mr: heredoc 餵給 bash 的 create 仍擋"
out="$(cg 'bash -e -c "git commit -m x"')"; assert_eq "$(decision "$out")" deny "commit: bash -e -c 內的 commit 仍擋"
out="$(cg 'bash <<EOF
git commit -m x
EOF')"; assert_eq "$(decision "$out")" deny "commit: heredoc 餵給 bash 的 commit 仍擋"
# 署名只抓署名形式：內文提到 claude / anthropic 放行
out="$(sd 'git commit -m "fix: claude 路徑處理"')"; assert_eq "$(decision "$out")" allow "guard: 內文提到 claude"
out="$(sd 'git commit -m "feat: x" -m "改用 Anthropic SDK 的 retry"')"; assert_eq "$(decision "$out")" allow "guard: 第二個 -m 提到 anthropic"
out="$(sd 'git commit -m "docs: 說明 Co-Authored-By 與 Generated with 的檢查規則"')"; assert_eq "$(decision "$out")" allow "guard: 提到署名字樣但不是署名行"
out="$(sd 'git commit -m "x" -m "Generated with [Claude Code](https://claude.com/claude-code)"')"; assert_eq "$(decision "$out")" deny "guard: Generated with 行"
out="$(sd 'GIT_COMMITTER_NAME=Claude git commit -m x')"; assert_eq "$(decision "$out")" deny "guard: GIT_COMMITTER_NAME"

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
rm -f "$C/report.md"; out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 沒 report"; reason "$out" | grep -q '/opsx-workflow:review' || fail "stop: 要叫跑 review"
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
iso_shift() { python3 -I -c 'import datetime, sys; h, z = int(sys.argv[1]), int(sys.argv[2]); print((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=h)).astimezone(datetime.timezone(datetime.timedelta(hours=z))).isoformat(timespec="seconds"))' "$1" "$2"; }
mk_sub() { # <子> <worker> <at> [step]
  local s="$C/subs/$1"; mkdir -p "$s/specs/x"
  printf 'schema: opsx\nparent: eval-core\n' > "$s/.openspec.yaml"
  printf '## Why\n' > "$s/proposal.md"; printf '## Context\n' > "$s/design.md"
  printf '## 1. a\n\n- [ ] 1.1 t\n  - 驗收：a\n  - 測試：b\n' > "$s/tasks.md"
  printf '### Requirement: r\n\n#### Scenario: s\n' > "$s/specs/x/spec.md"
  printf '{"phase":"apply","step":%s,"total":4,"label":"x","tests":"unknown","at":"%s","worker":"%s"}' "${4:-0}" "$3" "$2" > "$s/status.json"
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
mk_sub attach-cli subagent-attach-cli "$(iso_shift -3 8)"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: at 是 3 小時前（換算時區後）"
mk_sub attach-cli subagent-attach-cli "$(iso_shift 3 8)"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: at 是未來照擋"
mk_sub attach-cli subagent-attach-cli "$(iso_shift 0 -5)"
out="$(sg)"; assert_eq "$out" "" "stop: 負時區的新 at 放行"
mk_sub attach-cli subagent-attach-cli "$FRESH" 4
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 子 change 已回報 DONE（step=total）但還沒疊，照擋"
printf '## 1. x\n\n- [x] 1.1 `attach-cli`：a\n- [ ] R1.1 疊完後檢查 `attach-cli` 的 new.sh\n' > "$C/tasks.md"
mk_sub attach-cli subagent-attach-cli "$FRESH"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 子殼名只出現在後面的 R task 行，照擋"
printf '## 1. x\n\n- [x] 1.1 `attach-cli`：a\n- [ ] R1.1 `attach-cli`：疊完後檢查 new.sh\n' > "$C/tasks.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: R task 行以子殼名開頭（編號不是 [0-9.]+），照擋"
printf '## 1. x\n\n- [ ] 1.1 `attach-cli`：a\n- [x] 1.2 `attach-board`：b\n' > "$C/tasks.md"
mk_sub attach-cli subagent-attach-cli "$(iso_shift 0 8)"
out="$(sg)"; assert_eq "$out" "" "stop: 正時區的新 at 放行"
printf '{"phase":"apply","total":4,"label":"x","tests":"unknown","at":"%s","worker":"subagent-attach-cli"}' "$FRESH" > "$C/subs/attach-cli/status.json"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: status 缺 step 照擋"
printf '{"phase":"apply","step":"0","total":4,"label":"x","tests":"unknown","at":"%s","worker":"subagent-attach-cli"}' "$FRESH" > "$C/subs/attach-cli/status.json"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: step 不是數字照擋"
mk_sub attach-cli subagent-attach-cli "$FRESH"
printf '## 1. x\n\n- [ ] 1.1 `attach-cli`：a\n- [x] 1.2 `attach-board`：b\n' > "$C/tasks.md"
printf '## 1. x\n\n- [ ] 1.1 `attach-cli`：a\n- [x] 1.2 `attach-board`：b\n' > "$C/tasks.md"
rm -rf "$C/subs"; rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
# hook 自己寫的「卡在接」gate：建議是選項之一，不是 hook 內部說明
printf '## 1. x\n\n- [ ] 1.1 a\n' > "$C/tasks.md"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
assert_grep '^建議: 重做 /opsx-workflow:apply 一次，做不完就把卡在哪寫進 gates.md$' "$C/gates.md"
assert_grep '^選項: 重做 /opsx-workflow:apply 一次' "$C/gates.md"
assert_not_grep '先看 pane' "$C/gates.md"
printf '## 1. x\n\n- [x] 1.1 a\n- [x] 1.2 b\n' > "$C/tasks.md"
rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
# 卡在 linked worktree：只算卡自己 branch 的 commit，主 checkout 是別的 session 在用
sgw() { [ -n "${KEEP:-}" ] || rm -rf "$STOP_STATE"; printf '{"cwd":"%s","stop_hook_active":false}' "$WT" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
done_report; sleep 1
git -C "$WT" commit -q --allow-empty -m "feat: card later"
out="$(sgw)"; assert_eq "$(decision "$out")" block "stop: worktree 卡 report 後自己有新 commit"; reason "$out" | grep -q '/opsx-workflow:review' || fail "stop: worktree 卡要叫重跑 review"
done_report; sleep 1
git -C "$R" commit -q --allow-empty -m "feat: other session"
out="$(sgw)"; assert_eq "$out" "" "stop: worktree 卡不看主 checkout 的新 commit"

# ---------- stop gate：下一站 ----------
rm -f "$C/tasks.md" "$C/report.md" "$C/status.json" "$C/gates.md" "$C/grill.md"
# explore.md 寫好、待決空、沒有 tasks.md → /propose
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: explore 完待決空 → 擋"; reason "$out" | grep -q '/opsx-workflow:propose' || fail "stop: 要叫 /propose"
# dev 卡待決非空 → /grill
printf '## 已知\n- x\n\n## 待決\n- 選 A 還是 B\n\n## 不做\n' > "$C/explore.md"
printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$C/.openspec.yaml"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: dev 待決非空 → 擋"; reason "$out" | grep -q '/opsx-workflow:grill' || fail "stop: 要叫 /grill"
# bug-fix 同一張 explore.md → 跳過 grill 直接 /propose
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: bug-fix 待決非空 → 擋"
reason "$out" | grep -q '/opsx-workflow:propose' || fail "stop: bug-fix 要叫 /propose"
reason "$out" | grep -q '/opsx-workflow:grill' && fail "stop: bug-fix 不提 /grill"
# 沒有 explore.md → 不擋
mv "$C/explore.md" "$C/explore.md.bak"; out="$(sg)"; assert_eq "$out" "" "stop: 沒 explore.md 不擋"
mv "$C/explore.md.bak" "$C/explore.md"
# 缺步的新卡（created 2026-11-11 之後）擋在 explore：router 注入 explore，Stop 列出缺的步驟
printf 'schema: opsx\ncreated: 2026-11-12\nkind: bug-fix\n' > "$C/.openspec.yaml"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 新卡缺步要擋"
reason "$out" | grep -q '1 讀卡' || fail "stop: 要列出缺的步驟: $(reason "$out")"
reason "$out" | grep -q '/opsx-workflow:propose' && fail "stop: 缺步的新卡不叫 /propose: $(reason "$out")"
out="$(run_hook openspec-router.sh "$(j "$R" "" '{}' "下一步")")"; reason "$out" | grep -q '^opsx：explore · eval-core' || fail "router: 新卡缺步仍是 explore: $(reason "$out")"
cp "$C/explore.md" "$C/explore.md.keep"
{ cat "$C/explore.md"; printf '\n## 步驟\n\n- 1 讀卡：已知\n- 2 how：已知\n- 3 影響範圍：已知\n- 4 why：已知\n- 5 prototype：已知\n- 6 查資料：已知\n- 7 對照 code：已知\n- 8 待決：已知\n- 9 unslop：已知\n'; } > "$C/explore.md.full"
mv "$C/explore.md.full" "$C/explore.md"
out="$(sg)"; reason "$out" | grep -q '/opsx-workflow:propose' || fail "stop: 九步補齊後回到 /propose: $(reason "$out")"
mv "$C/explore.md.keep" "$C/explore.md"
printf 'schema: opsx\nkind: bug-fix\n' > "$C/.openspec.yaml"
out="$(sg)"; reason "$out" | grep -q '/opsx-workflow:propose' || fail "stop: 沒有 created 的卡不回頭補: $(reason "$out")"
printf 'schema: opsx\ncreated: 2026-11-10\nkind: bug-fix\n' > "$C/.openspec.yaml"
out="$(sg)"; reason "$out" | grep -q '/opsx-workflow:propose' || fail "stop: 門檻當天建的卡不回頭補: $(reason "$out")"
printf 'schema: opsx\ncreated: 2026-11-11\nkind: bug-fix\n' > "$C/.openspec.yaml"
out="$(sg)"; reason "$out" | grep -q '1 讀卡' || fail "stop: 門檻隔天建的卡缺步要擋: $(reason "$out")"
printf '## 要選 A 還是 B\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$out" "" "stop: 新卡缺步但有會擋的 open gate 放行"
rm "$C/gates.md"
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
out="$(sg)"; reason "$out" | grep -q '/opsx-workflow:propose' || fail "stop: 舊卡不回頭補: $(reason "$out")"
# 一般 open gate 放行；問「要不要接」的 gate 不算
printf '## 要選 A 還是 B\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$out" "" "stop: chain 站有一般 open gate 放行"
printf '## 要不要接 /propose\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 「要不要接」的 gate 不算 open"; reason "$out" | grep -q '/opsx-workflow:propose' || fail "stop: 要不要接的 gate 下仍要叫 /propose"
printf '## propose-done\ntype: decision\nstatus: open\n問題: 要不要接 /apply？\n選項: 接 (Recommended) | 不接\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 真實 gate 格式（問題:）問要不要接也不算 open"
printf '## g1\ntype: decision\nstatus: open\n問題: 要不要接受舊版 API 不相容？\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$out" "" "stop: 要不要接受 X 是真的產品問題，算 open"
printf '## merge-head-moved\ntype: approval\naction: merge\nstatus: open\n問題: MR head 變了，要不要繼續？\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$out" "" "stop: approval gate 只有人能答，問要不要繼續也算 open"
# apply 站（tasks.md 一個都沒勾）：「要不要接 /apply」的 gate 不放行，reason 叫 /apply
printf '## 1. x\n\n- [ ] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"
printf '## 要不要接 /apply\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: apply 站「要不要接」gate 不放行"; reason "$out" | grep -q 'invoke /opsx-workflow:apply' || fail "stop: apply 站 reason 要叫 invoke /apply"
# approval 旗標只管自己那個 gate：前一個 approval 不能把後面沒有 type 的「要不要接」gate 變成會擋的
printf '## 核准 push\ntype: approval\nstatus: answered\n\n## 要不要接 /apply\nstatus: open\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: approval 旗標不帶到下一個 gate"; reason "$out" | grep -q 'invoke /opsx-workflow:apply' || fail "stop: approval 後接「要不要接」gate，reason 要叫 invoke /apply"
# review R1.3：gate-timestamp 把標題縮成 slug 併進既有 問題: 之後，「要不要繼續」仍然不擋 Stop（縮標題前後結果一樣）
printf '## g1 要不要繼續\ntype: decision\nstatus: open\n問題: 跑完了\n' > "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 縮標題前「要不要繼續」不算 open"
gts "$C/gates.md" >/dev/null
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 縮標題後「要不要繼續：…」仍不算 open"
rm -f "$C/gates.md" "$C/tasks.md"

# 擋的次數：同一站 3 次，第 4 次 hook 寫 gate 放行；第 5 次不寫第二個
rm -rf "$STOP_STATE"
# symlink-safe-writes：擋次數的狀態檔是 symlink → 換成一般檔，目標不變（內容是合法的舊狀態，讀它不出錯）
mkdir -p "$STOP_STATE"; printf 'none 0 - x\n' > "$FX/victim"; ln -s "$FX/victim" "$STOP_STATE/Agentory-AI-$(basename "$C")"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: 第 1 次擋"
assert_eq "$(cat "$FX/victim")" "none 0 - x" "stop: 狀態檔上的 symlink 不能被寫到目標"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: 第 2 次擋"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: 第 3 次擋"
assert_no_file "$C/gates.md"
# gates.md 是 symlink 時，第 4 次要寫的自動 gate 不能附加到目標；次數沒推進，下面的真第 4 次照常寫
printf 'keep me\n' > "$FX/victim"; ln -s "$FX/victim" "$C/gates.md"
out="$(KEEP=1 sg)"
assert_eq "$(cat "$FX/victim")" "keep me" "stop: 自動 gate 不能附加到 symlink 的目標"
rm -f "$C/gates.md"
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
# 流水號取最大值加一：較早的 gate 不在了（Write 覆寫、人手刪），數量小於最大號
printf '## 卡在接 /propose #2\ntype: decision\nstatus: answered\n' > "$C/gates.md"; rm -rf "$STOP_STATE"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
assert_grep '^## 卡在接 /propose #3$' "$C/gates.md"
assert_eq "$(grep -c '^## 卡在接 /propose #2$' "$C/gates.md")" 1 "stop: 缺較早 gate 時新 gate 不與 #2 同名"
# 舊格式標題尾端多一個空白也要算進去
printf '## 卡在接 /propose \ntype: decision\nstatus: answered\n' > "$C/gates.md"; rm -rf "$STOP_STATE"
out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"; out="$(KEEP=1 sg)"
assert_grep '^## 卡在接 /propose #2$' "$C/gates.md"
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
# apply 站 HEAD 算進度：同一組未勾 task，中間多一個 commit，次數歸零
out="$(KEEP=1 sg)"
assert_eq "$(cut -d' ' -f1,2 "$STOP_STATE/Agentory-AI-eval-core")" "apply 2" "stop: HEAD 不變次數累計"
git -C "$R" commit -q --allow-empty -m "chore: between apply stops"
out="$(KEEP=1 sg)"; assert_eq "$(decision "$out")" block "stop: apply 站 commit 後仍擋"
assert_eq "$(cut -d' ' -f1,2 "$STOP_STATE/Agentory-AI-eval-core")" "apply 1" "stop: apply 站 commit 算進度，次數歸零"
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
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: report 沒 MR → 擋"; reason "$out" | grep -q '/opsx-workflow:pr' || fail "stop: 要叫 /pr"
printf '# report\n### 待修（範圍內）\n- a.sh:1 task 沒做 · 回 `/apply eval-core` 做完\n### Consider\n' > "$C/report.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 待修（範圍內）有項目 → 擋"; reason "$out" | grep -q '/opsx-workflow:apply' || fail "stop: 待修要叫 /apply"; reason "$out" | grep -q '/opsx-workflow:pr' && fail "stop: 待修不叫 /pr"
printf '# report\n### 待修（範圍內）\n### Consider\n- a.sh:1 設計疑問\n' > "$C/report.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 待修空了 → 照一般 pr 站"; reason "$out" | grep -q '/opsx-workflow:pr' || fail "stop: 待修空了要叫 /pr"
# 確認: <sha>：HEAD 等於該 sha 時 report 之後的新 commit 不要求重審
printf '# report\n### 待修（範圍內）\n' > "$C/report.md"; sleep 1
git -C "$R" commit -q --allow-empty -m "fix: review items"
out="$(sg)"; reason "$out" | grep -q '再跑一次 /opsx-workflow:review' || fail "stop: 沒有確認行，report 後新 commit 要求重審"
printf '# report\n### 待修（範圍內）\n確認: %s\n' "$(git -C "$R" rev-parse HEAD)" > "$C/report.md"; touch -t 200001010000 "$C/report.md"
out="$(sg)"; reason "$out" | grep -q '/opsx-workflow:review' && fail "stop: 確認 sha 等於 HEAD 不再要求重審"
git -C "$R" commit -q --allow-empty -m "fix: after confirm"
out="$(sg)"; reason "$out" | grep -q '再跑一次 /opsx-workflow:review' || fail "stop: 確認後又有新 commit 要重審"
printf '# report\n' > "$C/report.md"
# babysit 站查 forge：MR 狀態來自假 glab
use_fakes glab; export OPSX_FAKE_LOG="$FX/glab.log" OPSX_TEST_GLAB_JSON="$FX/mr.json" OPSX_MR_CACHE_TTL=0; : > "$OPSX_FAKE_LOG"
OPEN_MR='{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}'
MERGED_MR='{"state":"merged","draft":false,"has_conflicts":false,"sha":"abc123","merged_at":"2026-11-10T03:00:00.000Z"}'
printf '%s' "$OPEN_MR" > "$OPSX_TEST_GLAB_JSON"
# babysit 站：有 MR 沒有 babysit: 行
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/a/b/-/merge_requests/212 · opened 2026-11-10 · auto-merge: no\n' > "$C/report.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: MR 已開沒 babysit → 擋"; reason "$out" | grep -q '/opsx-workflow:babysit' || fail "stop: 要叫 /babysit"
done_report
out="$(sg)"; assert_eq "$out" "" "stop: 有 babysit: 行放行"
# MR 已合併、workplan 沒標 merged、沒有 babysit: 行 → 要 /archive，不要 babysit 記號
printf '%s' "$MERGED_MR" > "$OPSX_TEST_GLAB_JSON"
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/a/b/-/merge_requests/212 · opened 2026-11-10 · auto-merge: no\n' > "$C/report.md"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: MR 已合併 → 擋"
reason "$out" | grep -q '/opsx-workflow:archive' || fail "stop: 已合併要叫 /archive: $(reason "$out")"
reason "$out" | grep -q 'babysit' && fail "stop: 已合併不該提 babysit: $(reason "$out")"
# 已合併也勝過舊的 babysit: 記號
done_report
out="$(sg)"; reason "$out" | grep -q '/opsx-workflow:archive' || fail "stop: 已合併且有 babysit: 行仍要 /archive: $(reason "$out")"
# 擋滿 3 次：第 4 次寫「卡在接 /archive #1」並放行
rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
KEEP=1 sg >/dev/null; KEEP=1 sg >/dev/null; KEEP=1 sg >/dev/null
out="$(KEEP=1 sg)"; assert_eq "$out" "" "stop: 已合併擋 3 次後放行"
assert_grep '^## 卡在接 /archive #1$' "$C/gates.md"; assert_not_grep '卡在接 /babysit' "$C/gates.md"
rm -f "$C/gates.md"
# 查不到 MR 狀態：維持 /babysit，reason 帶查詢的錯誤文字
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/a/b/-/merge_requests/212 · opened 2026-11-10 · auto-merge: no\n' > "$C/report.md"
printf '' > "$OPSX_TEST_GLAB_JSON"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: 查不到 MR → 維持擋"
reason "$out" | grep -q '/opsx-workflow:babysit' || fail "stop: 查不到要叫 /babysit: $(reason "$out")"
reason "$out" | grep -q 'glab mr view 212' || fail "stop: 要帶查詢的錯誤文字: $(reason "$out")"
# 已關閉但沒合併（merged_at 是 null）：不是 /archive
printf '{"state":"closed","draft":false,"has_conflicts":false,"sha":"abc123","merged_at":null}' > "$OPSX_TEST_GLAB_JSON"
out="$(sg)"; assert_eq "$(decision "$out")" block "stop: MR 已關閉未合併 → 擋"
reason "$out" | grep -q '/opsx-workflow:babysit' || fail "stop: 已關閉未合併要叫 /babysit: $(reason "$out")"
reason "$out" | grep -q '/opsx-workflow:archive' && fail "stop: 已關閉未合併不能叫 /archive: $(reason "$out")"
# forge 查詢掛住：在 hook 的 10 秒之內放棄，仍 block 並帶錯誤文字
printf '%s' "$MERGED_MR" > "$OPSX_TEST_GLAB_JSON"
t0="$(date +%s)"; out="$(OPSX_TEST_GLAB_SLEEP=6 OPSX_MR_TIMEOUT=1 sg)"; elapsed=$(( $(date +%s) - t0 ))
[ "$elapsed" -lt 4 ] || fail "stop: 查詢要在時限內放棄，花了 ${elapsed} 秒"
assert_eq "$(decision "$out")" block "stop: 查詢逾時 → 擋"
reason "$out" | grep -q '/opsx-workflow:babysit' || fail "stop: 逾時要叫 /babysit: $(reason "$out")"
reason "$out" | grep -q 'glab mr view 212' || fail "stop: 逾時要帶錯誤文字: $(reason "$out")"
# 不設 OPSX_MR_TIMEOUT：hook 自己的預設要在 10 秒內放棄
t0="$(date +%s)"; out="$(unset OPSX_MR_TIMEOUT; OPSX_TEST_GLAB_SLEEP=9 sg)"; elapsed=$(( $(date +%s) - t0 ))
[ "$elapsed" -lt 8 ] || fail "stop: 預設時限要小於 hook 的 10 秒，花了 ${elapsed} 秒"
assert_eq "$(decision "$out")" block "stop: 預設時限逾時 → 擋"
reason "$out" | grep -q '逾時' || fail "stop: 要說逾時: $(reason "$out")"
printf '%s' "$OPEN_MR" > "$OPSX_TEST_GLAB_JSON"; done_report
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
# symlink-safe-writes：drive 的 log 是 symlink → 這一步失敗（佇列留 .failed），目標不變
rm -f "$QD/Agentory-AI-qc.tsv.failed"; printf 'drive\tqc\t%s\n' "$R" > "$QD/Agentory-AI-qc.tsv"; : > "$OPSX_FAKE_LOG"
DL="$OPSX_STATE_DIR/drive-Agentory-AI-qc.log"; rm -f "$DL"; printf 'keep me\n' > "$FX/victim"; ln -s "$FX/victim" "$DL"
out="$(post "opsx chain p")"
sleep 1
assert_eq "$(cat "$FX/victim")" "keep me" "queue: drive log 不能附加到 symlink 的目標"
assert_file "$QD/Agentory-AI-qc.tsv.failed"
rm -f "$DL" "$QD/Agentory-AI-qc.tsv.failed"
# drive 成功起來：dispatch.json 的 drive_pid 是被起的那支程序本身（假 opsx drive 把自己的 $$ 寫進檔），不是等它的子 shell
mkdir -p "$FX/fake-root/bin"; ln -s "$OPSX_ROOT/hooks" "$FX/fake-root/hooks"; ln -s "$OPSX_ROOT/bin/lib" "$FX/fake-root/bin/lib"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$$" > "%s/drive-self.pid"\nsleep 2\n' "$FX" > "$FX/fake-root/bin/opsx"
printf '{"Agentory-AI/qc":{"mode":"autopilot","drive_pid":null}}\n' > "$OPSX_STATE_DIR/dispatch.json"
printf 'drive\tqc\t%s\n' "$R" > "$QD/Agentory-AI-qc.tsv"
out="$(CLAUDE_PLUGIN_ROOT="$FX/fake-root" post "opsx chain p")"
n=0; until [ -s "$FX/drive-self.pid" ]; do n=$((n+1)); [ $n -lt 30 ] || fail "假 drive 沒在背景起來"; sleep 0.1; done
assert_eq "$(jq -r '."Agentory-AI/qc".drive_pid' "$OPSX_STATE_DIR/dispatch.json")" "$(cat "$FX/drive-self.pid")" "queue: drive_pid 要是起出來的程序本身"
# pane 關掉時 process group 收到 SIGHUP：背景起的 drive 要活著
kill -HUP "$(cat "$FX/drive-self.pid")"; sleep 0.3
kill -0 "$(cat "$FX/drive-self.pid")" 2>/dev/null || fail "queue: drive 收到 SIGHUP 死了"
assert_no_file "$QD/Agentory-AI-qc.tsv.failed"

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
