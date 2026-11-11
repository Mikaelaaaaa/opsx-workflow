#!/usr/bin/env bash
# commit 閘門認得 git 全域選項（-c、--no-pager、--git-dir、多個 -C）；認不出作用目錄時 deny。
# 驗收：openspec/changes/me-20261111-1824/specs/commit-gate-detect/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

run_hook() { printf '%s' "$2" | bash "$H/$1" 2>"$FX/hook.err"; true; }
j() { python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name="Bash",tool_input=json.loads(sys.argv[2]),prompt="",hook_event_name="PreToolUse")))' "$1" "$2"; }
decision() { [ -z "$1" ] && { echo allow; return; }; printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // .decision // "allow"'; }
reason() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // .reason // .hookSpecificOutput.additionalContext // ""'; }

R="$(mk_repo Agentory-AI git@gitlab.tsg-navigator.com:agentory/Agentory-AI.git)"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'prs:\n  - name: eval-core\n    status: in-progress\n' > "$R/openspec/workplan.yaml"
printf '## 1. x\n\n- [ ] 1.1 a\n' > "$C/tasks.md"
cg() { run_hook openspec-commit-gate.sh "$(j "$R" "{\"command\":$(printf '%s' "$1" | jq -Rs .)}")"; }

# tasks 全未勾、branch 對到卡：每一種 git 全域選項寫法都要擋
for c in 'git -c user.name=x commit -m fix' 'git --no-pager commit -m fix' "git --git-dir=$R/.git commit -m fix" "git --git-dir $R/.git commit -m fix" 'git -c a=b -c c=d commit -m fix' 'git -c "k=v w" commit -m fix' 'git -P commit -m fix' 'git -p commit -m fix' 'git --super-prefix x/ commit -m fix' 'git -c k=v -P commit -m fix'; do
  out="$(cg "$c")"; assert_eq "$(decision "$out")" deny "commit 閘門要認得：${c}｜${out}｜$(head -c 300 "$FX/hook.err")"
  reason "$out" | grep -q '還沒有任何勾' || fail "deny 要說 tasks 沒勾（${c}）: $(reason "$out")"
done

# 不是 commit 的不動作
for c in 'git -c k=v status' 'git --no-pager log' 'git -c k=v commit-tree x'; do
  out="$(cg "$c")"; assert_eq "$out" "" "非 commit 不出聲：${c}"
done

# 多個 -C 依序疊出作用目錄：session 在 main，wt 在卡的 branch 上且 tasks 已勾
git -C "$R" checkout -q -B main "$(git -C "$R" rev-list --max-parents=0 HEAD)"
git -C "$R" worktree add -q "$FX/wt" feat/eval-core/mikaela
printf '## 1. x\n\n- [x] 1.1 a\n' > "$C/tasks.md"
out="$(cg "git -C $FX -C wt commit -m x")"; assert_eq "$(decision "$out")" allow "兩個 -C 要疊起來: $(reason "$out")"
out="$(cg "git -C /nonexistent-opsx -C $FX/wt commit -m x")"; assert_eq "$(decision "$out")" allow "後面的絕對 -C 蓋掉前面的: $(reason "$out")"
out="$(cg "git -c k=v -C $FX/wt commit -m x")"; assert_eq "$(decision "$out")" allow "-c 在 -C 前面也要看到 -C: $(reason "$out")"
out="$(cg "git -C $FX/wt commit -m x")"; assert_eq "$(decision "$out")" allow "字面路徑照常判斷: $(reason "$out")"
out="$(cg 'git -c k=v commit -m x')"; assert_eq "$(decision "$out")" deny "session 在 main 沒有卡，-c 寫法也要擋"

# 作用目錄讀不出來：反斜線跳脫空白的 -C 路徑 deny，要求字面路徑
out="$(cg 'git -C /abs/my\ dir commit -m x')"; assert_eq "$(decision "$out")" deny "反斜線跳脫空白的 -C 路徑要 deny"
reason "$out" | grep -q '不含空白的字面路徑' || fail "deny 要說明改法: $(reason "$out")"
out="$(cg 'git --git-dir=/abs/a\ b commit -m x')"; assert_eq "$(decision "$out")" deny "反斜線跳脫空白的 --git-dir 路徑要 deny"
git -C "$R" worktree remove --force "$FX/wt"
echo "commit-gate-detect ok"
