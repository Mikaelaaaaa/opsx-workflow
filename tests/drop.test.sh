#!/usr/bin/env bash
# opsx drop：捨棄。驗收：specs/board-actions「捨棄收件卡」「沒有理由」「還在跑的卡」「捨棄待分類」（board-inbox 5.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-06 14:30"
A="$(mk_opsx_repo a)"; mkdir -p "$OPSX_STATE_DIR"
X="$(opsx new --repo "$A" -- 要捨棄的)"; Y="$(opsx new --repo "$A" -- 還在跑的)"
CH="$A/openspec/changes"

# --- 沒有理由、多行理由：退出非零，檔案都沒變 ---
snap() { find "$CH" -type f -exec shasum {} + | sort; }
before="$(snap)"
assert_rc 2 opsx drop "$X" --repo "$A" -- ""
assert_rc 2 opsx drop "$X" --repo "$A" -- "$(printf 'a\nb')"
assert_rc 2 opsx drop nope --repo "$A" -- 理由
assert_eq "$(snap)" "$before"; assert_dir "$CH/$X"

# --- 還在跑的卡：拒絕，提示先停止；stopped 的可以捨棄 ---
printf '{"a/%s":{"mode":"autopilot","pane":"p4"}}' "$Y" > "$OPSX_STATE_DIR/dispatch.json"
err="$(opsx drop "$Y" --repo "$A" -- 不要了 2>&1 >/dev/null)"; rc=$?
[ $rc -ne 0 ] || fail "還在跑的卡不能捨棄"
case "$err" in *停止*) ;; *) fail "stderr 要提示先停止：$err" ;; esac
assert_dir "$CH/$Y"

# --- 捨棄收件卡 ---
out="$(opsx drop "$X" --repo "$A" -- 跟 y 重複 2>&1)"; assert_eq "$?" 0 "drop: $out"
assert_no_file "$CH/$X"
D="$CH/archive/2026-11-06-$X"; assert_dir "$D"
assert_grep '^outcome: declined$' "$D/.openspec.yaml"
assert_grep '^## 捨棄理由$' "$D/inbox.md"; assert_grep '^跟 y 重複$' "$D/inbox.md"
assert_grep '捨棄' "$D/decisions.tsv"; assert_grep '跟 y 重複' "$D/decisions.tsv"

printf '{"a/%s":{"mode":"stopped","pane":"p4"}}' "$Y" > "$OPSX_STATE_DIR/dispatch.json"
assert_rc 0 opsx drop "$Y" --repo "$A" -- 停了再丟
assert_dir "$CH/archive/2026-11-06-$Y"

# --- 捨棄待分類：移到 unfiled/dropped/，不刪 ---
U="$(opsx new -- 不需要的)"
assert_rc 2 opsx drop "$U" -- ""
assert_file "$OPSX_STATE_DIR/unfiled/$U.md"
assert_rc 0 opsx drop "$U" -- 不需要
assert_no_file "$OPSX_STATE_DIR/unfiled/$U.md"
assert_file "$OPSX_STATE_DIR/unfiled/dropped/$U.md"; assert_grep '^不需要$' "$OPSX_STATE_DIR/unfiled/dropped/$U.md"
assert_rc 2 opsx drop nope -- 理由

# --- 同一分鐘再新增、再捨棄：dropped/ 裡已有同名檔，不能蓋掉 ---
U2="$(opsx new -- 第二個不需要的)"; assert_eq "$U2" "$U"
assert_rc 0 opsx drop "$U2" -- 也不需要
assert_grep '^不需要的$' "$OPSX_STATE_DIR/unfiled/dropped/$U.md"
assert_grep '^第二個不需要的$' "$OPSX_STATE_DIR/unfiled/dropped/$U-2.md"
echo ok
