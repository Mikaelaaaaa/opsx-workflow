#!/usr/bin/env bash
# 跑 tests/*.test.sh。每個測試檔自己開 fixture，寫在 $TMPDIR，不碰 plugin 目錄。
# 用法：bash tests/run.sh [pattern]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OPSX_ROOT="$(cd "$HERE/.." && pwd)"
export TMPDIR="${TMPDIR:-/tmp}"
# 沙盒裡 plugin 目錄可能不准 chmod +x：用一個可執行的 shim 轉呼叫，測試不依賴檔案權限
SHIM="$(mktemp -d "$TMPDIR/opsx-shim.XXXXXX")"
printf '#!/usr/bin/env bash\nexec bash "%s/bin/opsx" "$@"\n' "$OPSX_ROOT" > "$SHIM/opsx"; chmod +x "$SHIM/opsx"
export PATH="$SHIM:$PATH"
trap 'rm -rf "$SHIM"' EXIT
pass=0; fail=0; failed=()
for t in "$HERE"/*.test.sh; do
  case "$(basename "$t")" in *"${1:-}"*) ;; *) continue;; esac
  name="$(basename "$t" .test.sh)"
  echo "START $name"; t0=$SECONDS
  out="$(bash "$t" 2>&1)"; rc=$?
  if [ $rc -eq 0 ]; then pass=$((pass+1)); echo "PASS $name ($((SECONDS-t0))s)"
  else fail=$((fail+1)); failed+=("$name"); echo "FAIL $name ($((SECONDS-t0))s)"; echo "$out" | sed 's/^/    /'; fi
done
# python 側（herdr-board/tests/test_*.py，unittest，直接跑檔案：目錄名有連字號不能當模組）
for t in "$OPSX_ROOT"/herdr-board/tests/test_*.py; do
  [ -f "$t" ] || continue
  case "$(basename "$t")" in *"${1:-}"*) ;; *) continue;; esac
  name="$(basename "$t" .py)"
  echo "START $name"; t0=$SECONDS
  out="$(cd "$OPSX_ROOT" && python3 -I "$t" 2>&1)"; rc=$?
  if [ $rc -eq 0 ]; then pass=$((pass+1)); echo "PASS $name ($((SECONDS-t0))s)"
  else fail=$((fail+1)); failed+=("$name"); echo "FAIL $name ($((SECONDS-t0))s)"; echo "$out" | sed 's/^/    /'; fi
done
echo "----"; echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
