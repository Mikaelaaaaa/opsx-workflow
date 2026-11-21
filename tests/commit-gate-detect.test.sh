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

R="$(mk_repo Acmecorp-AI git@gitlab.example.com:acmecorp/Acmecorp-AI.git)"
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

# command-gate-bypass：commit 實際作用的目錄。cgin <session cwd> <指令>
cgin() { run_hook openspec-commit-gate.sh "$(j "$1" "{\"command\":$(printf '%s' "$2" | jq -Rs .)}")"; }
# 連續的 cd、含 .. 的 cd、pushd 都要疊起來（wt 在卡的 branch 上且 tasks 已勾；session 在 main 的 $R）
out="$(cgin "$R" "cd $FX && cd wt && git commit -m x")"; assert_eq "$(decision "$out")" allow "兩個 cd 要疊起來: $(reason "$out")"
out="$(cgin "$R" "cd $FX/wt/.. && cd wt && git commit -m x")"; assert_eq "$(decision "$out")" allow "cd 含 .. 要疊起來: $(reason "$out")"
out="$(cgin "$R" "pushd $FX/wt && git commit -m x")"; assert_eq "$(decision "$out")" allow "pushd 要當成 cd: $(reason "$out")"
out="$(cgin "$R" "cd $FX/wt && cd $R && git commit -m x")"; assert_eq "$(decision "$out")" deny "最後 cd 回 main，要擋"
out="$(cgin "$R" 'pushd "$X" && git commit -m x')"; assert_eq "$(decision "$out")" deny "pushd 的目錄讀不出來要 deny"
# --git-dir 與 --work-tree 決定作用的 repo（session cwd 不是 repo 時也一樣）
out="$(cgin "$FX" "git --git-dir=$R/.git commit -m x")"; assert_eq "$(decision "$out")" deny "--git-dir 指到 main 上的 repo 要擋: $(reason "$out")"
# 只給 --work-tree 不改 repo：repo 還是 cwd（與 -C）的那個。cwd 不是 repo 時 git 自己會失敗，閘門不擋
out="$(cgin "$R" "git --work-tree=$FX/wt commit -m x")"; assert_eq "$(decision "$out")" deny "只給 --work-tree，repo 還是 session 在 main 的 ${R}，要擋: $(reason "$out")"
out="$(cgin "$FX" "git --work-tree=$R commit -m x")"; assert_eq "$(decision "$out")" allow "cwd 不是 repo、只給 --work-tree：git 自己會失敗，閘門不擋"
# --git-dir 與 --work-tree 並用：repo 由 --git-dir 決定；兩邊不是同一個 repo 就 deny
out="$(cgin "$FX" "git --work-tree=/tmp --git-dir=$R/.git commit -m x")"; assert_eq "$(decision "$out")" deny "work-tree 與 git-dir 不是同一個 repo 要 deny"
reason "$out" | grep -q 'work-tree' || fail "deny 要點名 work-tree: $(reason "$out")"
out="$(cgin "$FX" "git --work-tree=$R --git-dir=$R/.git commit -m x")"; assert_eq "$(decision "$out")" deny "兩邊同一個 repo（main，沒有卡）照 branch 判斷：$(reason "$out")"
reason "$out" | grep -q 'work-tree' && fail "同一個 repo 不能說 work-tree 有問題: $(reason "$out")"
out="$(cgin "$R" "git --git-dir=/abs/bare.git commit -m x")"; assert_eq "$(decision "$out")" deny "--git-dir 不是 <repo>/.git 讀不出作用的 repo，要 deny"
# popd 之後的目錄讀不出來
out="$(cgin "$R" "popd && git commit -m x")"; assert_eq "$(decision "$out")" deny "popd 之後讀不出作用的目錄，要 deny: $(reason "$out")"
reason "$out" | grep -q 'popd' || fail "deny 要點名 popd: $(reason "$out")"
out="$(cgin "$FX/wt" "echo hi && git commit -m x")"; assert_eq "$(decision "$out")" allow "對照：沒有 popd 的同一條 commit 照 branch 放行: $(reason "$out")"
# 相對的 --git-dir 與 --work-tree 照 cd 疊出來的目錄解析（同一個 repo，wt 在卡的 branch 上且 tasks 已勾）；--git-dir 結尾的 / 不擋
out="$(cgin "$FX" "git --git-dir=wt/.git --work-tree=wt commit -m x")"; assert_eq "$(decision "$out")" allow "相對路徑的 git-dir 與 work-tree 是同一個 repo: $(reason "$out")"
out="$(cgin "$R" "cd $FX && git --git-dir=wt/.git --work-tree=wt commit -m x")"; assert_eq "$(decision "$out")" allow "cd 之後的相對 git-dir 與 work-tree: $(reason "$out")"
out="$(cgin "$FX" "git --git-dir=$FX/wt/.git/ commit -m x")"; assert_eq "$(decision "$out")" allow "--git-dir 結尾的 / 不能被拒: $(reason "$out")"
# 指令位置的 \<字母> 還原：這些寫法 bash 都是 git commit，session 在 main（沒有卡）要擋
for c in '/usr/bin/g\it commit -m x' 'echo hi;g\it commit -m x' 'echo hi&&g\it commit -m x'; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" deny "反斜線切開的 git 要擋：${c}｜$(reason "$out")"
done
# 別名：在 git 設定寫入別名，之後的別名 commit 會繞過閘門，設定當下就擋（任何別名都擋；--get 這類讀取不擋）
for c in 'git config alias.ci commit' 'git config --global alias.ci commit' 'git config alias.ci "!git commit"' 'git config alias.ci "com\mit"' "git config alias.ci 'c\"\"ommit'" 'git config alias.st status'; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" deny "設別名要擋：${c}｜$(reason "$out")"
  reason "$out" | grep -q '別名' || fail "deny 要說明別名: $(reason "$out")"
done
out="$(cgin "$R" 'git config --get alias.ci')"; assert_eq "$out" "" "讀別名不出聲"
out="$(cgin "$R" 'git config alias.ci')"; assert_eq "$out" "" "沒有值的 alias.<名> 只是讀，不出聲"
# 唯讀旗標只算在同一段：別的段或尾端註解帶 --list 不能關掉別名擋
for c in 'git config alias.ci commit; git config --list' 'git config alias.ci commit # --list' 'git config alias.ci commit && ls --get'; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" deny "別的段帶唯讀旗標不能關掉別名擋：${c}｜$(reason "$out")"
done
# commit 訊息只是提到別名的字樣：不是設別名，照 branch 判斷（wt 在卡的 branch、tasks 已勾）
out="$(cgin "$FX/wt" 'git commit -m "docs: never run git config alias.ci commit"')"; assert_eq "$(decision "$out")" allow "訊息提到別名字樣不能被當成設別名: $(reason "$out")"
# cd-command-position：cd、pushd 只在命令開頭算數，旗標略過，沒有參數讀不出目錄（$R 在 main，$FX/wt 在卡的 branch、tasks 已勾）
for c in "cd -P $R && git commit -m x" "cd -- $R && git commit -m x" "cd -L $R && git commit -m x" 'pushd && git commit -m x' 'cd && git commit -m x'; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" deny "cd 的旗標或沒有參數：${c}｜$(reason "$out")"
done
for c in "cd -P $FX/wt && git commit -m x" "cd -L -- $FX/wt ; git commit -m x" "cd $FX/wt && git commit -m x" "git status; cd $FX/wt && git commit -m x"; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" allow "命令開頭的 cd 照後面的目錄判：${c}｜$(reason "$out")"
done
for c in "echo cd $R; git commit -m x" "git log --grep cd $R; git commit -m x"; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" allow "參數位置的 cd 不算：${c}｜$(reason "$out")"
done
out="$(cgin "$R" "echo cd $FX/wt; git commit -m x")"; assert_eq "$(decision "$out")" deny "echo 的 cd 不能把目標換到卡的 worktree: $(reason "$out")"
# CDPATH 讓相對 cd 的目錄讀不出來：commit 前面有 CDPATH 賦值就擋
for c in "CDPATH=$FX cd wt && git commit -m x" "export CDPATH=$FX; cd wt && git commit -m x" "env CDPATH=$FX git commit -m x"; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" deny "CDPATH 要擋：${c}｜$(reason "$out")"
  reason "$out" | grep -q 'CDPATH' || fail "deny 要點名 CDPATH: $(reason "$out")"
done
N="$FX/nowp"; mkdir -p "$N/sub"; git -C "$N" init -q
out="$(cgin "$N" 'CDPATH=/x cd sub && git commit -m x')"; [ "$(decision "$out")" != deny ] || fail "沒有 workplan 的 repo 不因 CDPATH 被擋: $(reason "$out")"
# every-commit-checked：兩個以上 git commit 就 deny，訊息請分成兩個 Bash 呼叫
for c in "git commit -m a; git -C $R commit -m b" "git commit -m a; cd $R && git commit -m b" "git commit -m a && git commit --amend -m b"; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" deny "兩個 commit 要擋：${c}｜$(reason "$out")"
  reason "$out" | grep -q '兩個 Bash 呼叫' || fail "deny 要請分成兩個 Bash 呼叫: $(reason "$out")"
done
out="$(cgin "$R" "git -C $FX/wt commit -m a; git commit -m b")"; assert_eq "$(decision "$out")" deny "兩個 commit 要擋（session 在 main）: $(reason "$out")"
for c in 'git add f && git commit -m x' 'git commit -m "fix git commit message"' 'git commit-tree x && git commit -m y'; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" allow "一個 commit 照常判：${c}｜$(reason "$out")"
done
out="$(cgin "$N" 'git commit -m a; git commit -m b')"; [ "$(decision "$out")" != deny ] || fail "沒有 workplan 的 repo 不因多個 commit 被擋: $(reason "$out")"
# alias-env-bypass：帶路徑的 git、--config-env、GIT_CONFIG_* 賦值都當別名寫入擋
for c in '/usr/bin/git config alias.ci commit' 'FOO=commit git --config-env alias.ci=FOO ci -m x' 'git --config-env=alias.ci=FOO ci -m x' 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.ci GIT_CONFIG_VALUE_0=commit git ci -m x' "GIT_CONFIG_PARAMETERS=\"'alias.ci'='commit'\" git ci -m x" 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=a git status'; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" deny "別名寫入要擋：${c}｜$(reason "$out")"
  reason "$out" | grep -q '別名' || fail "deny 要說別名: $(reason "$out")"
done
for c in '/usr/bin/git config --get alias.ci' 'git log --oneline'; do
  out="$(cgin "$R" "$c")"; [ "$(decision "$out")" != deny ] || fail "讀別名不擋：${c}｜$(reason "$out")"
done
out="$(cgin "$N" 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.ci GIT_CONFIG_VALUE_0=commit git ci -m x')"; [ "$(decision "$out")" != deny ] || fail "沒有 workplan 的 repo 不因 GIT_CONFIG_* 被擋: $(reason "$out")"
# subshell-gitdir：子程序裡有 cd 就擋，GIT_DIR 這組環境變數就擋
for c in "cd $R && (cd $N) && git commit -m x" "echo \$(cd /tmp) && git commit -m x" 'bash -c "cd /tmp" ; git commit -m x' 'eval "cd /tmp"; git commit -m x' 'echo `cd /tmp`; git commit -m x'; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" deny "子程序裡的 cd 要擋：${c}｜$(reason "$out")"
  reason "$out" | grep -q 'git -C' || fail "deny 要說改法 git -C: $(reason "$out")"
done
out="$(cgin "$N" "cd $R && (cd $N) && git commit -m x")"; assert_eq "$(decision "$out")" deny "session 在 N：外層 cd 到 R，括號裡的 cd 不算: $(reason "$out")"
reason "$out" | grep -q 'git -C' || fail "deny 要說改法 git -C: $(reason "$out")"
# 從卡的 worktree 跑：沒有這條規則就會 allow，所以刪掉 env_re 會變紅
for p in "GIT_DIR|GIT_DIR=$R/.git git commit -m x" "GIT_WORK_TREE|export GIT_WORK_TREE=$R; git commit -m x" "GIT_COMMON_DIR|env GIT_COMMON_DIR=$R/.git git commit -m x" "GIT_DIR|declare -x GIT_DIR=$R/.git; git commit -m x"; do
  c="${p#*|}"; out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" deny "git 目錄環境變數要擋：${c}｜$(reason "$out")"
  reason "$out" | grep -q "${p%%|*}" || fail "deny 要點名 ${p%%|*}: $(reason "$out")"
done
out="$(cgin "$N" 'git commit -m x')"; [ "$(decision "$out")" != deny ] || fail "沒有子程序照常判: $(reason "$out")"
out="$(cgin "$FX/wt" 'git add $(git ls-files -m) && git commit -m x')"; assert_eq "$(decision "$out")" allow "有 \$( ) 沒有 cd 照常判: $(reason "$out")"
# review R1.1：cd 後面接重導向、前綴關鍵字、管線或背景時，作用目錄照樣讀得出來或擋下
for c in "cd $R 2>/dev/null && git commit -m x" "cd $R > /dev/null; git commit -m x" "command cd $R && git commit -m x" "if true; then cd $R; git commit -m x; fi" "builtin cd $R && git commit -m x"; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" deny "cd 到 main 的寫法不能放行：${c}｜$(reason "$out")"
done
for c in "cd $FX/wt & git commit -m x" "cd $FX/wt | git commit -m x" "echo a | cd $FX/wt && git commit -m x"; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" deny "背景或管線裡的 cd 不改目前目錄：${c}｜$(reason "$out")"
done
for c in "cd $FX/wt 2>/dev/null && git commit -m x" "cd $FX/wt 2>&1 && git commit -m x" "cd $FX/wt > /dev/null; git commit -m x"; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" allow "有重導向的 cd 照後面的目錄判：${c}｜$(reason "$out")"
done
# review R1.2：commit 訊息裡的括號、cd、commit 字樣不是子程序
for c in "cd $FX/wt && git commit -m \"fix(scope): x\"" 'git commit -m "feat(gate): cd into repo before commit"' $'git commit -m "$(cat <<\'EOF\'\nfix: cd (x) before commit\nEOF\n)"'; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" allow "訊息文字不算子程序：${c}｜$(reason "$out")"
done
# review R1.3：只是搜尋這些字串不是寫別名；\git 的寫法照擋
for c in 'grep -rn GIT_CONFIG_COUNT= hooks' 'echo --config-env'; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" allow "沒有 git 的指令不算別名寫入：${c}｜$(reason "$out")"
done
out="$(cgin "$R" '\git config alias.ci commit')"; assert_eq "$(decision "$out")" deny "\\git 寫別名要擋: $(reason "$out")"
# review R2.1：子程序判斷看原文，各種 shell 的 -c 與雙引號裡的 $( ) 都算
for c in 'echo "$(cd /tmp)" && git commit -m x' "sh -c 'cd /tmp'; git commit -m x" "bash -lc \"cd $FX/wt\"; git commit -m x" "zsh -c 'cd /tmp'; git commit -m x"; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" deny "子程序裡的 cd 要擋：${c}｜$(reason "$out")"
  reason "$out" | grep -q 'git -C' || fail "deny 要說改法 git -C: $(reason "$out")"
done
# review R2.2：第一個 commit 的目標不是 workplan 的 repo，第二個 commit 也要被看到
for c in 'git -C /tmp commit -m a; git commit -m b' "git -C $N commit -m a; git commit -m b"; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" deny "第一個 commit 在別的 repo 也要擋：${c}｜$(reason "$out")"
  reason "$out" | grep -q '兩個 Bash 呼叫' || fail "deny 要請分成兩個 Bash 呼叫: $(reason "$out")"
done
# review R2.3：cd 緊接重導向、case 分支裡的 cd
for c in "cd $R>/dev/null && git commit -m x" "case a in *) cd $R;; esac; git commit -m x"; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" deny "cd 到 main 的寫法不能放行：${c}｜$(reason "$out")"
done
out="$(cgin "$R" "cd $FX/wt>/dev/null && git commit -m x")"; assert_eq "$(decision "$out")" allow "緊接重導向的 cd 照後面的目錄判: $(reason "$out")"
# review R2.4：GIT_CONFIG_* 只在同一個指令有 git 或用 export 這類指令設定時算；env 旗標、typeset 前綴認得
for c in 'GIT_CONFIG_COUNT=0 pnpm test' 'env GIT_CONFIG_COUNT=0 pnpm test'; do
  out="$(cgin "$FX/wt" "$c")"; assert_eq "$(decision "$out")" allow "沒有 git 的指令不算別名寫入：${c}｜$(reason "$out")"
done
for c in 'env -i GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.ci GIT_CONFIG_VALUE_0=commit git ci -m x' 'typeset -x GIT_CONFIG_COUNT=1; git ci -m x' 'export GIT_CONFIG_COUNT=1; git ci -m x'; do
  out="$(cgin "$R" "$c")"; assert_eq "$(decision "$out")" deny "GIT_CONFIG_* 設別名要擋：${c}｜$(reason "$out")"
  reason "$out" | grep -q '別名' || fail "deny 要說別名: $(reason "$out")"
done
out="$(cgin "$N" "(cd $N) && git commit -m x")"; [ "$(decision "$out")" != deny ] || fail "作用的 repo 沒有 workplan，不擋: $(reason "$out")"
out="$(cgin "$N" "GIT_DIR=$N/.git git commit -m x")"; [ "$(decision "$out")" != deny ] || fail "沒有 workplan 時 GIT_DIR 不擋: $(reason "$out")"
git -C "$R" worktree remove --force "$FX/wt"
echo "commit-gate-detect ok"
