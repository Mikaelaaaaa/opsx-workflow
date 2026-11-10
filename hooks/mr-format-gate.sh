#!/usr/bin/env bash
# PreToolUse(Bash)：glab mr create / gh pr create 時，description 要是 mr-note 格式：
# 有 `## Changes` 和表格列 `| 編號 |`，否則 deny。取代只提醒的 ~/.claude/hooks/mr-note-reminder.sh。要求檔 §8.5。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

cmd="$(hook_cmd)"
# 只看真的要執行的指令：先剝掉 heredoc 本體與引號字串，剩下的要在命令位置（開頭，或 ; & | ( ` 換行之後）才算。
# 引號沒配對時不剝，寧可多檢查。description 的抽取在下面仍讀原始 $cmd。
printf '%s' "$cmd" | perl -e 'local $/; $_ = <STDIN> // ""; s/(?<!<)(<<-?\s*([\x27"]?)(\w+)\2[^\n]*)\n.*?\n[ \t]*\3[ \t]*(?:\n|\z)/$1\n/sg; s/"(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27/""/sg; exit(/(?:^|[;&|(`\n])\s*(?:\w+=\S*\s+)*(?:gh\s+pr\s+(?:create|edit)|glab\s+mr\s+(?:create|update))\b/ ? 0 : 1)' || exit 0

desc=""
# -F / --description-file / --body-file <path>
f="$( { printf '%s' "$cmd" | grep -oE '(-F|--description-file|--body-file|-F=|--body-file=)[= ]*("[^"]+"|'"'"'[^'"'"']+'"'"'|\S+)' || true; } | head -1 | sed -E 's/^(-F|--description-file|--body-file)[= ]*//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//')"
if [ -n "$f" ]; then
  [ "${f#/}" = "$f" ] && f="$(hook_cwd)/$f"
  [ -f "$f" ] && desc="$(cat "$f")"
fi
# -d / --description / -b / --body "<text>"（取第一個引號區塊；多行 heredoc 也在 cmd 裡）
if [ -z "$desc" ]; then
  desc="$(printf '%s' "$cmd" | perl -0ne 'if (/(?:-d|--description|-b|--body)[= ]+"((?:[^"\\]|\\.)*)"/s) { print $1 } elsif (/(?:-d|--description|-b|--body)[= ]+\x27((?:[^\x27])*)\x27/s) { print $1 }')"
fi
if [ -z "$desc" ] && printf '%s' "$cmd" | grep -qE "<<['\"]?[A-Z_]+['\"]?"; then
  desc="$(printf '%s' "$cmd" | awk 'f{print} /<<[ '"'"'"]*[A-Z_]+/{f=1}')"
fi

if [ -z "$desc" ]; then
  deny "opsx MR 閘門：沒看到 description。用 mr-note 格式寫一份（## Summary / ## Changes 表格 | 編號 | 程式碼改動 | 業務層邏輯 | 對應測試 | / ## Test plan / ## Reviewer notes），用 -F <file> 或 --description 帶進來；不要 --fill。"
fi
printf '%s' "$desc" | grep -q '## Changes' || deny "opsx MR 閘門：description 缺 '## Changes' 段。mr-note 格式見 skills/pr/references/mr-note.md。"
printf '%s' "$desc" | grep -qE '\|\s*編號\s*\|' || deny "opsx MR 閘門：'## Changes' 底下缺表格（表頭要有 | 編號 | 程式碼改動 | 業務層邏輯 | 對應測試 |）。"
exit 0
