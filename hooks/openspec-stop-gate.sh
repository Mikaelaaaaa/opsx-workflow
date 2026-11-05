#!/usr/bin/env bash
# Stop：branch 對到的卡 tasks.md 仍有 - [ ]、status.json tests 不是 green、或有 commit 但 review 沒跑 → block 並說原因。
# 要求檔 §8.5。stop_hook_active 為 true（已經因為這個 hook 續跑過一次）就放行，避免無限迴圈。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[ "$(jqr '.stop_hook_active')" = "true" ] && exit 0
d="$(card_dir)"
[ -n "$d" ] || exit 0
slug="$(card_slug)"
[ -f "$d/tasks.md" ] || exit 0          # 還沒到 apply，不擋

open="$(tasks_open "$d")"
if [ "$open" -gt 0 ]; then
  stop_block "opsx：$slug 的 tasks.md 還有 $open 個 task 沒勾。要停下來就先把做到一半的 task 做完勾起來（測試綠才准勾），或寫 gates.md 說明卡在哪；不要帶著半個 task 收工。"
fi
if [ "$(status_tests "$d")" != green ]; then
  stop_block "opsx：$slug tasks 全勾，但 status.json 的 tests 不是 green（$(status_tests "$d")）。跑 test agent 把整張卡的測試跑到綠，`opsx status apply n/n <label> --tests green`，再停。"
fi
if [ ! -f "$d/report.md" ]; then
  stop_block "opsx：$slug tasks 全勾、測試綠，但還沒 review。跑 /review $slug 產 report.md 再停。"
fi
top="$(repo_top)"
last_commit="$(git -C "$top" log -1 --format=%ct 2>/dev/null || echo 0)"
report_ts="$(stat -f %m "$d/report.md" 2>/dev/null || stat -c %Y "$d/report.md" 2>/dev/null || echo 0)"
if [ "$last_commit" -gt "$report_ts" ]; then
  stop_block "opsx：$slug 在 report.md 之後又有新 commit，review 沒涵蓋到。再跑一次 /review $slug 再停。"
fi
exit 0
