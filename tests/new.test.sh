#!/usr/bin/env bash
# opsx new：＋新增。驗收：specs/board-actions「新增到 repo」「同一分鐘兩次」「沒給 repo」「空的一句話」（board-inbox 3.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-06 14:30"
A="$(mk_opsx_repo a)"; B="$(mk_opsx_repo b)"
snap() { find "$A/openspec/changes" "$B/openspec/changes" | sort; }

# --- 新增到 repo ---
out="$(opsx new --repo "$A" -- 聊天視窗被鍵盤蓋住)"; assert_eq "$?" 0 "new: $out"
assert_eq "$out" me-20261106-1430 "stdout 只印 slug"
C="$A/openspec/changes/me-20261106-1430"
assert_file "$C/inbox.md"; assert_grep '^schema: opsx$' "$C/.openspec.yaml"
assert_grep '^type: 功能$' "$C/inbox.md"; assert_grep '^source: me$' "$C/inbox.md"; assert_grep '^found: 2026-11-06$' "$C/inbox.md"
assert_eq "$(awk '/^## 一句話/{f=1;next} f&&NF{print;exit}' "$C/inbox.md")" 聊天視窗被鍵盤蓋住

# --- 同一分鐘兩次 ---
out="$(opsx new --repo "$A" -- 第二件)"; assert_eq "$out" me-20261106-1430-2
assert_grep '^第二件$' "$A/openspec/changes/me-20261106-1430-2/inbox.md"
assert_grep '^聊天視窗被鍵盤蓋住$' "$C/inbox.md"

# --- 沒給 repo：只寫 unfiled/ ---
before="$(snap)"
out="$(opsx new -- 試試看)"; assert_eq "$?" 0; assert_eq "$out" me-20261106-1430
U="$OPSX_STATE_DIR/unfiled/me-20261106-1430.md"
assert_file "$U"; assert_grep '^source: me$' "$U"; assert_grep '^試試看$' "$U"
assert_eq "$(snap)" "$before" "不帶 --repo 不能動任何 repo"
assert_eq "$(opsx new -- 再一個)" me-20261106-1430-2

# --- 空的、多行的一句話：退出非零，什麼都不寫 ---
before="$(snap)"; ub="$(ls "$OPSX_STATE_DIR/unfiled")"
assert_rc 2 opsx new --repo "$A" -- ""
assert_rc 2 opsx new --repo "$A" -- "   "
assert_rc 2 opsx new --repo "$A" -- "$(printf 'a\nb')"
assert_rc 2 opsx new -- ""
assert_rc 2 opsx new --repo "$FX/nope" -- 有字
assert_eq "$(snap)" "$before"; assert_eq "$(ls "$OPSX_STATE_DIR/unfiled")" "$ub"

# --- 並行：同一分鐘 8 個呼叫，slug 互不相同、每張卡內容完整（specs/board-actions「並行新增到…」）---
par_new() { # par_new <輸出目錄> <opsx new 的前置參數…>：同時起 8 個，各帶「並行<i>」
  local out="$1" i; shift
  mkdir -p "$out"
  for i in 1 2 3 4 5 6 7 8; do opsx new "$@" -- "並行$i" > "$out/$i.out" 2> "$out/$i.err" & done
  wait
}
count() { wc -l | tr -d ' '; }
assert_par() { # assert_par <輸出目錄> <slug 前綴> <各卡內容檔的 glob>
  local out="$1" i
  for i in 1 2 3 4 5 6 7 8; do assert_not_grep '失敗' "$out/$i.err"; assert_eq "$(count < "$out/$i.out")" 1 "並行$i 要印一個 slug"; done
  assert_eq "$(cat "$out"/*.out | sort -u | count)" 8 "8 個 slug 要互不相同"
  assert_eq "$(ls -d $2* | count)" 8 "落地的卡要剛好 8 張"
  for i in 1 2 3 4 5 6 7 8; do assert_eq "$(grep -l "^並行$i\$" $3 | count)" 1 "並行$i 的內容要在剛好一張卡裡"; done
}
export OPSX_TEST_NOW="2026-11-06 15:00"
par_new "$FX/par-unfiled"
assert_par "$FX/par-unfiled" "$OPSX_STATE_DIR/unfiled/me-20261106-1500" "$OPSX_STATE_DIR/unfiled/me-20261106-1500*.md"

export OPSX_TEST_NOW="2026-11-06 15:10"
spec_before="$(ls -A "$A/openspec")"
par_new "$FX/par-repo" --repo "$A"
assert_par "$FX/par-repo" "$A/openspec/changes/me-20261106-1510" "$A/openspec/changes/me-20261106-1510*/inbox.md"
assert_eq "$(ls -A "$A/openspec")" "$spec_before" "保留用的東西不能留在 openspec/ 下"

# --- 建殼失敗：退出非零、印原因、只呼叫一次、不留殘渣 ---
export OPSX_TEST_NOW="2026-11-06 15:20"
mkdir -p "$FX/failspec"
printf '#!/usr/bin/env bash\necho "fake openspec: boom" >&2\necho x >> "%s/spec.calls"\nexit 1\n' "$FX" > "$FX/failspec/openspec"; chmod +x "$FX/failspec/openspec"
before="$(snap)"; spec_before="$(ls -A "$A/openspec")"
PATH="$FX/failspec:$PATH" opsx new --repo "$A" -- 有字 > /dev/null 2> "$FX/fail.err"; rc=$?
[ "$rc" -ne 0 ] || fail "openspec 失敗時 opsx new 要退出非零"
assert_grep 'boom' "$FX/fail.err"
assert_eq "$(count < "$FX/spec.calls")" 1 "openspec 失敗不能換 slug 重試"
assert_eq "$(snap)" "$before"; assert_eq "$(ls -A "$A/openspec")" "$spec_before" "失敗後不能留保留殘渣"

# --- 保留剛被別人放掉：mkdir 失敗但保留目錄已不在，不能誤判成建不了，要換下一號（review R1.1）---
export OPSX_TEST_NOW="2026-11-06 15:40"
mkdir -p "$FX/failmkdir"
printf '#!/usr/bin/env bash\ncase "$*" in *.reserve-*) [ -e "%s/mkdir.once" ] || { : > "%s/mkdir.once"; exit 1; };; esac\nexec /bin/mkdir "$@"\n' "$FX" "$FX" > "$FX/failmkdir/mkdir"; chmod +x "$FX/failmkdir/mkdir"
spec_before="$(ls -A "$A/openspec")"
out="$(PATH="$FX/failmkdir:$PATH" opsx new --repo "$A" -- 保留剛被放掉 2>/dev/null)"; assert_eq "$?" 0 "new: $out"
assert_eq "$out" me-20261106-1540-2
assert_grep '^保留剛被放掉$' "$A/openspec/changes/me-20261106-1540-2/inbox.md"
assert_eq "$(ls -A "$A/openspec")" "$spec_before" "保留用的東西不能留在 openspec/ 下"

# --- openspec/ 不可寫：退出非零、說原因，不無限換號 ---
export OPSX_TEST_NOW="2026-11-06 15:50"
chmod a-w "$A/openspec"; before="$(snap)"
opsx new --repo "$A" -- 唯讀 > /dev/null 2> "$FX/ro.err"; rc=$?
chmod u+w "$A/openspec"
[ "$rc" -ne 0 ] || fail "openspec/ 不可寫時 opsx new 要退出非零"
assert_grep '保留' "$FX/ro.err"
assert_eq "$(snap)" "$before"

# --- 待分類寫入失敗：退出非零、不換號、不留 0 byte 的檔（review R1.2）---
export OPSX_TEST_NOW="2026-11-06 16:00"
mkdir -p "$FX/failcat"
printf '#!/usr/bin/env bash\ncase "$1" in *opsx-new.*) echo x >> "%s/cat.calls"; [ "$(wc -l < "%s/cat.calls")" -gt 3 ] || exit 1;; esac\nexec /bin/cat "$@"\n' "$FX" "$FX" > "$FX/failcat/cat"; chmod +x "$FX/failcat/cat"
PATH="$FX/failcat:$PATH" opsx new -- 寫不進去 > /dev/null 2> "$FX/cat.err"; rc=$?
[ "$rc" -ne 0 ] || fail "待分類寫入失敗時 opsx new 要退出非零"
assert_eq "$(ls "$OPSX_STATE_DIR/unfiled" | grep -c 'me-20261106-1600')" 0 "寫入失敗不能留檔（含 0 byte）"
assert_eq "$(count < "$FX/cat.calls")" 1 "寫入失敗不能換號重試"

# --- mkdir 因撞名以外的原因一直失敗（磁碟滿之類）而 openspec/ 可寫：換號有上限，要 die，不能無限換（review R2.1）---
export OPSX_TEST_NOW="2026-11-06 16:10"
mkdir -p "$FX/enospc"
printf '#!/usr/bin/env bash\ncase "$*" in *.reserve-*) echo x >> "%s/mkdir.calls"; echo "mkdir: No space left on device" >&2; exit 1;; esac\nexec /bin/mkdir "$@"\n' "$FX" > "$FX/enospc/mkdir"; chmod +x "$FX/enospc/mkdir"
before="$(snap)"
PATH="$FX/enospc:$PATH" opsx new --repo "$A" -- 磁碟滿 > /dev/null 2> "$FX/enospc.err" &
pid=$!
( sleep 60; kill "$pid" 2>/dev/null ) &
killer=$!
wait "$pid"; rc=$?
kill "$killer" 2>/dev/null
[ "$rc" -ne 0 ] && [ "$rc" -ne 143 ] || fail "mkdir 一直失敗時 opsx new 要自己退出非零（rc=${rc}；143 是被測試的逾時保護殺掉）"
assert_grep 'No space left' "$FX/enospc.err"
[ "$(count < "$FX/mkdir.calls")" -le 1100 ] || fail "換號沒有上限：mkdir 被呼叫 $(count < "$FX/mkdir.calls") 次"
assert_eq "$(snap)" "$before"
echo ok
