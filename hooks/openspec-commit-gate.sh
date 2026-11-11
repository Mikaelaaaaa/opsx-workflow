#!/usr/bin/env bash
# PreToolUse(Bash)：git commit 時，branch 要對到卡且 tasks.md 有勾才放行；子殼 branch（<主>--<子>）只要求 tasks.md 存在。
# repo 沒有 workplan.yaml → 不擋（印一行「閘門未啟用」）。對不到 → deny；訊息帶 [no-change] 放行並記 bypass.log。
# 只看 branch 不看 index（Agentory-AI 的 pathspec commit 照用）。要求檔 §8.5。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

cmd="$(hook_cmd)"
sk="$(cmd_skeleton "$cmd")" || deny "opsx commit 閘門：perl 執行失敗，讀不到指令骨架，先擋下。確認 perl 可用"
# git 的寫法：反引號、$(…)、\git、絕對路徑都算；全域選項（-C x、-c k=v、-p、-P、--no-pager、--git-dir=x、--git-dir x…）夾在 git 與 commit 之間也算。
# -c alias.<名>=… 可以把任何字變成 commit，只要出現就當成 commit 處理（寧可誤擋）。
git_word='(^|[^[:alnum:]_./-])(\\|/[^[:space:];&|()`$]*/)?git'
git_opts='(([[:space:]]+-C[[:space:]]+[^[:space:]]+)|([[:space:]]+-c[[:space:]]+[^[:space:]]+)|([[:space:]]+-[pP])|([[:space:]]+--(git-dir|work-tree|namespace|exec-path|super-prefix|config-env)[[:space:]]+[^-[:space:]][^[:space:]]*)|([[:space:]]+--[a-z][a-z-]*(=[^[:space:]]+)?))*'
commit_re="${git_word}${git_opts}[[:space:]]+commit([[:space:]]|\$)"
printf '%s' "$sk" | grep -qE "${commit_re}|${git_word}([[:space:]]+[^;&|]*)?[[:space:]]-c[[:space:]]+alias\\." || exit 0

# commit 實際作用的目錄決定對卡，不是 session cwd；hook_cwd 認 OPSX_CWD
join_dir() { case "$2" in /*) printf '%s' "$2" ;; *) printf '%s/%s' "$1" "$2" ;; esac; }
unreadable_dir() { case "$1" in *[\"\'\$\`~\\]*|*[*?\[\{]*) return 0 ;; esac; return 1; }
unset OPSX_CWD
bad_dirs=''
if [[ "$sk" =~ $commit_re ]]; then
  matched="${BASH_REMATCH[0]}"
  c_dir=''; rest="$matched"
  while [[ "$rest" =~ -C[[:space:]]+([^[:space:]]+)(.*) ]]; do c_dir="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"; done
  before=" ${sk%%"$matched"*}"
  after_cd="${before##*[[:space:];&|(]cd[[:space:]]}"
  cd_dir=''
  [ "$after_cd" != "$before" ] && cd_dir="${after_cd%%[[:space:];&|)]*}"
  for d in "$cd_dir" "$c_dir"; do
    case "$d" in
      '""'|"''") bad_dirs="$bad_dirs 引號包住的路徑" ;;
      *) unreadable_dir "$d" && bad_dirs="$bad_dirs '$d'" ;;
    esac
  done
  if [ -z "$bad_dirs" ]; then
    target="$(hook_cwd)"
    [ -n "$cd_dir" ] && target="$(join_dir "$target" "$cd_dir")"
    [ -n "$c_dir" ] && target="$(join_dir "$target" "$c_dir")"
    [ -d "$target" ] && export OPSX_CWD="$target"
  fi
fi

top="$(repo_top)"
[ -n "$top" ] || exit 0
if [ ! -f "$top/openspec/workplan.yaml" ]; then
  ctx PreToolUse "opsx commit 閘門未啟用：這個 repo 還沒有 openspec/workplan.yaml（第一次 /opsx-workflow:propose 後自動生效）"; exit 0
fi

if [ -n "$bad_dirs" ]; then
  deny "opsx commit 閘門：指令裡的目錄（${bad_dirs# }）含空白、引號、變數、~ 或萬用字元，閘門讀不到 commit 實際作用的 repo。改用不含空白的字面路徑（git -C /abs/path commit 或 cd /abs/path && git commit）。"
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
    # shortcut: 子殼 commit 不檢查有沒有勾，空 commit 也放行, 等有心跳或子殼 status 回報後改成要求 status.json 的 step >= 1
    [ -f "$d/tasks.md" ] || deny "opsx commit 閘門：${d#"$top"/} 沒有 tasks.md。先 /opsx-workflow:propose 寫出子殼的 tasks.md 再 commit；不屬於 task 的改動加 [no-change]。" ;;
  *)
    if [ "$(tasks_done "$d")" -eq 0 ]; then
      deny "opsx commit 閘門：${d#"$top"/} 的 tasks.md 還沒有任何勾（$( [ -f "$d/tasks.md" ] && echo '有 tasks.md 但全未勾' || echo '沒有 tasks.md' )）。先 /opsx-workflow:apply 做完一個 task 並勾起來再 commit；不屬於 task 的改動加 [no-change]。"
    fi ;;
esac
exit 0
