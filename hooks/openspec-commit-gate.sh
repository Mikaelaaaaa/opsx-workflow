#!/usr/bin/env bash
# PreToolUse(Bash)：git commit 時，branch 要對到卡且 tasks.md 有勾才放行。
# repo 沒有 workplan.yaml → 不擋（印一行「閘門未啟用」）。對不到 → deny；訊息帶 [no-change] 放行並記 bypass.log。
# 只看 branch 不看 index（Agentory-AI 的 pathspec commit 照用）。要求檔 §8.5。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

cmd="$(hook_cmd)"
sk="$(cmd_skeleton "$cmd")" || deny "opsx commit 閘門：perl 執行失敗，讀不到指令骨架，先擋下。確認 perl 可用"
printf '%s' "$sk" | grep -qE '(^|\s|&&|\|\||;)git\s+(-C\s+\S+\s+)?commit(\s|$)' || exit 0

# commit 實際作用的目錄決定對卡，不是 session cwd；hook_cwd 認 OPSX_CWD
join_dir() { case "$2" in /*) printf '%s' "$2" ;; *) printf '%s/%s' "$1" "$2" ;; esac; }
unreadable_dir() { case "$1" in *[\"\'\$\`~\\]*|*[*?\[\{]*) return 0 ;; esac; return 1; }
unset OPSX_CWD
bad_dirs=''
if [[ "$sk" =~ (^|[[:space:];\&\|\(])git[[:space:]]+(-C[[:space:]]+([^[:space:]]+)[[:space:]]+)?commit([[:space:]]|$) ]]; then
  c_dir="${BASH_REMATCH[3]}"
  before=" ${sk%%"${BASH_REMATCH[0]}"*}"
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
  ctx PreToolUse "opsx commit 閘門未啟用：這個 repo 還沒有 openspec/workplan.yaml（第一次 /propose 後自動生效）"; exit 0
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
  deny "opsx commit 閘門：branch '$(branch)' 對不到 openspec/changes/<slug>/。先 /propose 開卡（或 /explore），或在 commit 訊息加 [no-change] 說明為什麼這個 commit 不屬於任何 change。"
fi
if [ "$(tasks_done "$d")" -eq 0 ]; then
  deny "opsx commit 閘門：${d#"$top"/} 的 tasks.md 還沒有任何勾（$( [ -f "$d/tasks.md" ] && echo '有 tasks.md 但全未勾' || echo '沒有 tasks.md' )）。先 /apply 做完一個 task 並勾起來再 commit；不屬於 task 的改動加 [no-change]。"
fi
exit 0
