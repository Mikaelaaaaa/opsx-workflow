#!/usr/bin/env bash
# opsx sync [--source gitlab|github|debt] [--root ~/code]：把來源撈進收件匣。本體在 sync.py（去重索引、建殼、標記、sync.log、鎖）。
# 退出碼：0 跑完（個別來源失敗記在 sync.log 的 errors），2 參數錯，3 另一支 sync 還在跑。specs/board-sync。

opsx_sync() {
  "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/sync.py" --state "$OPSX_STATE_DIR" --opsx-root "$OPSX_ROOT" "$@"
}
