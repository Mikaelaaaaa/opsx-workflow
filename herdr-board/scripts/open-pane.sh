#!/usr/bin/env bash
# herdr action open-pane：在按鍵的 pane 右邊以 split 開看板的 TUI pane（manifest 的 [[panes]] board）；
# 這個 tab 已經有看板 pane 就只 focus 它，不疊第二個。鍵綁不到 pane，只綁得到 action，所以要這一層；綁法見 README 看板段。
# 只看本 tab：別的 tab 的看板 pane 要先 herdr tab focus 才跳得過去，按鍵的人要的是眼前看到看板。
set -euo pipefail
pane="${HERDR_PANE_ID:?HERDR_PANE_ID 未設：open-pane 要由 herdr action 叫}"
tab="${HERDR_TAB_ID:?HERDR_TAB_ID 未設：open-pane 要由 herdr action 叫}"
ws="${HERDR_WORKSPACE_ID:?HERDR_WORKSPACE_ID 未設：open-pane 要由 herdr action 叫}"
herdr="${HERDR_BIN_PATH:-herdr}"

# label 是 manifest [[panes]] board 的 title；pane list 沒有 plugin id 可認
existing="$("$herdr" pane list --workspace "$ws" | python3 -I -c '
import json, sys
tab = sys.argv[1]
for p in json.load(sys.stdin)["result"]["panes"]:
    if p["tab_id"] == tab and p.get("label") == "opsx":
        print(p["pane_id"]); break
' "$tab")"

# 用 pane focus 不用 plugin pane focus：後者對 pane list 列出的看板 pane 實跑回過 plugin_pane_not_found，pane focus 認的就是 pane_id
if [ -n "$existing" ]; then
  exec "$herdr" pane focus "$existing"
fi
exec "$herdr" plugin pane open --plugin opsx-board --entrypoint board --placement split --direction right --target-pane "$pane" --focus
