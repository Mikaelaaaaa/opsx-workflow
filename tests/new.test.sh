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

# --- 附檔（新增時附檔）---
export OPSX_TEST_NOW="2026-11-06 15:00"
T="$FX/att"; mkdir -p "$T/x" "$T/y"
printf 'png-bytes' > "$T/shot.png"; printf 'log line\n' > "$T/log.txt"
printf 'first' > "$T/x/a.png"; printf 'second' > "$T/y/a.png"

# 附檔建在 repo
out="$(opsx new --repo "$A" --attach "$T/shot.png" --attach "$T/log.txt" -- 聊天視窗被鍵盤蓋住)"; assert_eq "$?" 0 "new --attach: $out"
assert_eq "$out" me-20261106-1500
C="$A/openspec/changes/me-20261106-1500"
assert_eq "$(cat "$C/attachments/shot.png")" png-bytes; assert_eq "$(cat "$C/attachments/log.txt")" "log line"
assert_grep '^source: paste$' "$C/inbox.md"
assert_eq "$(awk '/^## 附件/{f=1;next} /^## /{f=0} f&&NF' "$C/inbox.md")" "$(printf -- '- attachments/shot.png\n- attachments/log.txt')"
assert_eq "$(grep -n '^## ' "$C/inbox.md" | cut -d: -f2-)" "$(printf '## 一句話\n## 附件\n## 證據')" "## 附件 在 ## 證據 之前"

# 沒附檔照舊
out="$(opsx new --repo "$A" -- 試試看)"; assert_eq "$out" me-20261106-1500-2
assert_grep '^source: me$' "$A/openspec/changes/$out/inbox.md"
assert_not_grep '^## 附件' "$A/openspec/changes/$out/inbox.md"
assert_no_file "$A/openspec/changes/$out/attachments"

# 同名附件
out="$(opsx new --repo "$A" --attach "$T/x/a.png" --attach "$T/y/a.png" --attach "$T/x/a.png" -- 同名)"; assert_eq "$?" 0 "new 同名: $out"
D="$A/openspec/changes/$out/attachments"
assert_eq "$(cat "$D/a.png")" first; assert_eq "$(cat "$D/a-2.png")" second; assert_eq "$(cat "$D/a-3.png")" first
assert_grep '^- attachments/a.png$' "$A/openspec/changes/$out/inbox.md"; assert_grep '^- attachments/a-2.png$' "$A/openspec/changes/$out/inbox.md"
assert_grep '^- attachments/a-3.png$' "$A/openspec/changes/$out/inbox.md"
printf 'm' > "$T/Makefile"; printf 'n' > "$T/y/Makefile"
out="$(opsx new --repo "$A" --attach "$T/Makefile" --attach "$T/y/Makefile" -- 沒副檔名)"
assert_eq "$(cat "$A/openspec/changes/$out/attachments/Makefile-2")" n "沒副檔名的同名加 -2"

# 附檔進待分類
before="$(snap)"
out="$(opsx new --attach "$T/shot.png" -- 試試看)"; assert_eq "$?" 0 "new unfiled --attach: $out"
assert_eq "$out" me-20261106-1500
assert_file "$OPSX_STATE_DIR/unfiled/$out.md"; assert_grep '^source: paste$' "$OPSX_STATE_DIR/unfiled/$out.md"
assert_grep '^- attachments/shot.png$' "$OPSX_STATE_DIR/unfiled/$out.md"
assert_eq "$(cat "$OPSX_STATE_DIR/unfiled/$out/attachments/shot.png")" png-bytes
assert_eq "$(snap)" "$before" "附檔進待分類不能動任何 repo"

# 待分類撞名：只剩 <slug>/ 也算撞名
rm "$OPSX_STATE_DIR/unfiled/me-20261106-1500.md"
assert_eq "$(opsx new -- 撿到舊附件嗎)" me-20261106-1500-2
assert_no_file "$OPSX_STATE_DIR/unfiled/me-20261106-1500.md"

# 檔案太大、附件不存在、不是一般檔案：退出非零，什麼都不寫
truncate -s 10485760 "$T/edge.bin"; truncate -s 10485761 "$T/big.bin"
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
err="$(opsx new --repo "$A" --attach "$T/shot.png" --attach "$T/big.bin" -- 太大 2>&1 >/dev/null)"; rc=$?
assert_eq "$rc" 2 "太大要退出 2：$err"
case "$err" in *big.bin*10\ MB*) ;; *) fail "stderr 要含檔名與 10 MB：$err" ;; esac
assert_rc 2 opsx new --attach "$T/big.bin" -- 太大
assert_rc 2 opsx new --repo "$A" --attach "$T/nope.png" -- 不存在
assert_rc 2 opsx new --attach "$T/nope.png" -- 不存在
assert_rc 2 opsx new --attach "$T/x" -- 是資料夾
assert_rc 2 opsx new --attach -- 沒給檔
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub"
out="$(opsx new --repo "$A" --attach "$T/edge.bin" -- 剛好十MB)"; assert_eq "$?" 0 "剛好 10 MB 要收：$out"
assert_file "$A/openspec/changes/$out/attachments/edge.bin"
echo ok
