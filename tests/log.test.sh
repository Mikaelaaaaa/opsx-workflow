#!/usr/bin/env bash
# opsx log：decisions.tsv 的列格式 ts · who · tag · 文字 · 證據（specs/opsx-log「decisions.tsv 的列格式」）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo Agentory-AI)"; mk_change "$R" eval-core; cd "$R"
T="$R/openspec/changes/eval-core/decisions.tsv"

# 寫一列
opsx log eval-core claude 替你決定 "選了 SQLite" "bench.txt" || fail "log rc"
python3 -I - "$T" <<'PY' || fail "row shape"
import re, sys
rows = open(sys.argv[1], encoding="utf-8").read().split("\n")
assert rows[-1] == "", rows
cols = rows[0].split("\t")
assert len(cols) == 5, cols
assert re.match(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+08:00$", cols[0]), cols[0]
assert cols[1:] == ["claude", "替你決定", "選了 SQLite", "bench.txt"], cols
PY

# 證據省略：第五欄在，是空字串
opsx log eval-core 你 已停止 停止 || fail "no evidence rc"
assert_eq "$(tail -1 "$T" | awk -F'\t' '{print NF "|" $5}')" "5|"

# 文字裡的 tab 與換行換成空白
opsx log eval-core claude 已決定 "$(printf '第一行\n第二\t段')" || fail "multiline rc"
assert_eq "$(tail -1 "$T" | cut -f4)" "第一行 第二 段"
assert_eq "$(wc -l < "$T" | tr -d ' ')" 3

# 不認得的 tag、who 空白、卡不存在：退出碼 2，不寫
cp "$T" "$FX/before.tsv"
opsx log eval-core claude 隨便 "x" 2> "$FX/err"; assert_eq $? 2; assert_grep '隨便' "$FX/err"
assert_rc 2 opsx log eval-core "" 已決定 "x"
assert_rc 2 opsx log eval-core claude 已決定
cmp -s "$T" "$FX/before.tsv" || fail "decisions 不該變"
assert_rc 2 opsx log nope 你 已決定 "x"
assert_no_file "$R/openspec/changes/nope"

# --repo：不在 repo 裡也能寫
cd "$FX"; opsx log eval-core 你 已決定 "從外面寫" --repo "$R" || fail "--repo"
assert_eq "$(tail -1 "$T" | cut -f4)" "從外面寫"

# 寫進去的列讀得回來（新格式列）
opsx timeline --root "$FX" > "$FX/tl.json" || fail "timeline rc"
python3 -I - "$FX/tl.json" <<'PY' || fail "timeline shape"
import json, sys
d = json.load(open(sys.argv[1]))
assert set(d) >= {"generated_at", "last_seen", "events", "errors"}, d.keys()
ev = d["events"]
assert len(ev) == 4, ev
assert ev[0]["text"] == "從外面寫", ev[0]          # 新的在前；同一秒的列，檔案裡後寫的在前
e = [x for x in ev if x["tag"] == "替你決定"][0]
assert e == {**e, "repo": "Agentory-AI", "slug": "eval-core", "archived": False, "who": "claude",
             "text": "選了 SQLite", "evidence": "bench.txt", "source": "decisions"}, e
assert d["errors"] == [] and d["last_seen"] is None, d
PY

# --sync：寫 <state>/sync.log 一列四欄；新卡數要是非負整數
opsx log --sync gitlab 3 "Agentory-CS 三張新 issue" || fail "sync rc"
assert_eq "$(tail -1 "$OPSX_STATE_DIR/sync.log" | cut -f2-4)" $'gitlab\t3\tAgentory-CS 三張新 issue'
assert_eq "$(tail -1 "$OPSX_STATE_DIR/sync.log" | awk -F'\t' '{print NF}')" 4
cp "$OPSX_STATE_DIR/sync.log" "$FX/sync-before"
assert_rc 2 opsx log --sync gitlab many "x"
assert_rc 2 opsx log --sync gitlab -1 "x"
assert_rc 2 opsx log --sync "" 1 "x"
cmp -s "$OPSX_STATE_DIR/sync.log" "$FX/sync-before" || fail "sync.log 不該變"
echo ok
