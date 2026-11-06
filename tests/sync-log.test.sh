#!/usr/bin/env bash
# herdr-board/sync/debt.sh 跑完在 sync.log 留一列（specs/opsx-log「sync.log」的「debt 掃描留紀錄」）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
mkdir -p "$FX/root"; R="$(cd "$FX/root" && mkdir -p a && cd a && git init -q . && pwd -P)"
mkdir -p "$R/openspec" "$R/src"
printf '# shortcut: in-memory cache, go redis when multi-instance\nx = 1\n// shortcut: one worker\n' > "$R/src/app.py"
bash "$OPSX_ROOT/herdr-board/sync/debt.sh" "$FX/root" > "$FX/out.jsonl" || fail "debt rc"
assert_eq "$(wc -l < "$FX/out.jsonl" | tr -d ' ')" 2
assert_eq "$(tail -1 "$OPSX_STATE_DIR/sync.log" | cut -f2-3)" $'debt\t0'
tail -1 "$OPSX_STATE_DIR/sync.log" | cut -f4 | grep -q '2 處 shortcut' || fail "文字要含筆數：$(tail -1 "$OPSX_STATE_DIR/sync.log")"
# 掃不到也留一列
rm "$R/src/app.py"
bash "$OPSX_ROOT/herdr-board/sync/debt.sh" "$FX/root" > "$FX/out2.jsonl" || fail "debt rc 2"
assert_eq "$(wc -c < "$FX/out2.jsonl" | tr -d ' ')" 0
tail -1 "$OPSX_STATE_DIR/sync.log" | cut -f4 | grep -q '0 處 shortcut' || fail "空掃描也要記"
echo ok
