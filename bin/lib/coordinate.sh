#!/usr/bin/env bash
# opsx coordinate [--dry | --kick]：中控跑一輪就結束，launchd 每 5 分鐘叫一次（init.sh 的 com.opsx.coordinate）。
# 判斷與動作都在 coordinate.py；log 在 <state>/coordinator.log。specs/opsx-coordinate/spec.md。

opsx_coordinate() {
  local dry=""
  while [ $# -gt 0 ]; do
    case "$1" in --dry) dry=--dry; shift ;; --kick) coordinate_kick; return 0 ;; *) die "coordinate: 不認得的參數 $1" ;; esac
  done
  "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/coordinate.py" "$OPSX_STATE_DIR" $dry
}

# hook 與 drive 在事件發生時叫：一輪要等 collect 查 glab，叫的人不能等，所以放背景就回。
# HERDR_ENV=1 跟 launchd 那輪一樣：沒有它 collect 不問 herdr，coordinate 會整輪拒跑。輸出跟 launchd 寫同一個檔。
coordinate_kick() {
  local out="$OPSX_STATE_DIR/coordinate.out"
  if ! : 2>/dev/null >> "$out"; then
    printf '%s ?? coordinate --kick 起不來：寫不了 %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$out" >> "$OPSX_STATE_DIR/coordinator.log"
    return 0
  fi
  HERDR_ENV=1 nohup bash "$OPSX_ROOT/bin/opsx" coordinate < /dev/null >> "$out" 2>&1 &
}
