#!/usr/bin/env bash
# herdr action open-pane：在目前的 workspace 以 overlay 開看板的 TUI pane（manifest 的 [[panes]] board）。
# 鍵綁不到 pane，只綁得到 action，所以要這一層；綁法見 README 看板段。
set -euo pipefail
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open --plugin opsx-board --entrypoint board --placement overlay --focus
