#!/usr/bin/env bash
# PostToolUse（Edit|Write）：寫入 openspec/changes/<slug>/gates.md 後，幫 status 是 open、沒有 opened_at 的 gate
# 在 status 行下面補 opened_at（本機時間，offset 帶冒號）。時間由機器產生，agent 手寫的會寫錯時區或忘了寫。
# 工具已經跑完，這支擋不了什麼：讀不到、寫不回都安靜結束，不能卡住 agent。
# OPSX_NOW 只給測試固定時間用。
# 不 source _lib.sh：它開 set -e 並載入 python，這支只要 jq 與 awk（叫 opsx 是另起 process，失敗不管），失敗也不能讓 hook 報錯。
set -uo pipefail
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=/dev/null
source "$root/bin/lib/common.sh"

file="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
case "$file" in */openspec/changes/*/gates.md) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

now="${OPSX_NOW:-$(now_iso)}"

# 一個 gate 從 "## " 行到下一個 "## " 行。status 的判斷跟 stop-gate、collect 一致：值去掉空白後剛好是 open。
new="$(awk -v now="$now" '
  function flush(   i) {
    for (i = 1; i <= n; i++) {
      print buf[i]
      if (i == st && open && !has) print "opened_at: " now
    }
    n = 0; st = 0; open = 0; has = 0
  }
  /^## / { flush() }
  {
    buf[++n] = $0
    if ($0 ~ /^status:[ \t]*open[ \t]*$/) { st = n; open = 1 }
    if ($0 ~ /^opened_at:/) has = 1
  }
  END { flush() }
' "$file")" || exit 0

if [ "$new" != "$(cat "$file")" ]; then
  tmp="$file.tmp.$$"
  printf '%s\n' "$new" > "$tmp" && mv "$tmp" "$file"
fi

# 有 gate 等人就叫 coordinate 馬上跑一輪（規則答得了的答、答不了的通知人），不等 launchd 的 5 分鐘。--kick 放背景就回
if grep -qE '^status:[[:blank:]]*open[[:blank:]]*$' "$file"; then
  bash "$root/bin/opsx" coordinate --kick >/dev/null 2>&1
fi
exit 0
