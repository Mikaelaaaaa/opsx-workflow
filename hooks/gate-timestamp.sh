#!/usr/bin/env bash
# PostToolUse（Edit|Write）：寫入 openspec/changes/<slug>/gates.md 後做三件事。
# 1. status 是 open、沒有 opened_at 的 gate，在 status 行下面補 opened_at（本機時間，offset 帶冒號）。
#    時間由機器產生，agent 手寫的會寫錯時區或忘了寫。
# 2. type 行的值剛好命中同義詞表（SYN）就改成 approval / decision。值不在表內、或 open 的 gate 沒寫 type，
#    不改檔，用 additionalContext 提醒 agent 合法值；collect 端會把這種 gate 顯示成「type 不明」。
# 3. 檔案裡還有 open 的 gate 就叫 opsx coordinate --kick（放背景就回，失敗不管）。
# 工具已經跑完，這支擋不了什麼：讀不到、寫不回都安靜結束，不能卡住 agent，退出碼永遠 0。
# OPSX_NOW 只給測試固定時間用。
# 不 source _lib.sh：它開 set -e 並載入 python，這支只要 jq 與 awk（叫 opsx 是另起 process，失敗不管），失敗也不能讓 hook 報錯。
# SYN 與 bin/lib/gatetype.py 的 SYNONYMS 是同一張表（awk 不能 import），tests/hooks.test.sh 比對兩份一致。
set -uo pipefail
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=/dev/null
source "$root/bin/lib/common.sh"

SYN='authorization=approval 授權=approval 等待授權=approval 等待決定=decision 決定=decision'

file="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
case "$file" in */openspec/changes/*/gates.md) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

now="${OPSX_NOW:-$(now_iso)}"
# mktemp：隨機名、排他建立，名字不能預先放 symlink
warn="$(mktemp "$file.warn.XXXXXX")" || exit 0

# 一個 gate 從 "## " 行到下一個 "## " 行。status 的判斷跟 stop-gate、collect 一致：值去掉空白後剛好是 open。
new="$(awk -v now="$now" -v syn="$SYN" -v warn="$warn" '
  BEGIN {
    n_syn = split(syn, pair, " ")
    for (i = 1; i <= n_syn; i++) { split(pair[i], kv, "="); map[tolower(kv[1])] = kv[2] }
  }
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function norm(v,   l) {
    l = tolower(v)
    if (l == "approval" || l == "decision") return l
    return (l in map) ? map[l] : ""
  }
  function flush(   i, raw, nv) {
    if (tl) {
      raw = trim(substr(buf[tl], 6)); nv = norm(raw)
      if (nv != "" && raw != nv) buf[tl] = "type: " nv
    }
    if (gid != "" && open && (!tl || norm(raw) == ""))
      print (tl ? "gate " gid " 的 type「" raw "」" : "gate " gid " 沒寫 type") > warn
    for (i = 1; i <= n; i++) {
      print buf[i]
      if (i == st && open && !has) print "opened_at: " now
    }
    n = 0; st = 0; open = 0; has = 0; tl = 0
  }
  /^## / { flush(); gid = trim(substr($0, 4)) }
  {
    buf[++n] = $0
    if ($0 ~ /^status:[ \t]*open[ \t]*$/) { st = n; open = 1 }
    if ($0 ~ /^opened_at:/) has = 1
    if ($0 ~ /^type:/ && !tl) tl = n
  }
  END { flush() }
' "$file")" || { rm -f "$warn"; exit 0; }

if [ "$new" != "$(cat "$file")" ]; then
  # shortcut: mktemp 與寫入之間有毫秒級空窗（要猜到隨機名並換成 symlink），這支不載入 python；要補就改走 safefile.py replace
  tmp="$(mktemp "$file.tmp.XXXXXX")" || { rm -f "$warn"; exit 0; }
  chmod "$(stat -f %Lp "$file" 2>/dev/null || stat -c %a "$file")" "$tmp" 2>/dev/null   # mktemp 是 0600，換名後 gates.md 要保留原權限
  printf '%s\n' "$new" > "$tmp" && mv "$tmp" "$file"
fi

if [ -s "$warn" ]; then
  jq -n --arg t "$(cat "$warn")" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("gates.md 的 type 只能寫 approval | decision（approval 要授權，decision 要決定）：\n" + $t + "\n請改成其中之一，看板才會分對類型；要使用者實際執行指令的另外加 needs: run。")}}' 2>/dev/null
fi
rm -f "$warn"

# 有 gate 等人就叫 coordinate 馬上跑一輪（規則答得了的答、答不了的通知人），不等 launchd 的 5 分鐘。--kick 放背景就回
if grep -qE '^status:[[:blank:]]*open[[:blank:]]*$' "$file"; then
  bash "$root/bin/opsx" coordinate --kick >/dev/null 2>&1
fi
exit 0
