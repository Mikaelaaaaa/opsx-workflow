#!/usr/bin/env bash
# opsx 與 hooks 叫的 python：opsx init --global 記在 $OPSX_STATE_DIR/python 的絕對路徑，不用 PATH 上的 python3。
# pyenv 的 shim 每次啟動多 250 ms 左右，hooks 每個 tool call 都要叫。讀檔只用 builtin，不 fork。
# 找不到就失敗、不退回 python3：退回就是原本那個慢的狀態，而且沒人會發現。

# 成功：設 OPSX_PY，回 0。失敗：設 OPSX_PY_ERR（原因與修法），回 1。
opsx_python_load() {
  local f="$OPSX_STATE_DIR/python"
  OPSX_PY=""; OPSX_PY_ERR=""
  if [ ! -f "$f" ]; then OPSX_PY_ERR="找不到 ${f}（記 python 路徑的檔）。跑 opsx init --global"; return 1; fi
  IFS= read -r OPSX_PY < "$f" || true
  if [ -z "$OPSX_PY" ]; then OPSX_PY_ERR="$f 是空的。跑 opsx init --global"; return 1; fi
  if [ ! -f "$OPSX_PY" ] || [ ! -x "$OPSX_PY" ]; then
    OPSX_PY_ERR="$f 記的 python 不是可執行檔：${OPSX_PY}（pyenv 換過版本，或 venv 被刪了？）。跑 opsx init --global"; OPSX_PY=""; return 1
  fi
}

# 寫沙盒可寫目錄裡的固定檔名：內容從 stdin 來，路徑是 symlink 時退出 2 並說明路徑，目標不動。specs/symlink-safe-writes。
# 要先 opsx_python_load；OPSX_PY 是空的就是「找不到指令」，不退回 shell 的 >> 與 >。
opsx_append()  { "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/safefile.py" append "$1"; }
opsx_replace() { "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/safefile.py" replace "$1"; }
