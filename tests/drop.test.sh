#!/usr/bin/env bash
# opsx drop：捨棄。驗收：specs/board-actions「捨棄收件卡」「沒有理由」「還在跑的卡」「捨棄待分類」（board-inbox 5.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-06 14:30"
cd "$FX"   # 從 dispatch 的 worktree 跑時，cwd 不能讓 opsx new 把 fixture 的卡當成 agent 開的
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
# 歸檔日期是 openspec archive 取的真實今天，假 date 管不到，所以照 slug 找
arch=("$CH"/archive/*-"$X"); assert_eq "${#arch[@]}" 1 "archive/*-$X"; D="${arch[0]}"; assert_dir "$D"
assert_grep '^outcome: declined$' "$D/.openspec.yaml"
assert_grep '^## 捨棄理由$' "$D/inbox.md"; assert_grep '^跟 y 重複$' "$D/inbox.md"
assert_grep '捨棄' "$D/decisions.tsv"; assert_grep '跟 y 重複' "$D/decisions.tsv"
assert_grep $'\t你\t已決定\t捨棄：跟 y 重複\t' "$D/decisions.tsv"

printf '{"a/%s":{"mode":"stopped","pane":"p4"}}' "$Y" > "$OPSX_STATE_DIR/dispatch.json"
assert_rc 0 opsx drop "$Y" --repo "$A" -- 停了再丟
arch=("$CH"/archive/*-"$Y"); assert_eq "${#arch[@]}" 1 "archive/*-$Y"; assert_dir "${arch[0]}"

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

# --- 捨棄待分類帶著附件：資料夾跟 .md 同名；dropped/ 只剩同名資料夾也不能蓋掉 ---
printf 'png-bytes' > "$FX/shot.png"
export OPSX_TEST_NOW="2026-11-06 15:00"
P="$(opsx new --attach "$FX/shot.png" -- 有附件不需要)"
assert_rc 0 opsx drop "$P" -- 不需要
assert_file "$OPSX_STATE_DIR/unfiled/dropped/$P.md"
assert_eq "$(cat "$OPSX_STATE_DIR/unfiled/dropped/$P/attachments/shot.png")" png-bytes
assert_no_file "$OPSX_STATE_DIR/unfiled/$P.md"; assert_no_file "$OPSX_STATE_DIR/unfiled/$P"
rm "$OPSX_STATE_DIR/unfiled/dropped/$P.md"
P2="$(opsx new --attach "$FX/shot.png" -- 又一個)"; assert_eq "$P2" "$P"
assert_rc 0 opsx drop "$P2" -- 也不要
assert_file "$OPSX_STATE_DIR/unfiled/dropped/$P-2.md"; assert_file "$OPSX_STATE_DIR/unfiled/dropped/$P-2/attachments/shot.png"
assert_no_file "$OPSX_STATE_DIR/unfiled/dropped/$P.md"

# --- 還有 ## 併入 段的卡：拒絕，列出 id、提示先 opsx split-out，什麼都不動（併入項目不能跟著歸檔）---
export OPSX_TEST_NOW="2026-11-06 16:00"
M="$(opsx new --repo "$A" -- 有併入的)"
printf '\n## 併入：2026-11-06T16:00:00+08:00 agent:foo\n\n- id: agent-20261106-1600\n- kind_of_work: planned\n- area: hooks\n\n別人的問題\n' >> "$CH/$M/inbox.md"
before="$(snap)"
err="$(opsx drop "$M" --repo "$A" -- 不要了 2>&1 >/dev/null)"; rc=$?
[ $rc -ne 0 ] || fail "還有併入段的卡不能捨棄"
case "$err" in *agent-20261106-1600*split-out*|*split-out*agent-20261106-1600*) ;; *) fail "stderr 要列出 id 並提示 split-out：$err" ;; esac
assert_eq "$(snap)" "$before"; assert_dir "$CH/$M"

# --- drop-card-lock：另一個行程持卡鎖時，drop 的無鎖預檢已過；它放鎖前寫進一段併入，drop 取得鎖後要重查並拒絕 ---
PYBIN="$(cat "$OPSX_STATE_DIR/python")"; LIBDIR="$OPSX_ROOT/bin/lib"
hold_lock() { # hold_lock <卡目錄> <動作>：持卡鎖，等 $FX/go 出現後做動作（merge 併入一段 / move 搬走目錄）再放鎖
  rm -f "$FX/held" "$FX/go"
  "$PYBIN" -I -c '
import os, sys, time
sys.path.insert(0, sys.argv[1]); import safefile, inboxmerge
card, act = sys.argv[2], sys.argv[3]
with safefile.CardLock(card):
    open(sys.argv[4], "w").close()
    while not os.path.exists(sys.argv[5]):
        time.sleep(0.02)
    if act == "merge":
        p = os.path.join(card, "inbox.md")
        with open(p, encoding="utf-8") as f:
            cur = f.read()
        safefile.write_atomic(p, cur + "\n" + inboxmerge.section("late-1", "2026-11-11T10:00:00+08:00", "agent:t", "planned", "", "hooks", "晚到的併入"))
    else:
        os.rename(card, card + ".moved")
' "$LIBDIR" "$1" "$2" "$FX/held" "$FX/go" &
  HOLDER=$!
  for _ in $(seq 100); do [ -e "$FX/held" ] && break; sleep 0.05; done
  [ -e "$FX/held" ] || fail "持鎖的 process 沒有拿到鎖"
}
L="$(opsx new --repo "$A" -- 鎖內重查)"
hold_lock "$CH/$L" merge
opsx drop "$L" --repo "$A" -- 不要了 > "$FX/drop.out" 2>&1 &
DROP=$!
sleep 1; : > "$FX/go"
wait "$HOLDER"; wait "$DROP"; rc=$?
[ $rc -ne 0 ] || fail "鎖內重查發現併入段，drop 要失敗：$(cat "$FX/drop.out")"
assert_grep 'late-1' "$FX/drop.out"
assert_dir "$CH/$L"; assert_not_grep '^outcome: declined$' "$CH/$L/.openspec.yaml"; assert_not_grep '捨棄理由' "$CH/$L/inbox.md"
arch=("$CH"/archive/*-"$L"); [ ! -e "${arch[0]}" ] || fail "卡不能被歸檔"

# --- drop-card-lock：取得鎖時卡目錄已被搬走：非 0 退出、指出路徑、不建任何東西 ---
L2="$(opsx new --repo "$A" -- 拿鎖前被搬走)"
hold_lock "$CH/$L2" move
opsx drop "$L2" --repo "$A" -- 不要了 > "$FX/drop.out" 2>&1 &
DROP=$!
sleep 1; : > "$FX/go"
wait "$HOLDER"; wait "$DROP"; rc=$?
[ $rc -ne 0 ] || fail "卡目錄被搬走，drop 要失敗：$(cat "$FX/drop.out")"
assert_grep "$CH/$L2" "$FX/drop.out"
assert_no_file "$CH/$L2"; assert_not_grep '捨棄' "$CH/$L2.moved/decisions.tsv"
assert_not_grep '^outcome: declined$' "$CH/$L2.moved/.openspec.yaml"; assert_not_grep '捨棄理由' "$CH/$L2.moved/inbox.md"

# --- drop-card-lock：archive 進行中，另一個行程 opsx new 要併進同一張卡：等鎖，放鎖後併不進（不是併進歸檔的卡）---
printf 'hooks\n' > "$A/openspec/areas.txt"
mkdir -p "$A/.claude/worktrees" "$FX/slowbin"
git -C "$A" worktree add -q -b fix/foo/mikaela "$A/.claude/worktrees/foo" || fail "worktree foo 建不起來"
W="$(cd "$A/.claude/worktrees/foo" && pwd -P)"
T=target
mkdir -p "$CH/$T"; printf 'schema: opsx\n' > "$CH/$T/.openspec.yaml"
printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-10\nrelated:\nkind_of_work: planned\narea: hooks\n---\n\n## 一句話\n\n要被捨棄的\n\n## 證據\n\n' > "$CH/$T/inbox.md"
printf '#!/usr/bin/env bash\n: > "$OPSX_TEST_ARCHIVING"\nwhile [ ! -e "$OPSX_TEST_RELEASE" ]; do sleep 0.02; done\nmkdir -p openspec/changes/archive\nmv "openspec/changes/$2" "openspec/changes/archive/2026-11-11-$2"\n' > "$FX/slowbin/openspec"; chmod +x "$FX/slowbin/openspec"
export OPSX_TEST_ARCHIVING="$FX/archiving" OPSX_TEST_RELEASE="$FX/release"; rm -f "$OPSX_TEST_ARCHIVING" "$OPSX_TEST_RELEASE"
PATH="$FX/slowbin:$PATH" opsx drop "$T" --repo "$A" -- 不要了 > "$FX/drop.out" 2>&1 &
DROP=$!
for _ in $(seq 100); do [ -e "$OPSX_TEST_ARCHIVING" ] && break; sleep 0.05; done
[ -e "$OPSX_TEST_ARCHIVING" ] || fail "drop 沒有跑到 archive：$(cat "$FX/drop.out")"
(cd "$W" && opsx new --kind-of-work planned --area hooks --repo "$A" -- 晚到的併入) > "$FX/new.out" 2> "$FX/new.err" &
NEW=$!
sleep 1
assert_not_grep '晚到的併入' "$CH/$T/inbox.md"
: > "$OPSX_TEST_RELEASE"
wait "$DROP"; assert_eq "$?" 0 "drop: $(cat "$FX/drop.out")"
wait "$NEW"; rc=$?
[ $rc -ne 0 ] || fail "卡已歸檔，opsx new 不能併進去：$(cat "$FX/new.out")"
assert_grep '併不進' "$FX/new.err"
assert_not_grep '晚到的併入' "$CH/archive/2026-11-11-$T/inbox.md"
echo ok
