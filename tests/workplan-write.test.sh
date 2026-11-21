#!/usr/bin/env bash
# bin/lib/workplanwrite.py：在 workplan.yaml 加 feature／PR／change，原有的行逐字不變；寫入持 workplan 鎖。
# 驗收：openspec/changes/workplan-attach/subs/workplan-writer/specs/workplan-attach/spec.md
source "$(dirname "$0")/lib.sh"
LIB="$OPSX_ROOT/bin/lib"
R="$FX/r"; mkdir -p "$R/openspec"
WP="$R/openspec/workplan.yaml"

BASE='created: 2026-11-18

milestones:
  - name: m1
    status: active

# 註解
features:
  - name: f1
    description: "a: b"
    status: active
    depends-on: [x, y]
    prs:
      - name: p1
        branch: feat/p1/m
        status: pending
        depends-on: []
        changes:
          - name: c1
            status: pending
'
F2='{"name":"f2","status":"active","depends-on":[],"prs":[{"name":"p9","branch":"feat/p9/m","status":"pending","depends-on":[],"changes":[{"name":"p9","status":"pending"}]}]}'
P2='{"name":"p2","branch":"feat/p2/m","status":"pending","depends-on":[],"changes":[{"name":"p2","status":"pending"}]}'
C2='{"name":"c2","status":"pending"}'

reset() { printf '%s' "$1" > "$WP"; cp "$WP" "$FX/orig"; }
# add <add_feature|add_pr|add_change> [<目標名>] <item JSON>
add() { python3 -I -c 'import json, sys
sys.path.insert(0, sys.argv[1]); import workplanwrite
getattr(workplanwrite, sys.argv[2])(sys.argv[3], *sys.argv[4:-1], json.loads(sys.argv[-1]))' "$LIB" "$1" "$R" "${@:2}"; }
# 新檔跟原檔比，只有插入、沒有改或刪：印 ok，否則印 difflib 的 opcode
only_inserts() { python3 -I -c 'import difflib, sys
a = open(sys.argv[1], encoding="utf-8").read().split("\n"); b = open(sys.argv[2], encoding="utf-8").read().split("\n")
ops = [op for op in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes() if op[0] != "equal"]
print("ok" if ops and all(op[0] == "insert" for op in ops) else ops)' "$FX/orig" "$WP"; }
# 讀回：印 load_workplan 結果上的一個 python 運算式
wp() { python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1]); import chain
w = chain.load_workplan(sys.argv[2])
f1 = w["features"][0]; p1 = f1["prs"][0]
print(eval(sys.argv[3]))' "$LIB" "$WP" "$1"; }

# --- Scenario Outline「加項目後原有的行不變」：一般場景 ---
reset "$BASE"
add add_feature "$F2" || fail "add_feature rc"
assert_eq "$(only_inserts)" ok "加 feature 只能插入行"
assert_eq "$(wp 'w["features"][1]["name"]')" f2
assert_eq "$(wp 'w["features"][1]["prs"][0]["changes"][0]["name"]')" p9 "新 feature 的 PR 與 change 也要讀得回來"
want='  - name: "f2"
    status: "active"
    depends-on: []
    prs:
      - name: "p9"
        branch: "feat/p9/m"
        status: "pending"
        depends-on: []
        changes:
          - name: "p9"
            status: "pending"'
assert_eq "$(tail -n 11 "$WP")" "$want" "新 feature 的排版：縮排照清單第一項、字串加雙引號"

reset "$BASE"
add add_pr f1 "$P2" || fail "add_pr rc"
assert_eq "$(only_inserts)" ok "加 PR 只能插入行"
assert_eq "$(wp 'f1["prs"][1]["name"]')" p2

reset "$BASE"
add add_change p1 "$C2" || fail "add_change rc"
assert_eq "$(only_inserts)" ok "加 change 只能插入行"
assert_eq "$(wp 'p1["changes"][1]["name"]')" c2
assert_eq "$(wp 'f1["description"]')" "a: b" "引號字串照讀"
assert_eq "$(wp 'f1["depends-on"]')" "['x', 'y']" "[a, b] 清單照讀"

# --- 邊界：原檔沒有結尾換行 ---
reset "${BASE%$'\n'}"
add add_feature "$F2" || fail "add_feature 無結尾換行 rc"
assert_eq "$(only_inserts)" ok "沒有結尾換行時也只插入行"
assert_eq "$(wp 'w["features"][1]["name"]')" f2

# --- 邊界：f1 是最後一個 feature，後面接註解行與別的區塊；新 PR 不能插到註解後面 ---
reset "$BASE"'
# 尾註
notes: keep
'
add add_pr f1 "$P2" || fail "add_pr 尾註 rc"
assert_eq "$(only_inserts)" ok "後面接註解時只插入行"
assert_eq "$(wp 'f1["prs"][1]["name"]')" p2
pr_at="$(grep -n 'branch: "feat/p2/m"' "$WP" | cut -d: -f1)"; note_at="$(grep -n '^# 尾註' "$WP" | cut -d: -f1)"
[ "$pr_at" -lt "$note_at" ] || fail "新 PR 要在尾註之前：p2 在第 $pr_at 行、尾註在第 $note_at 行"
assert_eq "$(sed -n "$((note_at - 2)),$((note_at - 1))p" "$WP")" '            status: "pending"' "新 PR 的最後一行之後是原本的空行與尾註"

# --- 空清單 `features: []`、`prs: []`、`changes: []`：換成區塊清單再插第一項，其他行逐字不變（workplan-attach D10）---
# empty_ok <key>：原檔只把第一個 `<key>: []` 改成 `<key>:`，其餘只有插入
empty_ok() { awk -v k="$1" '!d && $0 ~ "^ *" k ": \\[\\]$" { sub(/ \[\]$/, ""); d = 1 } 1' "$FX/orig" > "$FX/orig2"; cp "$FX/orig2" "$FX/orig"; only_inserts; }
reset 'created: 2026-11-18

features: []
'
add add_feature "$F2" || fail "features: [] 時 add_feature rc"
assert_eq "$(empty_ok features)" ok "features: [] 只改那一行、其餘插入"
assert_eq "$(wp 'w["features"][0]["name"]')" f2
reset 'features:
  - name: f1
    status: active
    prs: []
  - name: f3
    status: active
    prs: []
'
add add_pr f1 "$P2" || fail "prs: [] 時 add_pr rc"
assert_eq "$(empty_ok prs)" ok "prs: [] 只改那一行、其餘插入"
assert_eq "$(wp 'f1["prs"][0]["name"]')" p2
assert_eq "$(wp 'w["features"][1]["prs"]')" "[]" "另一個 feature 的 prs: [] 不動"
reset 'features:
  - name: f1
    status: active
    prs:
      - name: p1
        branch: feat/p1/m
        changes: []
'
add add_change p1 "$C2" || fail "changes: [] 時 add_change rc"
assert_eq "$(empty_ok changes)" ok "changes: [] 只改那一行、其餘插入"
assert_eq "$(wp 'p1["changes"][0]["name"]')" c2

# --- 區塊頭底下沒有項目（只有註解、空行，或直接接下一個區塊）也是空清單：插在區塊頭下一行（workplan-attach D10）---
reset 'features:
# 都清掉了

notes: keep
'
add add_feature "$F2" || fail "沒有項目的 features: 時 add_feature rc"
assert_eq "$(only_inserts)" ok "沒有項目的 features: 只插入行"
assert_eq "$(wp 'w["features"][0]["name"]')" f2
assert_eq "$(sed -n 2p "$WP")" '  - name: "f2"' "新 feature 插在 features: 的下一行，註解之前"
reset 'features:
  - name: f1
    status: active
    prs:
  - name: f3
    status: active
    prs:
'
add add_pr f1 "$P2" || fail "沒有項目的 prs: 時 add_pr rc"
assert_eq "$(only_inserts)" ok "沒有項目的 prs: 只插入行"
assert_eq "$(wp 'f1["prs"][0]["name"]')" p2
assert_eq "$(wp 'w["features"][1]["prs"]')" None "另一個 feature 沒有項目的 prs: 不動"
reset 'features:
  - name: f1
    status: active
    prs:
      - name: p1
        branch: feat/p1/m
        changes:
'
add add_change p1 "$C2" || fail "沒有項目的 changes: 時 add_change rc"
assert_eq "$(only_inserts)" ok "沒有項目的 changes: 只插入行"
assert_eq "$(wp 'p1["changes"][0]["name"]')" c2

# --- Scenario「名字已存在就拒絕」 ---
reset "$BASE"
add add_feature '{"name":"f1","status":"active"}' 2> "$FX/err"; rc=$?
[ "$rc" -ne 0 ] || fail "feature 重名要失敗"
assert_grep f1 "$FX/err"
cmp -s "$FX/orig" "$WP" || fail "重名時 workplan 不能被改"
add add_pr f1 '{"name":"p1","status":"pending"}' 2> "$FX/err"; rc=$?
[ "$rc" -ne 0 ] || fail "PR 重名要失敗"
assert_grep p1 "$FX/err"
add add_change p1 '{"name":"c1","status":"pending"}' 2> "$FX/err"; rc=$?
[ "$rc" -ne 0 ] || fail "change 重名要失敗"
assert_grep c1 "$FX/err"
cmp -s "$FX/orig" "$WP" || fail "重名時 workplan 不能被改"

# --- 目標不存在、值放不進雙引號：報錯指名，不寫 ---
add add_pr nope "$P2" 2> "$FX/err"; rc=$?
[ "$rc" -ne 0 ] || fail "feature 不存在要失敗"
assert_grep nope "$FX/err"
add add_change nope "$C2" 2> "$FX/err"; rc=$?
[ "$rc" -ne 0 ] || fail "PR 不存在要失敗"
assert_grep nope "$FX/err"
add add_feature '{"name":"b\"ad","status":"active"}' 2> "$FX/err"; rc=$?
[ "$rc" -ne 0 ] || fail "值含雙引號要失敗"
assert_grep 'b"ad' "$FX/err"
cmp -s "$FX/orig" "$WP" || fail "報錯時 workplan 不能被改"

# --- Scenario「讀回驗證失敗不吞」：讀回看不到新項目 → 還原並報錯 ---
python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1]); import chain, workplanwrite
chain.load_workplan = lambda path: {"features": []}
workplanwrite.add_feature(sys.argv[2], {"name": "f2", "status": "active"})' "$LIB" "$R" 2> "$FX/err"; rc=$?
[ "$rc" -ne 0 ] || fail "讀回驗證失敗要報錯"
assert_grep f2 "$FX/err"
cmp -s "$FX/orig" "$WP" || fail "讀回驗證失敗要還原成寫入前的內容"

# hold <ready 檔>：背景持 workplan 鎖，讀檔、睡 1 秒、在讀到的內容後加一行 `# H` 寫回（模擬另一個讀改寫的寫入者）
hold() { python3 -I -c 'import sys, time
sys.path.insert(0, sys.argv[1]); import safefile, workplanwrite
with workplanwrite.WorkplanLock(sys.argv[2]):
    text = open(sys.argv[3], encoding="utf-8").read()
    open(sys.argv[4], "w").close()
    time.sleep(1)
    safefile.write_atomic(sys.argv[3], text + "# H\n")' "$LIB" "$R" "$WP" "$1" & }
wait_ready() { for _ in $(seq 100); do [ -e "$1" ] && return 0; sleep 0.05; done; fail "持鎖的 process 沒有拿到鎖"; }

# --- Scenario「兩個寫入者先後寫都留下」：加 feature 等鎖 ---
reset "$BASE"
hold "$FX/ready1"; wait_ready "$FX/ready1"
add add_feature "$F2" || fail "等鎖的 add_feature rc"
wait
assert_grep '^# H$' "$WP"
assert_eq "$(wp 'w["features"][1]["name"]')" f2 "持鎖者寫完後，加 feature 的改動也要留下"

# --- 同上：coordinate.mark_merged 等同一把鎖 ---
mark() { python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1]); import coordinate
sys.exit(0 if coordinate.Round(sys.argv[2], False).mark_merged(sys.argv[3], sys.argv[4]) else 1)' "$LIB" "$FX/cstate" "$R" "$1" > /dev/null; }
mkdir -p "$FX/cstate"
reset "$BASE"
hold "$FX/ready2"; wait_ready "$FX/ready2"
mark c1 || fail "等鎖的 mark_merged rc"
wait
assert_grep '^# H$' "$WP"
assert_eq "$(wp 'p1["changes"][0]["status"]')" done "持鎖者寫完後，mark_merged 的 status 也要留下"

# --- 寫入端加的 change 名字帶引號，mark_merged 照樣標得到 ---
reset "$BASE"
add add_change p1 "$C2" || fail "add_change rc"
mark c2 || fail "mark_merged 找不到帶引號的 change：$(cat "$FX/cstate/coordinator.log")"
assert_eq "$(wp 'p1["changes"][1]["status"]')" done

echo "workplan-write ok"
