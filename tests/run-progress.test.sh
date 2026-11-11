#!/usr/bin/env bash
# tests/run.sh 逐檔輸出：START、PASS|FAIL <name> (<n>s)、總結行與退出碼。
# 驗收：specs/test-runner-progress/spec.md 的前三條 Requirement
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# run.sh 的 HERE 與 OPSX_ROOT 都從自己的位置推出來：複製進臨時的 tests/，旁邊放假測試
T="$FX/runner/tests"; mkdir -p "$T"
cp "$OPSX_ROOT/tests/run.sh" "$T/run.sh"
printf '#!/usr/bin/env bash\nsleep 3\n' > "$T/a-slow.test.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/b-ok.test.sh"
printf '#!/usr/bin/env bash\necho boom-line >&2\nexit 1\n' > "$T/c-bad.test.sh"

OUT="$FX/out.txt"
bash "$T/run.sh" > "$OUT" 2>&1 &
pid=$!

# 開始行先於結果行：a-slow 還在 sleep 時，START 已經寫出，PASS 還沒有
for _ in $(seq 50); do grep -q '^START a-slow$' "$OUT" && break; sleep 0.1; done
assert_grep '^START a-slow$' "$OUT"
assert_not_grep '^PASS a-slow' "$OUT"

rc=0; wait "$pid" || rc=$?

# 結果行帶秒數，失敗檔的原輸出縮排接在 FAIL 行後面
assert_grep '^PASS a-slow ([0-9][0-9]*s)$' "$OUT"
assert_grep '^PASS b-ok ([0-9][0-9]*s)$' "$OUT"
assert_grep '^FAIL c-bad ([0-9][0-9]*s)$' "$OUT"
assert_eq "$(grep -A1 '^FAIL c-bad' "$OUT" | tail -1)" "    boom-line"
# START 在同一檔的結果之前
[ "$(grep -n '^START c-bad$' "$OUT" | cut -d: -f1)" -lt "$(grep -n '^FAIL c-bad' "$OUT" | cut -d: -f1)" ] || fail "START c-bad 要在 FAIL c-bad 之前"

# 總結行與退出碼不變
assert_eq "$(grep '^pass=' "$OUT")" "pass=2 fail=1"
[ "$rc" -ne 0 ] || fail "有失敗時退出碼要非 0"
