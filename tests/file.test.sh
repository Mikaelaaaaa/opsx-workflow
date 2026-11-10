#!/usr/bin/env bash
# opsx file：待分類搬進 repo。驗收：specs/board-actions「分類」「不存在的待分類」（board-inbox 4.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-06 14:30"
A="$(mk_opsx_repo a)"

# --- 分類：內容原樣、unfiled 的檔不在了 ---
assert_eq "$(opsx new -- 試試看)" me-20261106-1430
U="$OPSX_STATE_DIR/unfiled/me-20261106-1430.md"; cp "$U" "$FX/orig.md"
out="$(opsx file me-20261106-1430 --repo "$A")"; assert_eq "$?" 0 "file: $out"
assert_eq "$out" me-20261106-1430
C="$A/openspec/changes/me-20261106-1430"
assert_eq "$(cat "$C/inbox.md")" "$(cat "$FX/orig.md")"; assert_grep '^schema: opsx$' "$C/.openspec.yaml"
assert_no_file "$U"

# --- repo 裡已有同名：加 -2，原本的不動 ---
assert_eq "$(opsx new -- 第二件)" me-20261106-1430
assert_eq "$(opsx file me-20261106-1430 --repo "$A")" me-20261106-1430-2
assert_grep '^第二件$' "$A/openspec/changes/me-20261106-1430-2/inbox.md"; assert_grep '^試試看$' "$C/inbox.md"

# --- 不存在的待分類、沒給 repo、不合格的 slug：退出非零，repo 沒有新資料夾 ---
before="$(find "$A/openspec/changes" | sort)"
assert_rc 2 opsx file nope --repo "$A"
assert_rc 2 opsx file me-20261106-1430
assert_rc 2 opsx file ../x --repo "$A"
assert_eq "$(find "$A/openspec/changes" | sort)" "$before"

# --- 分類帶著附件 ---
printf 'png-bytes' > "$FX/shot.png"
export OPSX_TEST_NOW="2026-11-06 15:00"
assert_eq "$(opsx new --attach "$FX/shot.png" -- 有附件)" me-20261106-1500
out="$(opsx file me-20261106-1500 --repo "$A")"; assert_eq "$?" 0 "file 附件: $out"
assert_eq "$out" me-20261106-1500
assert_eq "$(cat "$A/openspec/changes/me-20261106-1500/attachments/shot.png")" png-bytes
assert_no_file "$OPSX_STATE_DIR/unfiled/me-20261106-1500.md"; assert_no_file "$OPSX_STATE_DIR/unfiled/me-20261106-1500"

# --- 分類撞名時附件跟著改名的殼 ---
printf 'other' > "$FX/b.txt"
assert_eq "$(opsx new --attach "$FX/b.txt" -- 撞名的附件)" me-20261106-1500
assert_eq "$(opsx file me-20261106-1500 --repo "$A")" me-20261106-1500-2
assert_eq "$(cat "$A/openspec/changes/me-20261106-1500-2/attachments/b.txt")" other
assert_no_file "$A/openspec/changes/me-20261106-1500/attachments/b.txt"
assert_eq "$(ls "$A/openspec/changes/me-20261106-1500/attachments")" shot.png "原本的殼不變"
assert_no_file "$OPSX_STATE_DIR/unfiled/me-20261106-1500"
echo ok
