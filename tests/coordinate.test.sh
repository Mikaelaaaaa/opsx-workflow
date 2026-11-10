#!/usr/bin/env bash
# opsx coordinate：中控跑一輪。opsx / git / openspec / gh / herdr 全是 fake，斷言它叫了哪些指令、寫了哪些 log。
# 驗收：specs/opsx-coordinate/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo demo)"          # 真 git 建好 fixture 之後才換成 fake git
mkdir -p "$R/openspec/changes"
use_fakes opsx git openspec gh herdr
export OPSX_FAKE_LOG="$FX/fake.log" OPSX_TEST_COLLECT_JSON="$FX/collect.json"
LOG="$OPSX_STATE_DIR/coordinator.log"; MEMO="$OPSX_STATE_DIR/coordinator-memo.json"; DISP="$OPSX_STATE_DIR/dispatch.json"

# cards '<卡的 JSON 陣列，只寫跟預設不同的欄位>' ['<errors JSON 陣列>']：寫成 opsx collect 的輸出
cards() {
  python3 -I - "$R" "$1" "${2:-[]}" > "$OPSX_TEST_COLLECT_JSON" <<'PY'
import json, sys
top, given, errors = sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3])
base = {"repo": "demo", "kind": "dev", "stage": "apply", "section": "待指派", "archived": False,
        "waiting": None, "open_gates": [], "dispatch": None, "agent_status": None, "mr": None}
out = [{**base, **c, "path": "%s/openspec/changes/%s" % (top, c["slug"])} for c in given]
print(json.dumps({"repo_paths": {"demo": top}, "cards": out, "errors": errors}, ensure_ascii=False))
PY
}
mkcard() { local s; for s in "$@"; do mkdir -p "$R/openspec/changes/$s"; printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/$s/tasks.md"; done; }
round() { : > "$OPSX_FAKE_LOG"; : > "$LOG"; bash "$OPSX_ROOT/bin/opsx" coordinate "$@" > "$FX/out" 2>&1; }
count() { grep -c -- "$1" "$OPSX_FAKE_LOG" || true; }
memo_get() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], {}).get(sys.argv[3], ""))' "$MEMO" "$1" "$2"; }
ago() { python3 -I -c 'import datetime,sys; print((datetime.datetime.now().astimezone()-datetime.timedelta(minutes=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
D='{"mode":"autopilot","agent":"claude","pane":"w1:p1","drive_pid":null}'
READY='{"url":"https://github.com/o/r/pull/7","state":"ready","head_sha":"abc","conditions":{"no_conflicts":true},"merged_at":null}'

# --- 讀不到狀態就失敗：herdr ---
mkcard a
cards '[{"slug":"a"}]' '[{"source":"herdr","message":"不在 herdr 內（HERDR_ENV 未設）"}]'
round; rc=$?
[ $rc -ne 0 ] || fail "herdr 讀不到要非 0：$(cat "$FX/out")"
assert_grep herdr "$LOG"
assert_eq "$(grep -cv '^opsx collect' "$OPSX_FAKE_LOG")" 0 "herdr 讀不到不能做任何動作"

# --- 讀不到狀態就失敗：memo 壞掉 ---
cards '[{"slug":"a"}]'
printf '{' > "$MEMO"
round; rc=$?
[ $rc -ne 0 ] || fail "memo 壞掉要非 0"
assert_eq "$(cat "$MEMO")" "{" "memo 壞掉不能被改寫"
assert_eq "$(count '^opsx dispatch')" 0
rm -f "$MEMO"

# --- 派卡：收件匣不派、沒 tasks.md 不派、有 MR 不派 ---
mkdir -p "$R/openspec/changes/i" "$R/openspec/changes/nt"; mkcard hasmr
cards '[{"slug":"i","section":"收件匣","stage":"explore"},{"slug":"nt","stage":"propose"},{"slug":"hasmr","stage":"babysit","mr":'"$READY"'}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "收件匣、沒 tasks.md、有 MR 都不派：$(cat "$OPSX_FAKE_LOG")"
rm -f "$MEMO"

# --- 派卡：依賴沒合不派 ---
cat > "$R/openspec/workplan.yaml" <<'EOF'
created: 2026-11-07

features:
  - name: demo
    status: active
    prs:
      - name: p
        branch: feat/p/m
        status: pending
        depends-on: []
        changes:
          - name: p
            status: pending
      - name: d-pr                # PR 名跟 change 名不同：依賴要從 change 對到它的 PR
        branch: feat/d/m
        status: pending
        depends-on: [p]
        changes:
          - name: d
            status: pending
      - name: g
        branch: feat/g/m
        status: pending
        depends-on: []
        changes:
          - name: g
            status: pending
      - name: core              # 一個 PR 兩個 change：兩個都 done 才算 merged
        branch: feat/core/m
        status: in-progress
        depends-on: []
        changes:
          - name: ca
            status: pending
          - name: cb
            status: pending
      - name: af
        branch: feat/af/m
        status: pending
        depends-on: [core]
        changes:
          - name: af
            status: pending
EOF
WP0="$FX/workplan.orig"; cp "$R/openspec/workplan.yaml" "$WP0"
mkcard d
cards '[{"slug":"d"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "依賴沒合不派"
grep '⏳' "$LOG" | grep -q 'p' || fail "log 要有 ⏳ 與依賴名：$(cat "$LOG")"

# --- 派卡：一輪最多六張，參數照卡 ---
mkcard s1 s2 s3 s4 s5 s6 s7 s8
cards '[{"slug":"s1"},{"slug":"s2"},{"slug":"s3"},{"slug":"s4"},{"slug":"s5"},{"slug":"s6"},{"slug":"s7"},{"slug":"s8","kind":"bug-fix"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 6 "一輪最多六張：$(cat "$OPSX_FAKE_LOG")"
assert_grep "^opsx dispatch s1 --agent claude --mode autopilot --kind dev --repo $R\$" "$OPSX_FAKE_LOG"
rm -f "$MEMO"

# --- 派卡：人停掉的不派 ---
mkcard h
printf '{"demo/h":{"mode":"stopped","agent":"claude","pane":"w1:p9","drive_pid":null}}' > "$DISP"
cards '[{"slug":"h"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "人停掉的不派"
rm -f "$DISP" "$MEMO"

# --- --dry 只印 ---
mkcard x
cards '[{"slug":"x"}]'
round --dry || fail "dry rc: $(cat "$FX/out")"
assert_grep "DRY opsx dispatch x" "$FX/out"
assert_eq "$(count '^opsx dispatch')" 0 "dry 不能真的派"
assert_no_file "$MEMO"

# --- 合併：ready 的卡走 opsx merge，不直接合 ---
mkcard m
cards '[{"slug":"m","section":"待處理","stage":"babysit","dispatch":'"$D"',"agent_status":"idle","mr":'"$READY"'}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx merge m --repo $R\$" "$OPSX_FAKE_LOG"
assert_not_grep 'pr merge' "$OPSX_FAKE_LOG"; assert_not_grep 'mr merge' "$OPSX_FAKE_LOG"
assert_eq "$(memo_get _approved demo/m)" "abc"
grep '++' "$LOG" | grep -q m || fail "核准要記 ++：$(cat "$LOG")"

# --- 合併：同一個 sha 不重複核准 ---
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx merge')" 0 "同一個 sha 不重複核准"
rm -f "$MEMO"

# --- 合併：有衝突不合 ---
cards '[{"slug":"m","section":"進行中","stage":"babysit","dispatch":'"$D"',"agent_status":"idle","mr":{"url":"https://github.com/o/r/pull/7","state":"conflicts","head_sha":"abc","conditions":{"no_conflicts":false},"merged_at":null}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx merge')" 0 "有衝突不合"

# --- 合併：被拒記 ??，這輪繼續 ---
cards '[{"slug":"m","section":"待處理","stage":"babysit","dispatch":'"$D"',"agent_status":"idle","mr":'"$READY"'},{"slug":"x"}]'
OPSX_TEST_FAIL_merge="merge: demo/m 是互動模式，沒有授權閘門" round || fail "rc: $(cat "$FX/out")"
grep '??' "$LOG" | grep m | grep -q '互動模式' || fail "被拒要記 ?? 與原因：$(cat "$LOG")"
assert_grep '^opsx dispatch x ' "$OPSX_FAKE_LOG"
assert_eq "$(memo_get _approved demo/m)" "" "被拒不算核准過"
rm -f "$MEMO"

# merged <slug> <merged_at> <dispatch JSON 或 null> <agent_status JSON 或 null>：forge 上已合的卡
merged() { printf '{"slug":"%s","section":"進行中","stage":"babysit","dispatch":%s,"agent_status":%s,"mr":{"url":"https://github.com/o/r/pull/8","state":"state:MERGED","head_sha":"def","conditions":{},"merged_at":"%s"}}' "$1" "$3" "$4" "$2"; }
wp_status() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[3]); import chain
for f in chain.load_workplan(sys.argv[1])["features"]:
    for pr in f["prs"]:
        if pr["name"] == sys.argv[2]: print(pr["status"])' "$R/openspec/workplan.yaml" "$1" "$OPSX_ROOT/bin/lib"; }
wp_change() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[3]); import chain
for f in chain.load_workplan(sys.argv[1])["features"]:
    for pr in f["prs"]:
        for c in pr.get("changes") or []:
            if c["name"] == sys.argv[2]: print(c["status"])' "$R/openspec/workplan.yaml" "$1" "$OPSX_ROOT/bin/lib"; }

# --- 收尾：forge 上已合、agent 不在、主 checkout 在 main 且乾淨 ---
mkcard g; mkdir -p "$R/.claude/worktrees/g-wt"
printf '{"demo/g":{"mode":"stopped","agent":"claude","pane":"w1:p2","drive_pid":null,"branch":"feat/g/m","worktree":"%s"}}' "$R/.claude/worktrees/g-wt" > "$DISP"
G="$(merged g 2026-11-07T12:00:00Z null null)"
cards "[$G]"
round || fail "rc: $(cat "$FX/out")"
got="$(grep -E '^(git|opsx stop|openspec)' "$OPSX_FAKE_LOG")"
want="git -C $R rev-parse --abbrev-ref HEAD
git -C $R status --porcelain
git -C $R pull -q --ff-only
openspec archive g -y
git -C $R worktree remove $R/.claude/worktrees/g-wt
git -C $R branch -D feat/g/m
git -C $R worktree prune"
assert_eq "$got" "$want" "收尾順序（不 checkout、worktree 用 dispatch.json 記的、不 --force）"
assert_eq "$(wp_status g)" merged "workplan 的 PR 要標 merged"
assert_eq "$(wp_change g)" done "workplan 的 change 要標 done"
grep '++' "$LOG" | grep -q g || fail "收尾要記 ++：$(cat "$LOG")"
cp "$WP0" "$R/openspec/workplan.yaml"

# --- 收尾：主 checkout 不在 main 或有改動就不 pull，也不 checkout ---
OPSX_TEST_GIT_BRANCH=feat/x round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count 'pull')" 0 "不在 main 不 pull"; assert_eq "$(count 'checkout')" 0 "永遠不 checkout"
assert_grep '^openspec archive g -y$' "$OPSX_FAKE_LOG"
grep -q 'feat/x' "$LOG" || fail "要記不 pull 的原因：$(cat "$LOG")"
cp "$WP0" "$R/openspec/workplan.yaml"
OPSX_TEST_GIT_DIRTY=" M x.txt" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count 'pull')" 0 "有改動不 pull"
cp "$WP0" "$R/openspec/workplan.yaml"

# --- 收尾：worktree 刪不掉就不刪分支 ---
OPSX_TEST_GIT_FAIL=remove round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count 'branch -D')" 0 "worktree 刪不掉不刪分支"
grep '??' "$LOG" | grep -q g || fail "要記 ??：$(cat "$LOG")"
cp "$WP0" "$R/openspec/workplan.yaml"

# --- 收尾：agent 還在就交給它自己 /archive ---
cards "[$(merged g "$(ago 10)" "$D" '"idle"')]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(grep -cE '^(opsx stop|openspec archive|git .*worktree remove|git .*branch -D)' "$OPSX_FAKE_LOG")" 0 "agent 還在不收尾：$(cat "$OPSX_FAKE_LOG")"
grep '⏳' "$LOG" | grep -q g || fail "要記 ⏳：$(cat "$LOG")"
assert_eq "$(wp_status g)" pending "agent 還在不動 workplan"

# --- 收尾：drive 死了但 agent 還在（可能正在 /archive）不收尾 ---
sleep 0 & dead=$!; wait "$dead"
cards "[$(merged g "$(ago 10)" '{"mode":"autopilot","agent":"claude","pane":"w1:p1","drive_pid":'"$dead"'}' '"working"')]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(grep -cE '^(opsx stop|openspec archive)' "$OPSX_FAKE_LOG")" 0 "drive 死了不等於 agent 不在：$(cat "$OPSX_FAKE_LOG")"

# --- 收尾：合併超過 30 分鐘、agent 在忙，只記 ?? ---
cards "[$(merged g "$(ago 40)" "$D" '"working"')]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count 'openspec archive')" 0
grep '??' "$LOG" | grep -q g || fail "超過 30 分鐘記 ??：$(cat "$LOG")"

# --- 收尾：網頁上合併、agent idle 超過 30 分鐘，沒人會 /archive，coordinator 收 ---
printf '{"demo/g":{"mode":"autopilot","agent":"claude","pane":"w1:p2","drive_pid":null,"branch":"feat/g/m"}}' > "$DISP"
cards "[$(merged g "$(ago 40)" "$D" '"idle"')]"
round || fail "rc: $(cat "$FX/out")"
got="$(grep -E '^(opsx stop|openspec archive)' "$OPSX_FAKE_LOG")"
assert_eq "$got" "opsx stop g --repo $R
openspec archive g -y" "idle 超過 30 分鐘要 stop 再收尾：$(cat "$OPSX_FAKE_LOG")"
cp "$WP0" "$R/openspec/workplan.yaml"

# --- 收尾：idle 超過 30 分鐘，但卡上有 open gate（在等人回）或是互動模式（人暫時離開），不收尾、記 ?? ---
cards "[$(merged g "$(ago 40)" "$D" '"idle"' | sed 's/^{/{"open_gates":[{"id":"g9","opened_at":null}],/')]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(grep -cE '^(opsx stop|openspec archive)' "$OPSX_FAKE_LOG")" 0 "有 open gate 不收尾：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep -q g || fail "有 open gate 要記 ??：$(cat "$LOG")"
printf '{"demo/g":{"mode":"interactive","agent":"claude","pane":"w1:p2","drive_pid":null,"branch":"feat/g/m"}}' > "$DISP"
cards "[$(merged g "$(ago 40)" "$D" '"idle"')]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(grep -cE '^(opsx stop|openspec archive)' "$OPSX_FAKE_LOG")" 0 "互動模式不收尾：$(cat "$OPSX_FAKE_LOG")"
cp "$WP0" "$R/openspec/workplan.yaml"

# --- 收尾：沒派過的卡（dispatch.json 沒有）不收尾，留給人 ---
rm -f "$DISP"
cards "[$(merged g 2026-11-07T12:00:00Z null null)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(grep -cE '^(opsx stop|openspec archive|git .*worktree remove|git .*branch -D)' "$OPSX_FAKE_LOG")" 0 "沒派過不收尾：$(cat "$OPSX_FAKE_LOG")"
grep -- '--' "$LOG" | grep -q 'demo/g' || fail "要記 --：$(cat "$LOG")"
assert_eq "$(wp_status g)" pending "沒派過不動 workplan"

# --- 收尾：一個 PR 兩個 change，只收了一個，PR 不標 merged、依賴它的不派 ---
mkcard ca af
printf '{"demo/ca":{"mode":"stopped","agent":"claude","pane":"w1:p5","drive_pid":null,"branch":"feat/core/m"}}' > "$DISP"
cards "[$(merged ca 2026-11-07T12:00:00Z null null),{\"slug\":\"af\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(wp_change ca)" done "收尾的 change 標 done"
assert_eq "$(wp_status core)" in-progress "cb 還沒 done，PR 不標 merged"
assert_eq "$(count '^opsx dispatch af')" 0 "core 沒 merged，依賴它的不派：$(cat "$OPSX_FAKE_LOG")"
assert_grep '^openspec archive ca -y$' "$OPSX_FAKE_LOG"
cp "$WP0" "$R/openspec/workplan.yaml"; rm -f "$DISP" "$MEMO"

# --- 收尾：依賴它的卡同一輪派出（PR 名跟 change 名不同） ---
mkcard p
printf '{"demo/p":{"mode":"stopped","agent":"claude","pane":"w1:p4","drive_pid":null,"branch":"feat/p/m"}}' > "$DISP"
cards "[$(merged p 2026-11-07T12:00:00Z null null),{\"slug\":\"d\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx dispatch d --agent claude --mode autopilot --kind dev --repo $R\$" "$OPSX_FAKE_LOG"
cp "$WP0" "$R/openspec/workplan.yaml"
rm -f "$MEMO" "$DISP"

# --- 答 gate：授權題允許這次 ---
mkcard a1
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待授權","gate_id":"g1","action":"push","question":"要 push","recommended":null,"options":["這次"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx answer a1 --gate g1 --grant this --repo $R -- 允許\$" "$OPSX_FAKE_LOG"

# --- 答 gate：合併的授權題不代答（合併只走 opsx merge 的五條件核准，D3） ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待授權","gate_id":"g8","action":"merge","question":"要合併","recommended":null,"options":["這次"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "合併的授權題不代答：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep a1 | grep -q g8 || fail "合併授權題要記 ??：$(cat "$LOG")"

# --- 答 gate：要人動手的不代答 ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","gate_id":"g5","question":"這段怎麼驗","recommended":"你在 sandbox 外跑","options":["你在 sandbox 外跑","略過"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "要人動手的不代答"
grep '??' "$LOG" | grep a1 | grep -q g5 || fail "要記 ?? 與 gate id：$(cat "$LOG")"

# --- 答 gate：沒派出去的不答 ---
cards '[{"slug":"a1","section":"待處理","dispatch":null,"waiting":{"type":"等待授權","gate_id":"g1","action":"push","question":"要 push","recommended":null,"options":["這次"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "沒派出去的不答"

# --- 答 gate：真機題標等使用者驗 ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","gate_id":"g2","question":"這要真機跑一次嗎","recommended":"跑","options":["跑","不跑"]}}]'
round || fail "rc: $(cat "$FX/out")"
grep '^opsx answer a1 --gate g2 ' "$OPSX_FAKE_LOG" | grep '等使用者驗' | grep -q 'report.md' || fail "真機題的答案：$(cat "$OPSX_FAKE_LOG")"

# --- 答 gate：沒有建議就答第一個選項；answer 失敗不換參數重送 ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","gate_id":"g3","question":"選哪個","recommended":null,"options":["甲","乙"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx answer a1 --gate g3 --repo $R -- 甲\$" "$OPSX_FAKE_LOG"
OPSX_TEST_FAIL_answer="answer: boom" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 1 "answer 失敗不重送"
grep '??' "$LOG" | grep -q boom || fail "answer 失敗記 ??：$(cat "$LOG")"

# --- 答 gate：終端機等待輸入只記 ?? ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"blocked","waiting":{"type":"終端機等待輸入","gate_id":null,"question":"agent 在終端機等輸入","recommended":"開啟 pane","options":["開啟 pane"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0; grep '??' "$LOG" | grep -q a1 || fail "終端機等輸入記 ??"
rm -f "$MEMO"

# --- 等別張卡：停下並記 parked ---
mkcard p1
cards '[{"slug":"p1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","gate_id":"g7","question":"等 a 合進 main 之後再做","recommended":null,"options":["等"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx stop p1 --repo $R\$" "$OPSX_FAKE_LOG"; assert_eq "$(count '^opsx answer')" 0
[ -n "$(memo_get _parked demo/p1)" ] || fail "memo 要記 parked：$(cat "$MEMO")"
grep '⏳' "$LOG" | grep -q p1 || fail "要記 ⏳"

# parked 之後 collect 真的會給的形狀：gate 還開著所以在「待處理」，stop 過所以 dispatch 是 null
P1='{"slug":"p1","section":"待處理","dispatch":null,"open_gates":[{"id":"g7","opened_at":null}],"waiting":{"type":"等待決定","gate_id":"g7","question":"等 a 合進 main 之後再做","recommended":null,"options":["等"]}}'
cp "$MEMO" "$FX/memo.parked"

# --- parked：沒有東西合就不重派、也不答 ---
printf '{"demo/p1":{"mode":"stopped","agent":"codex","pane":"w1:p3","drive_pid":null},"demo/g":{"mode":"stopped","agent":"claude","pane":"w1:p2","drive_pid":null,"branch":"feat/g/m"}}' > "$DISP"
cards "[$P1]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "沒東西合不重派 parked"; assert_eq "$(count '^opsx answer')" 0

# --- parked：有東西合了（被等的卡由它自己的 agent /archive，workplan 的 PR 變 merged），先答那個 gate 再重派，沿用原 agent ---
sed -i '' '/- name: g$/,/status:/s/status: pending/status: merged/' "$R/openspec/workplan.yaml"
cards "[$P1]"
round || fail "rc: $(cat "$FX/out")"
got="$(grep -E '^opsx (answer|dispatch) p1' "$OPSX_FAKE_LOG" | sed -E 's/ -- .*$//')"
assert_eq "$got" "opsx answer p1 --gate g7 --repo $R
opsx dispatch p1 --agent codex --mode autopilot --kind dev --repo $R" "先答 gate 再派：$(cat "$OPSX_FAKE_LOG")"
grep '^opsx answer p1 ' "$OPSX_FAKE_LOG" | grep -q '合進 main 的 PR：g。' || fail "答案要說停下之後合了哪幾個 PR：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(memo_get _parked demo/p1)" "" "重派後 memo 不再有 parked"

# --- parked：答了 gate 但派不出去，下一輪 gate 已不是 open，只重試 dispatch ---
cp "$FX/memo.parked" "$MEMO"
cards "[$P1]"
OPSX_TEST_FAIL_dispatch="dispatch: agent_pane_busy" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer p1')" 1 "第一輪答 gate"
[ -n "$(memo_get _parked demo/p1)" ] || fail "派不出去 parked 要留著：$(cat "$MEMO")"
cards '[{"slug":"p1","section":"待指派","dispatch":null}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer p1')" 0 "已答過不再答：$(cat "$OPSX_FAKE_LOG")"
assert_grep "^opsx dispatch p1 --agent codex " "$OPSX_FAKE_LOG"
assert_eq "$(memo_get _parked demo/p1)" "" "派出去後清 parked"

# --- parked：人在板上答掉 gate（不是 coordinator 答的），清 parked、不派 ---
cp "$FX/memo.parked" "$MEMO"
cards '[{"slug":"p1","section":"待指派","dispatch":null}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(memo_get _parked demo/p1)" "" "人答掉 gate 要清 parked"
assert_eq "$(count '^opsx (answer|dispatch) p1')" 0 "人停掉的卡不派：$(cat "$OPSX_FAKE_LOG")"

# --- parked：人手動重派過，清 parked，agent 不見了照常重派 ---
cp "$FX/memo.parked" "$MEMO"
cards '[{"slug":"p1","section":"進行中","dispatch":'"$D"',"agent_status":"unknown"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(memo_get _parked demo/p1)" "" "已派出要清 parked"
assert_grep "^opsx dispatch p1 --agent claude " "$OPSX_FAKE_LOG"
cp "$WP0" "$R/openspec/workplan.yaml"
rm -f "$MEMO" "$DISP"

# --- 不推節點：idle 的卡什麼都不送 ---
mkcard u
cards '[{"slug":"u","section":"進行中","dispatch":'"$D"',"agent_status":"idle"}]'
round || fail "rc: $(cat "$FX/out")"
assert_not_grep 'agent prompt' "$OPSX_FAKE_LOG"; assert_eq "$(count '^opsx ')" 1 "只有 collect：$(cat "$OPSX_FAKE_LOG")"

# --- agent 不見了就重派 ---
cards '[{"slug":"u","section":"進行中","dispatch":'"$D"',"agent_status":"unknown"}]'
round || fail "rc: $(cat "$FX/out")"
got="$(grep -E '^opsx (stop|dispatch)' "$OPSX_FAKE_LOG")"
assert_eq "$got" "opsx stop u --repo $R
opsx dispatch u --agent claude --mode autopilot --kind dev --repo $R" "重派順序"
grep '!!' "$LOG" | grep -q u || fail "重派要記 !!"

# --- 十分鐘內不重派兩次 ---
printf '{"_redispatched":{"demo/u":"%s"}}' "$(ago 5)" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "十分鐘內不重派"
printf '{"_redispatched":{"demo/u":"%s"}}' "$(ago 11)" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 1 "過了十分鐘可以重派"
rm -f "$MEMO"

# --- drive pid 死了就重派 ---
sleep 0 & dead=$!; wait "$dead"
cards '[{"slug":"u","section":"進行中","dispatch":{"mode":"autopilot","agent":"claude","pane":"w1:p1","drive_pid":'"$dead"'},"agent_status":"idle"}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx dispatch u --agent claude" "$OPSX_FAKE_LOG"
echo "coordinate: ok"
