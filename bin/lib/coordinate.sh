#!/usr/bin/env bash
# opsx coordinate [--dry]：中控跑一輪就結束，launchd 每 5 分鐘叫一次（init.sh 的 com.opsx.coordinate）。
# 判斷與動作都在 coordinate.py；log 在 <state>/coordinator.log。specs/opsx-coordinate/spec.md。

opsx_coordinate() {
  local dry=""
  while [ $# -gt 0 ]; do
    case "$1" in --dry) dry=--dry; shift ;; *) die "coordinate: 不認得的參數 $1" ;; esac
  done
  "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/coordinate.py" "$OPSX_STATE_DIR" $dry
}
