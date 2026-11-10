#!/usr/bin/env bash
# opsx reap [--root <dir>] [--pane <id>] [--dry]：關掉孤兒 pane（卡已歸檔 / 已拆 / stopped，agent 是 idle，pane 上沒有活卡）。
# 判斷在 reap.py；孤兒清單來自 opsx collect 的 orphans[]。specs/opsx-reap/spec.md。

opsx_reap() {
  "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/reap.py" "$OPSX_STATE_DIR" "$OPSX_ROOT/bin/opsx" "$@"
}
