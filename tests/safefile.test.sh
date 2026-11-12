#!/usr/bin/env bash
# bin/lib/safefile.py：不跟 symlink 的開檔，與隨機暫存檔加換名。specs/symlink-safe-writes/spec.md。
source "$(dirname "$0")/lib.sh"
PY="$(cat "$OPSX_STATE_DIR/python")"
LIB="$OPSX_ROOT/bin/lib"
D="$FX/sf"; mkdir -p "$D"

mode() { "$PY" -I -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"; }
hash_of() { shasum "$1" | cut -d' ' -f1; }
new_victim() { printf 'keep me\n' > "$D/victim"; }

# --- CLI append：建檔、再附加 ---
printf 'one\n' | "$PY" -I "$LIB/safefile.py" append "$D/log" || fail "append rc"
printf 'two\n' | "$PY" -I "$LIB/safefile.py" append "$D/log" || fail "append again rc"
assert_eq "$(cat "$D/log")" "$(printf 'one\ntwo')" "append 要接在後面"

# --- CLI append：路徑是 symlink → 退出碼 2、訊息含路徑、目標不變 ---
new_victim; before="$(hash_of "$D/victim")"
ln -s "$D/victim" "$D/linklog"
printf 'x\n' | "$PY" -I "$LIB/safefile.py" append "$D/linklog" 2> "$D/err"; rc=$?
assert_eq "$rc" 2 "append symlink 要退出 2"
assert_grep "$D/linklog" "$D/err"
assert_eq "$(hash_of "$D/victim")" "$before" "append 不能寫到 symlink 的目標"

# --- CLI append：dangling symlink 也拒絕，目標不會被建出來 ---
ln -s "$D/never-created" "$D/dangling"
printf 'x\n' | "$PY" -I "$LIB/safefile.py" append "$D/dangling" 2>/dev/null; rc=$?
assert_eq "$rc" 2 "dangling symlink 要退出 2"
assert_no_file "$D/never-created"

# --- CLI replace：內容換成 stdin ---
printf 'old\n' > "$D/doc"
printf 'new\n' | "$PY" -I "$LIB/safefile.py" replace "$D/doc" || fail "replace rc"
assert_eq "$(cat "$D/doc")" "new"

# --- Scenario「換名後保留權限」：原檔 0644 → 換名後仍 0644（mkstemp 預設 0600） ---
printf 'old\n' > "$D/gates"; chmod 644 "$D/gates"
printf 'new\n' | "$PY" -I "$LIB/safefile.py" replace "$D/gates" || fail "replace rc"
assert_eq "$(mode "$D/gates")" "0o644" "要保留原檔權限"
printf 'old\n' > "$D/private"; chmod 600 "$D/private"
printf 'new\n' | "$PY" -I "$LIB/safefile.py" replace "$D/private" || fail "replace rc"
assert_eq "$(mode "$D/private")" "0o600" "0600 的原檔要保持 0600"

# --- Scenario「新檔的權限」：umask 022、目標不存在 → 0644 ---
( umask 022; printf 'x\n' | "$PY" -I "$LIB/safefile.py" replace "$D/fresh" ) || fail "replace new rc"
assert_eq "$(mode "$D/fresh")" "0o644" "新檔要是 0666 & ~umask"

# --- Scenario「暫存檔名被占」：舊的固定暫存檔名上的 symlink 不被寫 ---
new_victim; before="$(hash_of "$D/victim")"
printf 'old\n' > "$D/memo.json"
ln -s "$D/victim" "$D/memo.json.tmp"
printf 'fresh\n' | "$PY" -I "$LIB/safefile.py" replace "$D/memo.json" || fail "replace rc"
assert_eq "$(cat "$D/memo.json")" "fresh"
assert_eq "$(hash_of "$D/victim")" "$before" "暫存檔名上的 symlink 不能被寫"
rm -f "$D/memo.json.tmp"

# --- replace 不留暫存檔 ---
leftover="$(ls -A "$D" | grep -c '\.tmp$' || true)"
assert_eq "$leftover" 0 "不留暫存檔"

# --- Scenario「鎖檔是 symlink」（API）：open_lock 拒絕，目標不被截斷 ---
new_victim; before="$(hash_of "$D/victim")"
ln -s "$D/victim" "$D/x.lock"
out="$("$PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1]); import safefile
try:
    safefile.open_lock(sys.argv[2])
except safefile.SymlinkRefused as e:
    print("refused", e)
' "$LIB" "$D/x.lock")"
assert_eq "${out%% *}" refused "open_lock 要丟 SymlinkRefused"
case "$out" in *"$D/x.lock"*) ;; *) fail "訊息要含路徑：$out";; esac
assert_eq "$(hash_of "$D/victim")" "$before" "open_lock 不能截斷 symlink 的目標"

# --- open_lock：一般路徑會建檔，且不截斷已有內容 ---
printf 'content\n' > "$D/real.lock"
"$PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1]); import safefile
safefile.open_lock(sys.argv[2]).close()
' "$LIB" "$D/real.lock" || fail "open_lock 一般檔 rc"
assert_eq "$(cat "$D/real.lock")" "content" "open_lock 不能截斷"

# --- Scenario「鎖檔是 symlink」：jsonfile.update 拒絕，dispatch.json 不被寫、目標不被截斷 ---
new_victim; before="$(hash_of "$D/victim")"
ln -s "$D/victim" "$D/dispatch.json.lock"
out="$("$PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1]); import jsonfile, safefile
def mutate(d): d["k"] = 1
try:
    jsonfile.update(sys.argv[2], mutate)
except safefile.SymlinkRefused as e:
    print("refused", e)
' "$LIB" "$D/dispatch.json")"
assert_eq "${out%% *}" refused "jsonfile.update 要丟 SymlinkRefused"
case "$out" in *dispatch.json.lock*) ;; *) fail "訊息要含 dispatch.json.lock：$out";; esac
assert_eq "$(hash_of "$D/victim")" "$before" "jsonfile.update 不能截斷 symlink 的目標"
assert_no_file "$D/dispatch.json"

# --- CardLock：另一個 process 持鎖時，要鎖的人等到放鎖才進去 ---
mkdir -p "$D/card"; : > "$D/lock-order"
"$PY" -I -c '
import sys, time
sys.path.insert(0, sys.argv[1]); import safefile
with safefile.CardLock(sys.argv[2]):
    open(sys.argv[3], "w").close()
    time.sleep(1)
    open(sys.argv[4], "a").write("release\n")
' "$LIB" "$D/card" "$D/lock-ready" "$D/lock-order" &
for _ in $(seq 100); do [ -e "$D/lock-ready" ] && break; sleep 0.05; done
[ -e "$D/lock-ready" ] || fail "持鎖的 process 沒有拿到鎖"
"$PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1]); import safefile
with safefile.CardLock(sys.argv[2]):
    open(sys.argv[3], "a").write("waiter\n")
' "$LIB" "$D/card" "$D/lock-order" || fail "CardLock 等鎖失敗"
wait
assert_eq "$(cat "$D/lock-order")" "$(printf 'release\nwaiter')" "持鎖者放鎖後，等鎖的才能進去"

# --- CardLock：卡目錄不存在 → 大聲失敗、報出路徑、不建東西 ---
"$PY" -I -c '
import sys
sys.path.insert(0, sys.argv[1]); import safefile
with safefile.CardLock(sys.argv[2]):
    pass
' "$LIB" "$D/no-such-card" 2> "$D/err"; rc=$?
[ "$rc" -ne 0 ] || fail "卡目錄不存在要失敗"
assert_grep "$D/no-such-card" "$D/err"
assert_no_file "$D/no-such-card"

# --- Requirement「drive 與 coordinate 的 log 附加寫入不經 shell 重導向」：檢查與開檔之間不能有空窗 ---
if grep -qE '>> *"\$(out|drivelog)"' "$OPSX_ROOT/bin/lib/coordinate.sh" "$OPSX_ROOT/bin/lib/dispatch.sh" "$OPSX_ROOT/hooks/opsx-herdr-queue.sh"; then
  fail "coordinate.out 與 drive log 的附加要走 opsx_append（safefile.py），不能用 shell 的 >>"
fi
# --- Requirement「gate-timestamp 改寫 gates.md 走 safefile」：不用 mktemp 加 mv ---
if grep -q 'mv "\$tmp"' "$OPSX_ROOT/hooks/gate-timestamp.sh"; then fail "gate-timestamp 改寫 gates.md 要走 opsx_replace，不能 mktemp 加 mv"; fi

# --- exec-append：指令的 stdout 與 stderr 附加到 log；log 是 symlink 時指令不跑、退出 2、目標不變 ---
printf 'keep\n' > "$D/run.log"
"$PY" -I "$LIB/safefile.py" exec-append "$D/run.log" sh -c 'echo out; echo err >&2' || fail "exec-append rc"
assert_eq "$(cat "$D/run.log")" "$(printf 'keep\nout\nerr')" "exec-append 要把 stdout 與 stderr 附加在後面"
new_victim; before="$(hash_of "$D/victim")"; ln -sf "$D/victim" "$D/linkrun"
"$PY" -I "$LIB/safefile.py" exec-append "$D/linkrun" sh -c 'echo evil' 2> "$D/err"; rc=$?
assert_eq "$rc" 2 "exec-append symlink 要退出 2"
assert_grep "$D/linkrun" "$D/err"
assert_eq "$(hash_of "$D/victim")" "$before" "exec-append 不能寫到 symlink 的目標"

echo "safefile ok"
