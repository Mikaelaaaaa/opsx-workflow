#!/usr/bin/env bash
# PreToolUse(Bash)：git commit 時，branch 要對到卡且 tasks.md 有勾才放行；子殼 branch（<主>--<子>）只要求 tasks.md 存在。
# repo 沒有 workplan.yaml → 不擋（印一行「閘門未啟用」）。對不到 → deny；訊息帶 [no-change] 放行並記 bypass.log。
# 只看 branch 不看 index（Acmecorp-AI 的 pathspec commit 照用）。要求檔 §8.5。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

cmd="$(hook_cmd)"
sk="$(cmd_skeleton "$cmd")" || deny "opsx commit 閘門：perl 執行失敗，讀不到指令骨架，先擋下。確認 perl 可用"
# git 的寫法：反引號、$(…)、\git、絕對路徑都算；git 與 commit 之間可以夾全域選項：-c k=v、-C <dir>（可重複）、--git-dir[=]<d>、--work-tree[=]<d>、--namespace[=]<n>、--no-pager 這類不帶值的長選項。
# 值可以含反斜線跳脫的字元（\ 加任一字元算同一個字），這樣跳脫空白的路徑也讀得到、交給 unreadable_dir 擋。
# -c alias.<名>=… 可以把任何字變成 commit，只要出現就當成 commit 處理（寧可誤擋）。
git_word='(^|[^[:alnum:]_./-])(\\|/[^[:space:];&|()`$]*/)?git'
tok='(\\.|[^[:space:]\\])+'
valued='-C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env|--exec-path'
opt="(${valued})[[:space:]]+${tok}|--[a-z][a-z-]*(=${tok})?|-[A-Za-z]"
commit_re="${git_word}(([[:space:]]+(${opt}))*)[[:space:]]+commit([[:space:]]|\$)"
alias_re="${git_word}([[:space:]]+[^;&|]*)?[[:space:]]-c[[:space:]]+alias\\."
# 在 git 設定寫入別名（git config alias.ci …）：別名的值可以用 bash 與 git 的引號、跳脫寫成 commit（com\mit、'c""ommit'、!f() { git commit; }），
# 之後用別名 commit 時骨架裡沒有 commit，閘門看不到，所以任何別名的寫入在設定當下就擋（--get、--unset、--list 這類讀取與刪除不擋）。
# 看骨架：commit 訊息之類引號裡只是提到這串字，不是在命令位置，不算
persist_re='(^|[[:space:];&|(])(\\|/[^[:space:];&|()`$]*/)?git[[:space:]]([^;&|]*[[:space:]])?config[[:space:]]([^;&|]*[[:space:]])?alias\.[[:alnum:]_.-]+[[:space:]]+[^[:space:];&|#]'
readonly_re='(^|[[:space:]])--(get|get-all|get-regexp|unset|unset-all|list)([[:space:]]|$)'
# --config-env 與 GIT_CONFIG_* 賦值也能寫入別名；值在環境變數裡讀不出來，出現就當別名寫入（寧可誤擋）
# 賦值只在命令位置算：export 這類設定指令不用管後面有沒有 git，前綴賦值與 env 要在同一個指令裡接著 git
cfg_re='GIT_CONFIG_(COUNT|PARAMETERS|KEY_[0-9]+|VALUE_[0-9]+)='
nv_re='[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+'
pre_re="(^|[;&|({]|"$'\n'")[[:space:]]*((then|do|else|elif|if|while|until|time|command|builtin|!)[[:space:]]+)*"
env_alias_re="(${git_word}([[:space:]]+[^;&|]*)?[[:space:]]--config-env([[:space:]=]|\$))"
env_alias_re+="|(${pre_re}(export|declare|typeset|readonly|local)[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*(${nv_re})*${cfg_re})"
env_alias_re+="|(${pre_re}(env[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*)?(${nv_re})*${cfg_re}[^;&|]*${git_word})"
is_alias=0
# 唯讀旗標只看 config 與 alias. 之間那一段（BASH_REMATCH[4]）；alias.<名> 後面沒有值就只是讀
if [[ "$sk" =~ $persist_re ]]; then
  alias_span="${BASH_REMATCH[4]}"
  [[ "$alias_span" =~ $readonly_re ]] || is_alias=1
fi
[[ "$sk" =~ $env_alias_re ]] && is_alias=1
m0=''; opts=''
if [[ "$sk" =~ $commit_re ]]; then
  m0="${BASH_REMATCH[0]}"; opts="${BASH_REMATCH[3]}"
elif [[ "$sk" =~ $alias_re ]]; then
  m0="${BASH_REMATCH[0]}"; opts=''
elif [ "$is_alias" != 1 ]; then
  exit 0
fi

# commit 實際作用的目錄決定對卡，不是 session cwd；hook_cwd 認 OPSX_CWD
join_dir() { case "$2" in /*) printf '%s' "$2" ;; *) printf '%s/%s' "$1" "$2" ;; esac; }
unreadable_dir() { case "$1" in *[\"\'\$\`~\\]*|*[*?\[\{]*) return 0 ;; esac; return 1; }
check_dir() { # <路徑>：讀不出來就記進 bad_dirs
  case "$1" in
    '""'|"''") bad_dirs="$bad_dirs 引號包住的路徑" ;;
    -) bad_dirs="$bad_dirs 'cd -'（上一個目錄讀不出來）" ;;
    *) if unreadable_dir "$1"; then bad_dirs="$bad_dirs '$1'"; fi ;;
  esac
}
unset OPSX_CWD
bad_dirs=''
before=" ${sk%%"$m0"*}"
# commit 前面的 cd 與 pushd 照順序疊起來（cd a && cd b 的 b 是相對 a）
# 只認命令開頭的 cd（echo cd x 的 cd 是參數），前面可以有 NAME=值；-P -L -e -@ -- 略過，目錄在第 8 組
# ( 不算命令開頭：子程序裡的 cd 不改外層目錄，由 sub_cd 擋
dtok='(\\.|[^[:space:];&|)<>\\])+'
asg='[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+|then[[:space:]]+|do[[:space:]]+|else[[:space:]]+|elif[[:space:]]+|if[[:space:]]+|while[[:space:]]+|until[[:space:]]+|![[:space:]]+|time[[:space:]]+|command[[:space:]]+|builtin[[:space:]]+'
cd_re="(^|[;&|{)]|"$'\n'")[[:space:]]*(${asg})*(cd|pushd)(([[:space:]]+-[PLe@]+)*([[:space:]]+--)?)([[:space:]]+(${dtok}))?([[:space:];&|)<>]|\$)"
cd_dirs=()
rest_cd="$before"
while [[ "$rest_cd" =~ $cd_re ]]; do
  if [ -z "${BASH_REMATCH[8]}" ]; then
    bad_dirs="$bad_dirs '${BASH_REMATCH[3]}'（沒有參數，回到哪個目錄讀不出來）"
  else
    check_dir "${BASH_REMATCH[8]}"; cd_dirs+=("${BASH_REMATCH[8]}")
  fi
  rest_cd="${rest_cd#*"${BASH_REMATCH[0]}"}"
done
# CDPATH 會改變相對 cd 的落點；GIT_DIR、GIT_WORK_TREE、GIT_COMMON_DIR 直接換掉 repo，都讀不出來
env_re='(^|[[:space:];&|(])(CDPATH|GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR)='
bad_env=''
[[ "$before" =~ $env_re ]] && bad_env="${BASH_REMATCH[2]}"
# 子程序（( )、$( )、反引號、sh -c、eval）裡的 cd 不影響外層目錄，骨架讀不出來（雙引號裡的 $( ) 沒有括號，sh -c 的內容被攤平成外層的 cd），
# 所以看原文第一個 commit 之前那段；commit 訊息在 commit 之後，不受影響
sub_re='(\(|`|(^|[^[:alnum:]_])(ba|z|k|da)?sh([[:space:]]+-[[:alnum:]]+)*[[:space:]]+-[[:alnum:]]*c|eval[[:space:]])'
cd_word_re='(^|[^[:alnum:]_.-])(cd|pushd)([[:space:]]|$)'
raw_m=''
[[ "$cmd" =~ $commit_re ]] && raw_m="${BASH_REMATCH[0]}"
raw_before="${cmd%%"$raw_m"*}"
sub_cd=0
[[ "$raw_before" =~ $sub_re && "$raw_before" =~ $cd_word_re ]] && sub_cd=1
# 管線裡與背景（單一 &）的 cd 在子程序執行，不改後面 commit 的目錄；先把 2>&1 的 & 去掉
pipe_cd_re='(^|[^|])\|[[:space:]]*(cd|pushd)([[:space:]]|$)'
bg_cd_re='(^|[;&|{]|'$'\n'')[[:space:]]*(cd|pushd)[[:space:]][^;&|]*(\|([^|]|$)|&([^&>]|$))'
before_s="${before//>&/>}"
if [[ "$before_s" =~ $pipe_cd_re || "$before_s" =~ $bg_cd_re ]]; then
  bad_dirs="$bad_dirs 'cd'（在管線或背景裡執行，不改後面 commit 的目錄）"
fi
# 兩個以上 commit 只判得了第一個
commit_n=0
rest_n="$sk"
while [[ "$rest_n" =~ $commit_re ]]; do
  commit_n=$((commit_n + 1)); rest_n="${rest_n#*"${BASH_REMATCH[0]}"}"
done
# popd 回到哪個目錄要追目錄堆疊，讀不出來
popd_re='(^|[[:space:];&|(])popd([[:space:];&|)]|$)'
[[ "$before" =~ $popd_re ]] && bad_dirs="$bad_dirs 'popd'（回到哪個目錄讀不出來）"
# 依序走過全域選項：-C 的目錄照順序收；--git-dir 與 --work-tree 決定作用的 repo
c_dirs=()
gitdir_v=''; wt_v=''
rest="$opts"
while [ -n "${rest//[[:space:]]/}" ]; do
  if [[ "$rest" =~ ^[[:space:]]+-C[[:space:]]+(${tok}) ]]; then
    check_dir "${BASH_REMATCH[1]}"; c_dirs+=("${BASH_REMATCH[1]}")
  elif [[ "$rest" =~ ^[[:space:]]+--git-dir(=|[[:space:]]+)(${tok}) ]]; then
    check_dir "${BASH_REMATCH[2]}"; gitdir_v="${BASH_REMATCH[2]}"
  elif [[ "$rest" =~ ^[[:space:]]+--work-tree(=|[[:space:]]+)(${tok}) ]]; then
    check_dir "${BASH_REMATCH[2]}"; wt_v="${BASH_REMATCH[2]}"
  elif [[ "$rest" =~ ^[[:space:]]+(${valued})[[:space:]]+${tok} ]]; then :
  elif [[ "$rest" =~ ^[[:space:]]+--[a-z][a-z-]*(=${tok})? ]]; then :
  elif [[ "$rest" =~ ^[[:space:]]+-[A-Za-z] ]]; then :
  else break; fi
  rest="${rest:${#BASH_REMATCH[0]}}"
done
if [ -z "$bad_dirs" ]; then
  target="$(hook_cwd)"
  for d in "${cd_dirs[@]+"${cd_dirs[@]}"}"; do target="$(join_dir "$target" "$d")"; done
  for d in "${c_dirs[@]+"${c_dirs[@]}"}"; do target="$(join_dir "$target" "$d")"; done
  # repo 由 --git-dir 決定（HEAD 在那裡）；只給 --work-tree 不改 repo，仍是 cwd 與 -C 找到的那個
  if [ -n "$gitdir_v" ]; then
    base="$target"   # cd 與 -C 疊出來的目錄：相對的 --git-dir 與 --work-tree 都從這裡算
    gitdir_v="${gitdir_v%/}"
    gd="$(join_dir "$base" "$gitdir_v")"
    case "$gd" in
      */.git)
        target="${gd%/.git}"
        # work-tree 對不上時也要看得到 repo，deny 才出得來
        ! [ -d "$target" ] || export OPSX_CWD="$target"
        if [ -n "$wt_v" ]; then
          wt="$(join_dir "$base" "$wt_v")"
          [ "$(cd "$wt" 2>/dev/null && pwd -P)" = "$(cd "$target" 2>/dev/null && pwd -P)" ] \
            || bad_dirs="$bad_dirs '--work-tree ${wt_v}'（跟 --git-dir 不是同一個 repo）"
        fi ;;
      *) bad_dirs="$bad_dirs '--git-dir ${gitdir_v}'（不是 <repo>/.git）" ;;
    esac
  fi
  [ -n "$bad_dirs" ] || ! [ -d "$target" ] || export OPSX_CWD="$target"
fi

top="$(repo_top)"
# 子程序裡的 cd 會被骨架算進作用目錄（sh -c "cd /tmp"），第二個 commit 的目標也沒人算，
# 所以第一個目標之外，session 所在的 repo 也要看：有 workplan 就擋
if [ "$sub_cd" = 1 ] || [ "$commit_n" -ge 2 ]; then
  for t in "$top" "$(OPSX_CWD= repo_top)"; do
    [ -n "$t" ] && [ -f "$t/openspec/workplan.yaml" ] || continue
    [ "$sub_cd" = 1 ] && deny "opsx commit 閘門：commit 前面的子程序（( )、\$( )、反引號、sh -c、eval）裡有 cd，外層的作用目錄讀不出來。改成 cd /abs/path && git commit 或 git -C /abs/path commit。"
    deny "opsx commit 閘門：一個指令裡有 ${commit_n} 個 git commit，閘門只判得了第一個。分成兩個 Bash 呼叫，一個呼叫一個 commit。"
  done
fi
[ -n "$top" ] || exit 0
if [ ! -f "$top/openspec/workplan.yaml" ]; then
  ctx PreToolUse "opsx commit 閘門未啟用：這個 repo 還沒有 openspec/workplan.yaml（第一次 /opsx-workflow:propose 後自動生效）"; exit 0
fi

if [ "$is_alias" = 1 ]; then
  deny "opsx commit 閘門：指令把 commit 設成 git 別名，之後用別名 commit 時骨架裡沒有 commit，會繞過閘門。直接寫 git commit，不要設別名。"
fi

if [ -n "$bad_env" ]; then
  deny "opsx commit 閘門：指令在 commit 前面設了 ${bad_env}，commit 實際作用的 repo 讀不出來。拿掉 ${bad_env}，改用 cd /abs/path && git commit、git -C /abs/path commit，或 git --git-dir=<repo>/.git commit。"
fi

if [ -n "$bad_dirs" ]; then
  deny "opsx commit 閘門：指令裡的目錄（${bad_dirs# }）讀不出 commit 實際作用的 repo：含空白、引號、變數、~ 或萬用字元，或 --git-dir 不是 <repo>/.git，或 cd -。改用不含空白的字面路徑（git -C /abs/path commit 或 cd /abs/path && git commit）。"
fi

if printf '%s' "$cmd" | grep -q '\[no-change\]'; then
  mkdir -p "$OPSX_STATE_DIR"
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(repo_name)" "$(branch)" "$(printf '%s' "$cmd" | tr '\n' ' ' | cut -c1-200)" | opsx_append "$OPSX_STATE_DIR/bypass.log"
  ctx PreToolUse "opsx：[no-change] 逃生口放行，記在 $OPSX_STATE_DIR/bypass.log"; exit 0
fi

d="$(card_dir)"
if [ -z "$d" ]; then
  deny "opsx commit 閘門：branch '$(branch)' 對不到 openspec/changes/<slug>/。先 /opsx-workflow:propose 開卡（或 /opsx-workflow:explore），或在 commit 訊息加 [no-change] 說明為什麼這個 commit 不屬於任何 change。"
fi
case "$(card_slug)" in
  *--*)
    # 子殼的 subagent 在 isolation worktree 寫不到主 repo 的 subs/<子>/tasks.md，勾由 session 疊上 PR branch 時做
    # shortcut: [已評估] 子殼 commit 不檢查有沒有勾，空 commit 也放行, 等有心跳或子殼 status 回報後改成要求 status.json 的 step >= 1
    [ -f "$d/tasks.md" ] || deny "opsx commit 閘門：${d#"$top"/} 沒有 tasks.md。先 /opsx-workflow:propose 寫出子殼的 tasks.md 再 commit；不屬於 task 的改動加 [no-change]。" ;;
  *)
    if [ "$(tasks_done "$d")" -eq 0 ]; then
      deny "opsx commit 閘門：${d#"$top"/} 的 tasks.md 還沒有任何勾（$( [ -f "$d/tasks.md" ] && echo '有 tasks.md 但全未勾' || echo '沒有 tasks.md' )）。先 /opsx-workflow:apply 做完一個 task 並勾起來再 commit；不屬於 task 的改動加 [no-change]。"
    fi ;;
esac
exit 0
