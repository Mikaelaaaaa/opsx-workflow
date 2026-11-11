#!/usr/bin/env bash
# tests/lib.sh 的 fixture 根目錄 $FX：TMPDIR 結尾帶 / 時不含連續斜線，TMPDIR 沒設時落在 /tmp。
# 驗收：specs/test-fixture-paths/spec.md「Fixture 路徑不含連續斜線」兩個 Scenario
set -u
: "${OPSX_ROOT:?OPSX_ROOT 未設}"
LIB="$OPSX_ROOT/tests/lib.sh"

BASE="$(mktemp -d "${TMPDIR:-/tmp}/opsx-slash-base.XXXXXX")"
BASE="$(cd "$BASE" && pwd -P)"
TMPDIR="$BASE/"
source "$LIB"
trap 'rm -rf "$FX" "$BASE"' EXIT

case "$FX" in
  *//*) fail "TMPDIR 結尾帶斜線時 FX 不該含連續斜線: $FX" ;;
esac
assert_eq "${FX#"$BASE"/opsx-test.}" "${FX##*/opsx-test.}" "FX 要直接在 TMPDIR 底下"

# TMPDIR 沒設：沙盒的 /tmp 常不可寫，不可寫時略過這一段
if [ -w /tmp ]; then
  out="$(env -u TMPDIR OPSX_ROOT="$OPSX_ROOT" bash -c 'source "$1"; echo "$FX"' _ "$LIB")"
  case "$out" in
    /tmp/opsx-test.*) ;;
    *) fail "TMPDIR 沒設時 FX 要以 /tmp/opsx-test. 開頭: $out" ;;
  esac
fi
echo "tmpdir-trailing-slash: ok"
