#!/usr/bin/env bash
# opsx coordinate：中控跑一輪。opsx / git / openspec / gh / herdr 全是 fake，斷言它叫了哪些指令、寫了哪些 log。
# 驗收：specs/opsx-coordinate/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo demo)"          # 真 git 建好 fixture 之後才換成 fake git
mkdir -p "$R/openspec/changes"
use_fakes opsx git openspec gh herdr
export OPSX_FAKE_LOG="$FX/fake.log" OPSX_TEST_COLLECT_JSON="$FX/collect.json"
LOG="$OPSX_STATE_DIR/coordinator.log"; MEMO="$OPSX_STATE_DIR/coordinator-memo.json"; DISP="$OPSX_STATE_DIR/dispatch.json"
# symlink-safe-writes：沙盒內的人把固定檔名換成指向 VICTIM 的 symlink，沙盒外的 coordinate 不能寫到它
VICTIM="$FX/victim"; victim_reset() { printf 'keep me\n' > "$VICTIM"; }

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
  - name: demo-d
    prs:
      - name: d-pr                # PR 名跟 change 名不同：依賴要從 change 對到它的 PR
        branch: feat/d/m
        status: pending
        depends-on: [p]
        changes:
          - name: d
            status: pending
  - name: demo-g
    prs:
      - name: g
        branch: feat/g/m
        status: pending
        depends-on: []
        changes:
          - name: g
            status: pending
  - name: demo-core
    prs:
      - name: core              # 一個 PR 兩個 change：兩個都 done 才算 merged
        branch: feat/core/m
        status: in-progress
        depends-on: []
        changes:
          - name: ca
            status: pending
          - name: cb
            status: pending
  - name: demo-af
    prs:
      - name: af
        branch: feat/af/m
        status: pending
        depends-on: [core]
        changes:
          - name: af
            status: pending
  - name: demo-loose
    prs:
      - name: loose             # 不在 workplan 的 planned 卡是 P2 不自動派；派工案例的卡要在這裡（沒設 milestone，照 D8 是 P1）
        branch: feat/loose/m
        status: pending
        depends-on: []
        changes:
          - name: s1
            status: pending
          - name: s2
            status: pending
          - name: s3
            status: pending
          - name: s4
            status: pending
          - name: s5
            status: pending
          - name: s6
            status: pending
          - name: s7
            status: pending
          - name: s8
            status: pending
          - name: x
            status: pending
          - name: p1
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

# --- 合併永遠由人按：五條件全綠的卡，coordinator 也不呼叫 opsx merge、不直接合、memo 不記核准（D3） ---
mkcard m
cards '[{"slug":"m","section":"待處理","stage":"babysit","dispatch":'"$D"',"agent_status":"idle","mr":'"$READY"'},{"slug":"x"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx merge')" 0 "coordinator 從不呼叫 opsx merge：$(cat "$OPSX_FAKE_LOG")"
assert_not_grep 'pr merge' "$OPSX_FAKE_LOG"; assert_not_grep 'mr merge' "$OPSX_FAKE_LOG"
assert_not_grep '_approved' "$MEMO"
assert_grep '^opsx dispatch x ' "$OPSX_FAKE_LOG"
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
victim_reset; ln -s "$VICTIM" "$R/openspec/workplan.yaml.coordinate.tmp"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(cat "$VICTIM")" "keep me" "workplan 的舊暫存檔名上的 symlink 不能被寫"
rm -f "$R/openspec/workplan.yaml.coordinate.tmp"
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

# --- 收尾：合併後分支又多了 commit，不收尾、通知一次；gate 答過（acked）才收尾 ---
LATE='late 1 abc1234 feat/g/m
abc1234 fix: pushed after merge'
rm -f "$MEMO"
OPSX_TEST_LATE_RC=1 OPSX_TEST_LATE_OUT="$LATE" round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx late g --repo $R --open-gate\$" "$OPSX_FAKE_LOG"
assert_eq "$(grep -cE '^(opsx stop|openspec archive|git .*worktree remove|git .*branch -D)' "$OPSX_FAKE_LOG")" 0 "多出 commit 不收尾：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep g | grep -q '1 個 commit' || fail "要記 ?? 含 commit 數：$(cat "$LOG")"
assert_grep '^notification show \[demo/g\] 合併後分支又多了 1 個 commit ' "$OPSX_FAKE_LOG"
assert_eq "$(count '^notification show')" 1 "第一輪通知一次"
[ -n "$(memo_get _notified demo/g/late/abc1234)" ] || fail "_notified 要有 demo/g/late/abc1234：$(cat "$MEMO")"
OPSX_TEST_LATE_RC=1 OPSX_TEST_LATE_OUT="$LATE" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^notification show')" 0 "第二輪不重送"
assert_eq "$(grep -cE '^(opsx stop|openspec archive)' "$OPSX_FAKE_LOG")" 0
OPSX_TEST_LATE_OUT="acked abc1234" round || fail "rc: $(cat "$FX/out")"
assert_grep '^openspec archive g -y$' "$OPSX_FAKE_LOG"
assert_grep '^git .*branch -D feat/g/m$' "$OPSX_FAKE_LOG"
cp "$WP0" "$R/openspec/workplan.yaml"

# --- 收尾：opsx late 查不出來（退出 2），不收尾、不通知，log 帶 stderr ---
rm -f "$MEMO"
OPSX_TEST_LATE_RC=2 OPSX_TEST_LATE_OUT="" OPSX_TEST_LATE_ERR="opsx late: 查不出來：mr.url 的 host github.com 對到 0 個 remote" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(grep -cE '^(opsx stop|openspec archive|git .*worktree remove|git .*branch -D)' "$OPSX_FAKE_LOG")" 0 "查不出來不收尾：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^notification show')" 0 "查不出來不通知"
grep '??' "$LOG" | grep -q 'github.com 對到 0 個 remote' || fail "log 要帶 stderr：$(cat "$LOG")"

# --- 收尾：--dry 只印 DRY opsx late，不通知 ---
rm -f "$MEMO"
OPSX_TEST_LATE_RC=1 OPSX_TEST_LATE_OUT="$LATE" round --dry || fail "rc: $(cat "$FX/out")"
assert_grep 'DRY opsx late g' "$FX/out"
assert_eq "$(count '^notification show')" 0 "dry 不通知"
assert_no_file "$MEMO"

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
grep '??' "$LOG" | grep -q 'demo/g' || fail "要記 ??：$(cat "$LOG")"
assert_eq "$(wp_status g)" pending "沒派過不動 workplan"

# --- 收尾：沒派過的卡，log 帶上 depends-on 它、還沒合的 PR ---
cards "[$(merged p 2026-11-07T12:00:00Z null null)]"
round || fail "rc: $(cat "$FX/out")"
grep '??' "$LOG" | grep 'demo/p' | grep -q 'd-pr' || fail "要記 ?? 並帶上在等它的 d-pr：$(cat "$LOG")"
assert_eq "$(wp_status p)" pending "沒派過不動 workplan"

# --- 收尾：一個 PR 兩個 change，只收了一個，PR 不標 merged、依賴它的不派 ---
mkcard ca cb af
printf '{"demo/ca":{"mode":"stopped","agent":"claude","pane":"w1:p5","drive_pid":null,"branch":"feat/core/m"}}' > "$DISP"
cards "[$(merged ca 2026-11-07T12:00:00Z null null),{\"slug\":\"af\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(wp_change ca)" done "收尾的 change 標 done"
assert_eq "$(wp_status core)" in-progress "cb 還沒 done，PR 不標 merged"
assert_eq "$(count '^opsx dispatch af')" 0 "core 沒 merged，依賴它的不派：$(cat "$OPSX_FAKE_LOG")"
assert_grep '^openspec archive ca -y$' "$OPSX_FAKE_LOG"
cp "$WP0" "$R/openspec/workplan.yaml"; rm -f "$MEMO"

# --- 收尾：兄弟 change 還沒 propose（目錄不在、archive 也沒有），PR 不標 merged ---
rm -rf "$R/openspec/changes/cb"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(wp_change cb)" pending "沒 propose 的兄弟不算 done"
assert_eq "$(wp_status core)" in-progress "沒 propose 的兄弟還在，PR 不標 merged"
assert_eq "$(count '^opsx dispatch af')" 0 "core 沒 merged，依賴它的不派：$(cat "$OPSX_FAKE_LOG")"
cp "$WP0" "$R/openspec/workplan.yaml"; rm -f "$MEMO"

# --- 收尾：archive 裡只有名字以 -cb 結尾的別的 change，沒 propose 的 cb 不算已歸檔 ---
mkdir -p "$R/openspec/changes/archive/2026-11-07-ca-cb"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(wp_change cb)" pending "別的 change 的歸檔不算 cb 已歸檔"
assert_eq "$(wp_status core)" in-progress "別的 change 的歸檔不讓 PR 標 merged"
assert_eq "$(count '^opsx dispatch af')" 0 "core 沒 merged，依賴它的不派：$(cat "$OPSX_FAKE_LOG")"
rm -rf "$R/openspec/changes/archive/2026-11-07-ca-cb"
cp "$WP0" "$R/openspec/workplan.yaml"; rm -f "$MEMO"

# --- 收尾：兄弟 change 已歸檔（drop 或手動 archive）、workplan 沒更新，PR 照樣標 merged、依賴它的同輪派出 ---
mkdir -p "$R/openspec/changes/archive/2026-11-07-cb"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(wp_change ca)" done "收尾的 change 標 done"
assert_eq "$(wp_change cb)" done "已歸檔的兄弟一起標 done"
assert_eq "$(wp_status core)" merged "兄弟都 done，PR 標 merged"
assert_grep "^opsx dispatch af --agent claude --mode autopilot --kind dev --repo $R\$" "$OPSX_FAKE_LOG"
grep -q 'cb' "$LOG" || fail "log 要點名因已歸檔補標的 cb：$(cat "$LOG")"
rm -rf "$R/openspec/changes/archive/2026-11-07-cb"
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

# --- 答 gate：action 不是閘門會查的動作（沙盒 / dontAsk 擋下的授權題）→ 照樣回「允許」，但不帶 --grant（grant-action） ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待授權","gate_id":"g2","action":"run-tests","question":"要跑測試","recommended":null,"options":["拒絕"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx answer a1 --gate g2 --repo $R -- 允許\$" "$OPSX_FAKE_LOG"
assert_eq "$(count '^opsx answer .*--grant')" 0 "表外 action 不帶 --grant：$(cat "$OPSX_FAKE_LOG")"

# --- 答 gate：合併的授權題不代答（合併永遠由人按，D3） ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待授權","gate_id":"g8","action":"merge","question":"要合併","recommended":null,"options":["這次"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "合併的授權題不代答：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep a1 | grep -q g8 || fail "合併授權題要記 ??：$(cat "$LOG")"

# --- 答 gate：要人動手的不代答 ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","gate_id":"g5","question":"這段怎麼驗","recommended":"你在 sandbox 外跑","options":["你在 sandbox 外跑","略過"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "要人動手的不代答"
grep '??' "$LOG" | grep a1 | grep -q g5 || fail "要記 ?? 與 gate id：$(cat "$LOG")"

# --- 答 gate：授權題的 action 或題目跟合併有關就不代答（action 不一定剛好寫成 merge） ---
for a in 'mr-merge|forge 回 405，要授權重試嗎' 'external|用 GitLab API 合併 MR !7'; do
  cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待授權","gate_id":"gx","action":"'"${a%%|*}"'","question":"'"${a#*|}"'","recommended":null,"options":["這次"]}}]'
  round || fail "rc: $(cat "$FX/out")"
  assert_eq "$(count '^opsx answer')" 0 "跟合併有關的授權題不代答（${a}）：$(cat "$OPSX_FAKE_LOG")"
  grep '??' "$LOG" | grep a1 | grep -q gx || fail "要記 ?? 與 gate id（${a}）：$(cat "$LOG")"
done

# --- 答 gate：合併類決定題不代答（merge 永遠人：授權綁 sha，代答「重試合併」等於替人決定） ---
for q in '要不要合併這個 PR？|合併' 'forge 拒絕合併（pipeline 紅），要怎麼做？|重跑 pipeline 後重試合併' '要授權合併嗎？|允許' 'Ready to merge?|yes'; do
  cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","gate_id":"gm","question":"'"${q%%|*}"'","recommended":"'"${q#*|}"'","options":["'"${q#*|}"'","停"]}}]'
  round || fail "rc: $(cat "$FX/out")"
  assert_eq "$(count '^opsx answer')" 0 "合併類決定題不代答（${q%%|*}）：$(cat "$OPSX_FAKE_LOG")"
  grep '??' "$LOG" | grep a1 | grep -q gm || fail "合併類決定題要記 ?? 與 gate id（${q%%|*}）：$(cat "$LOG")"
done

# --- 答 gate：沒派出去的不答 ---
cards '[{"slug":"a1","section":"待處理","dispatch":null,"waiting":{"type":"等待授權","gate_id":"g1","action":"push","question":"要 push","recommended":null,"options":["這次"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "沒派出去的不答"

# --- 答 gate：真機題標等使用者驗 ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","gate_id":"g2","question":"這要真機跑一次嗎","recommended":"跑","options":["跑","不跑"]}}]'
round || fail "rc: $(cat "$FX/out")"
grep '^opsx answer a1 --gate g2 ' "$OPSX_FAKE_LOG" | grep '等使用者驗' | grep -q 'report.md' || fail "真機題的答案：$(cat "$OPSX_FAKE_LOG")"

# --- type 不明、needs: run 的 gate 不代答（gate-type-normalize）：答案會變成指令原文或寫進不明的 gate ---
: > "$OPSX_FAKE_LOG"; : > "$LOG"
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"type 不明","needs":null,"gate_id":"gu","question":"沒寫 type","recommended":"照做","options":[]}}]'
round || fail "type 不明 rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "type 不明不代答：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep -q 'gu' || fail "type 不明要記 ?? 給人看：$(cat "$LOG")"
assert_grep '^notification show \[demo/a1\] gate gu ' "$OPSX_FAKE_LOG"
assert_eq "$(count '^notification show')" 1 "type 不明的 gate 第一輪通知一次：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(memo_get _notified demo/a1/gate/gu)" ] || fail "_notified 要有 demo/a1/gate/gu：$(cat "$MEMO")"
round || fail "type 不明第二輪 rc: $(cat "$FX/out")"
assert_eq "$(count '^notification show')" 0 "type 不明的 gate 第二輪不重送：$(cat "$OPSX_FAKE_LOG")"
: > "$OPSX_FAKE_LOG"; : > "$LOG"
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","needs":"run","gate_id":"gr","question":"跑一下","recommended":"ls -la /tmp","options":[]}}]'
round || fail "needs run rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "needs: run 不代答：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep -q 'gr' || fail "needs: run 要記 ?? 給人看：$(cat "$LOG")"
assert_grep '^notification show \[demo/a1\] gate gr ' "$OPSX_FAKE_LOG"
assert_eq "$(count '^notification show')" 1 "needs: run 的 gate 第一輪通知一次：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(memo_get _notified demo/a1/gate/gr)" ] || fail "_notified 要有 demo/a1/gate/gr：$(cat "$MEMO")"
round || fail "needs run 第二輪 rc: $(cat "$FX/out")"
assert_eq "$(count '^notification show')" 0 "needs: run 的 gate 第二輪不重送：$(cat "$OPSX_FAKE_LOG")"
: > "$OPSX_FAKE_LOG"; : > "$LOG"
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待授權","needs":"run","action":"external","gate_id":"ga","question":"要跑 chmod","recommended":"sudo chmod 755 x","options":["這次"]}}]'
round || fail "approval + needs run rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "approval + needs: run 也不代答（指令沒人跑，不能回允許）：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep -q 'ga' || fail "approval + needs: run 要記 ?? 給人看：$(cat "$LOG")"

# --- 答 gate：drive 與 Stop hook 寫的卡住 gate 只通知，不把「建議」或選項送進 pane ---
for gid in "drive-review-1" "卡在接 /apply #1" "卡在接 /review"; do
  : > "$OPSX_FAKE_LOG"; : > "$LOG"
  cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","needs":null,"gate_id":"'"$gid"'","question":"卡住了","recommended":"先看 pane 再回","options":["重做一次 (Recommended)","停在這裡"]}}]'
  round || fail "${gid} rc: $(cat "$FX/out")"
  assert_eq "$(count '^opsx answer')" 0 "${gid} 不代答：$(cat "$OPSX_FAKE_LOG")"
  assert_eq "$(count '^agent prompt a1 ')" 0 "${gid} 沒有任何字送進 pane：$(cat "$OPSX_FAKE_LOG")"
  assert_eq "$(count '^notification show')" 1 "${gid} 通知一次：$(cat "$OPSX_FAKE_LOG")"
  round || fail "${gid} 第二輪 rc: $(cat "$FX/out")"
  assert_eq "$(count '^notification show')" 0 "${gid} 第二輪不重送：$(cat "$OPSX_FAKE_LOG")"
done
# 其他 decision gate 照原規則答（標題只是長得像也一樣）
for gid in "g-drive-review-1" "drive-review"; do
  : > "$OPSX_FAKE_LOG"; : > "$LOG"
  cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","needs":null,"gate_id":"'"$gid"'","question":"選哪個","recommended":"甲","options":["甲","乙"]}}]'
  round || fail "${gid} rc: $(cat "$FX/out")"
  assert_grep "^opsx answer a1 --gate ${gid} --repo $R -- 甲\$" "$OPSX_FAKE_LOG"
done

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

# --- 沒有 waits-on：建議寫了「合併後」也不當等別張卡，不停 pane、通知使用者（coordinate-split-park） ---
mkcard p1
: > "$OPSX_FAKE_LOG"; : > "$LOG"
cards '[{"slug":"p1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","needs":null,"waits_on":null,"gate_id":"split","question":"照這個拆法建殼、寫 workplan？","recommended":"照這個拆法，forge session 等 grant-gate-levels 合併後再開","options":["照這個拆法","不拆"]}}]'
round || fail "split rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx stop')" 0 "沒有 waits-on 不停 pane：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx answer')" 0 "split gate 不代答：$(cat "$OPSX_FAKE_LOG")"
assert_grep '^notification show \[demo/p1\] gate split ' "$OPSX_FAKE_LOG"
assert_eq "$(memo_get _parked demo/p1)" "" "split gate 不記 parked：$(cat "$MEMO")"
rm -f "$MEMO"; : > "$OPSX_FAKE_LOG"; : > "$LOG"

# --- split gate 一律要人答：建議不含合併 / merge 也不代答（要人答不能靠建議剛好有哪個字） ---
cards '[{"slug":"p1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","needs":null,"waits_on":null,"gate_id":"split","question":"照這個拆法建殼、寫 workplan？","recommended":"照這個拆法，forge session 等 grant-gate-levels 進 main 再開","options":["照這個拆法","不拆"]}}]'
round || fail "split 無合併字 rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "split gate 建議不含合併也不代答：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx stop')" 0 "split gate 不停 pane：$(cat "$OPSX_FAKE_LOG")"
assert_grep '^notification show \[demo/p1\] gate split ' "$OPSX_FAKE_LOG"
rm -f "$MEMO"; : > "$OPSX_FAKE_LOG"; : > "$LOG"

# --- waits-on 排在合併類規則之前：建議含「合併後」也照停 pane ---
cards '[{"slug":"p1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","needs":null,"waits_on":"a","gate_id":"g8","question":"等 a 做完","recommended":"a 合併後再開","options":["等"]}}]'
round || fail "waits-on 先於合併類 rc: $(cat "$FX/out")"
assert_grep "^opsx stop p1 --repo $R\$" "$OPSX_FAKE_LOG"
assert_eq "$(count '^notification show')" 0 "waits-on 的 gate 不通知：$(cat "$OPSX_FAKE_LOG")"
rm -f "$MEMO"; : > "$OPSX_FAKE_LOG"; : > "$LOG"

# --- 等別張卡：停下並記 parked ---
cards '[{"slug":"p1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","needs":null,"waits_on":"a","gate_id":"g7","question":"等 a 合進 main 之後再做","recommended":null,"options":["等"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx stop p1 --repo $R\$" "$OPSX_FAKE_LOG"; assert_eq "$(count '^opsx answer')" 0
[ -n "$(memo_get _parked demo/p1)" ] || fail "memo 要記 parked：$(cat "$MEMO")"
grep '⏳' "$LOG" | grep -q p1 || fail "要記 ⏳"

# parked 之後 collect 真的會給的形狀：gate 還開著所以在「待處理」，stop 過所以 dispatch 是 null
P1='{"slug":"p1","section":"待處理","dispatch":null,"open_gates":[{"id":"g7","opened_at":null}],"waiting":{"type":"等待決定","waits_on":"a","gate_id":"g7","question":"等 a 合進 main 之後再做","recommended":null,"options":["等"]}}'
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

# --- parked：人在板上答掉 gate（不是 coordinator 答的），不再答、照派卡規則重派，沿用原 agent ---
cp "$FX/memo.parked" "$MEMO"
cards '[{"slug":"p1","section":"待指派","dispatch":null}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer p1')" 0 "人答過的 gate 不再答：$(cat "$OPSX_FAKE_LOG")"
assert_grep "^opsx dispatch p1 --agent codex " "$OPSX_FAKE_LOG"
assert_eq "$(memo_get _parked demo/p1)" "" "重派後清 parked"

# --- parked：人答掉 gate 但卡的依賴還沒合，不派，parked 留著並記已答 ---
cp "$FX/memo.parked" "$MEMO"
cat >> "$R/openspec/workplan.yaml" <<'EOF'
  - name: demo-p1
    prs:
      - name: p1
        branch: feat/p1/m
        status: pending
        depends-on: [p]
        changes:
          - name: p1
            status: pending
EOF
cards '[{"slug":"p1","section":"待指派","dispatch":null}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx (answer|dispatch) p1')" 0 "依賴沒合不派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(memo_get _parked demo/p1 | grep -c "'answered': True")" 1 "parked 要留著並記已答：$(cat "$MEMO")"
cp "$WP0" "$R/openspec/workplan.yaml"
sed -i '' '/- name: g$/,/status:/s/status: pending/status: merged/' "$R/openspec/workplan.yaml"

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
assert_not_grep 'agent prompt' "$OPSX_FAKE_LOG"; assert_eq "$(grep -cEv '^(opsx (collect|reap)|agent read )' "$OPSX_FAKE_LOG" || true)" 0 "只有 collect、reap 與唯讀的 agent read：$(cat "$OPSX_FAKE_LOG")"

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
rm -f "$MEMO" "$DISP"

# --- 派工照等級（priority-dispatch）---
# incident <slug> <impact> <evidence>：收件卡的事實；evidence 給空字串就是沒證據
incident() { printf -- '---\nkind_of_work: incident\nimpact: %s\nevidence: %s\n---\n' "$2" "$3" > "$R/openspec/changes/$1/inbox.md"; }
dispatched() { grep '^opsx dispatch' "$OPSX_FAKE_LOG" | cut -d' ' -f3; }
cat > "$R/openspec/workplan.yaml" <<'EOF'
milestones:
  - name: "1.0"
    goal: 能開單
  - name: "1.1"
    goal: 能退貨
features:
  - name: later               # 1.1 的 feature 寫在前面：順序要照 milestones，不是照 workplan
    milestone: "1.1"
    prs:
      - name: card-b
        branch: feat/card-b/m
        status: pending
        depends-on: []
        changes:
          - name: card-b
            status: pending
  - name: first
    milestone: "1.0"
    prs:
      - name: card-a
        branch: feat/card-a/m
        status: pending
        depends-on: []
        changes:
          - name: card-a
            status: pending
  - name: first-p1
    milestone: "1.0"
    prs:
      - name: card-p1
        branch: feat/card-p1/m
        status: pending
        depends-on: []
        changes:
          - name: card-p1
            status: pending
EOF
WP1="$FX/workplan.milestones"; cp "$R/openspec/workplan.yaml" "$WP1"
mkcard card-p0 card-p1 card-p2 card-a card-b card-bad card-old card-zz q1 q2 q3 q4 q5 q6 q7 r1 r2 r3 r4 r5 r6
incident card-p0 security "tests/auth.test.sh 第 3 案：未登入可讀 /admin"
incident card-bad security ""
for s in q1 q2 q3 q4 q5 q6 q7 r1 r2 r3 r4 r5 r6; do incident "$s" workaround_exists "手動重跑可過"; done

# P0 先派：collect 的順序是 P1 在前
cards '[{"slug":"card-p1"},{"slug":"card-p0"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(dispatched)" "card-p0
card-p1" "P0 先派：$(cat "$OPSX_FAKE_LOG")"

# P2 不自動派（不在 workplan 的 planned 卡）
cards '[{"slug":"card-p2"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "P2 不自動派：$(cat "$OPSX_FAKE_LOG")"
grep -- 'card-p2' "$LOG" | grep -q 'P2' || fail "P2 要記一行含卡名與 P2：$(cat "$LOG")"

# P1 依 milestone 順序：card-b 在 1.1、card-a 在 1.0，沒設 current_milestone 兩張都是 P1
cards '[{"slug":"card-b"},{"slug":"card-a"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(dispatched)" "card-a
card-b" "P1 依 milestone 順序：$(cat "$OPSX_FAKE_LOG")"

# P0 不受每輪上限擋：七張 P1 加一張 P0，派 P0 與六張 P1，第七張記派滿
cards '[{"slug":"q1"},{"slug":"q2"},{"slug":"q3"},{"slug":"q4"},{"slug":"q5"},{"slug":"q6"},{"slug":"q7"},{"slug":"card-p0"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 7 "P0 加六張 P1：$(cat "$OPSX_FAKE_LOG")"
assert_grep '^opsx dispatch card-p0 ' "$OPSX_FAKE_LOG"
assert_eq "$(count '^opsx dispatch q7 ')" 0 "第七張 P1 不派"
grep '派滿' "$LOG" | grep -q q7 || fail "第七張 P1 要記派滿：$(cat "$LOG")"

# 在跑的卡一律不停：六張進行中（含兩張 P2）又來一張 P0，照派 P0、不 stop 任何卡
busy() { printf '{"slug":"%s","section":"進行中","dispatch":%s,"agent_status":"working"}' "$1" "$D"; }
cards "[$(busy r1),$(busy r2),$(busy r3),$(busy r4),$(busy card-zz),$(busy card-old),{\"slug\":\"card-p0\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx stop')" 0 "在跑的卡不停：$(cat "$OPSX_FAKE_LOG")"
assert_grep '^opsx dispatch card-p0 ' "$OPSX_FAKE_LOG"

# 等級算不出來不派：impact 沒有 evidence；同一輪別的卡照派
cards '[{"slug":"card-bad"},{"slug":"card-a"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(dispatched)" "card-a" "算不出來的不派、別張照派：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep 'demo/card-bad' | grep -q 'evidence' || fail "要記 ?? 含卡名與 evidence：$(cat "$LOG")"

# 整個 repo 的 milestone 欄位不合格：那個 repo 的卡都記 ??、不派
printf 'current_milestone: "9.9"\n' | cat - "$WP1" > "$R/openspec/workplan.yaml"
cards '[{"slug":"card-a"},{"slug":"card-p0"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "workplan 不合格整個 repo 不派：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep 'demo/card-a' | grep -q 'current_milestone' || fail "要記 ?? 含卡名與欄位：$(cat "$LOG")"

# parked 的 P2 卡照樣重派：人派出去、coordinate 自己停下等別張合併的，不是新派工
cat "$WP1" > "$R/openspec/workplan.yaml"
printf '  - name: other\n    prs:\n      - name: done-pr\n        branch: feat/done-pr/m\n        status: merged\n        depends-on: []\n        changes:\n          - name: done-pr\n            status: done\n' >> "$R/openspec/workplan.yaml"
printf '{"_parked":{"demo/card-p2":{"at":"2026-11-10T10:00:00+08:00","gate":"g9","merged":[]}},"_redispatched":{}}' > "$MEMO"
printf '{"demo/card-p2":{"mode":"stopped","agent":"claude","pane":"w1:p9","drive_pid":null}}' > "$DISP"
cards '[{"slug":"card-p2","section":"待處理","open_gates":[{"id":"g9","opened_at":null}],"waiting":{"type":"等待決定","waits_on":"done-pr","gate_id":"g9","question":"等 done-pr 合進 main 之後再做","recommended":null,"options":["等"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep '^opsx answer card-p2 --gate g9 ' "$OPSX_FAKE_LOG"
assert_grep '^opsx dispatch card-p2 ' "$OPSX_FAKE_LOG"
cp "$WP0" "$R/openspec/workplan.yaml"
rm -f "$MEMO"; printf '{}' > "$DISP"

# --- 自動開 session：有 depends-on 的 feature g 等 m1；根 feature r 沒有 depends-on ---
auto_wp() { # <m1 的 status>
  cat > "$R/openspec/workplan.yaml" <<EOF
features:
  - name: f
    depends-on: []
    prs:
      - name: m1
        branch: feat/m1/u
        status: $1
        depends-on: []
        changes:
          - name: s1
            status: done
  - name: g
    depends-on: [m1]
    prs:
      - name: m3
        branch: feat/m3/u
        status: pending
        depends-on: []
        changes:
          - name: t3
            status: pending
EOF
}
mkcard m3

# 依賴沒合：m3 不單卡派、g 不開 session，log 記 feature g 等 m1
auto_wp pending
cards '[{"slug":"m3"}]'
round || fail "rc: $(cat "$FX/out")"
assert_not_grep "^opsx dispatch m3" "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch --feature g" "$OPSX_FAKE_LOG"
grep '⏳' "$LOG" | grep 'feature g' | grep -q 'm1' || fail "feature g 要記等 m1：$(cat "$LOG")"

# m1 合了、沒有 demo/@g：恰好開一次 session，m3 不單卡派
auto_wp merged
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch --feature g ')" 1 "依賴合了開一次 session：$(cat "$OPSX_FAKE_LOG")"
assert_grep "^opsx dispatch --feature g --only m3 --agent claude --mode autopilot --repo $R\$" "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch m3" "$OPSX_FAKE_LOG"
grep -- '--' "$LOG" | grep 'demo/m3' | grep -q 'feature g' || fail "m3 要記由 feature g 的 session 做：$(cat "$LOG")"
rm -f "$MEMO"

# 開不了 session：記 ?? 含 feature 名
OPSX_TEST_FAIL_dispatch="dispatch: boom" round || fail "rc: $(cat "$FX/out")"
grep '??' "$LOG" | grep 'feature g' | grep -q boom || fail "開不了 session 要記 ??：$(cat "$LOG")"
rm -f "$MEMO"

# --dry：不開 session
round --dry || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "--dry 不派：$(cat "$OPSX_FAKE_LOG")"
rm -f "$MEMO"

# demo/@g 活著：不再開
AUTO_G='"workspace":"demo","workspace_id":"w1","tab":"w1:t9","pane":"w1:p9","agent":"claude","model":"claude-opus-5-5","worktree":"'"$R"'/.claude/worktrees/g","started_at":"2026-11-07T10:00:00+08:00","drive_pid":null'
printf '{"demo/@g":{%s,"mode":"autopilot"}}' "$AUTO_G" > "$DISP"
round || fail "rc: $(cat "$FX/out")"
assert_not_grep "^opsx dispatch --feature g" "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch m3" "$OPSX_FAKE_LOG"
rm -f "$MEMO"

# demo/@g 是人停的：不重開，m3 也不單卡派
printf '{"demo/@g":{%s,"mode":"stopped","stopped_at":"2026-11-07T11:00:00+08:00"}}' "$AUTO_G" > "$DISP"
round || fail "rc: $(cat "$FX/out")"
assert_not_grep "^opsx dispatch --feature g" "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch m3" "$OPSX_FAKE_LOG"
rm -f "$MEMO"

# demo/@g 被 reap 收掉（不活、不是 stopped）：重開一次
printf '{"demo/@g":{%s,"mode":"autopilot","reaped_at":"2026-11-07T11:00:00+08:00"}}' "$AUTO_G" > "$DISP"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch --feature g ')" 1 "不活的 session 要重開：$(cat "$OPSX_FAKE_LOG")"
rm -f "$MEMO"; printf '{}' > "$DISP"

# m3 已經單卡派著（條目活著、沒有 via @g）、沒有 demo/@g：不開 session，log 記原因
printf '{"demo/m3":{"mode":"autopilot","agent":"claude","pane":"w1:p3","drive_pid":null,"branch":"feat/m3/u"}}' > "$DISP"
round || fail "rc: $(cat "$FX/out")"
assert_not_grep "^opsx dispatch --feature g" "$OPSX_FAKE_LOG"
grep '已經單卡派' "$LOG" | grep 'feature g' | grep -q 'm3' || fail "要記 m3 已經單卡派：$(cat "$LOG")"
rm -f "$MEMO"; printf '{}' > "$DISP"

# m3 單卡派過又停了，worktree 還在（分支還被它 checkout）：照樣不開 session
mkdir -p "$R/.claude/worktrees/m3"
printf '{"demo/m3":{"mode":"stopped","agent":"claude","pane":"w1:p3","drive_pid":null,"branch":"feat/m3/u","worktree":"%s"}}' "$R/.claude/worktrees/m3" > "$DISP"
round || fail "rc: $(cat "$FX/out")"
assert_not_grep "^opsx dispatch --feature g" "$OPSX_FAKE_LOG"
grep '已經單卡派' "$LOG" | grep 'feature g' | grep -q 'm3' || fail "停了但 worktree 還在也要記：$(cat "$LOG")"
# worktree 收掉了：不再佔分支，照開
rmdir "$R/.claude/worktrees/m3"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch --feature g ')" 1 "worktree 不在的停掉單卡不擋：$(cat "$OPSX_FAKE_LOG")"
rm -f "$MEMO"; printf '{}' > "$DISP"

# feature g 能開工的有兩張：只交出能自動派的卡，P0 排第一，人停的成員不算
cat >> "$R/openspec/workplan.yaml" <<'EOF'
      - name: m4
        branch: feat/m4/u
        status: pending
        depends-on: []
        changes:
          - name: t4
            status: pending
EOF
mkcard m4
printf -- '---\npriority: P2\npriority_reason: 先不做\n---\n' > "$R/openspec/changes/m4/inbox.md"
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx dispatch --feature g --only m3 " "$OPSX_FAKE_LOG"
rm -f "$MEMO"
incident m4 security "tests/auth.test.sh 第 3 案：未登入可讀 /admin"
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx dispatch --feature g --only m4,m3 " "$OPSX_FAKE_LOG"
rm -f "$MEMO"
printf -- '---\npriority: P2\npriority_reason: 先不做\n---\n' > "$R/openspec/changes/m4/inbox.md"
printf '{"demo/m3":{"mode":"stopped","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m3/u"}}' > "$DISP"
round || fail "rc: $(cat "$FX/out")"
assert_not_grep "^opsx dispatch --feature g" "$OPSX_FAKE_LOG"
grep 'feature g' "$LOG" | grep -q 'P2' || fail "人停的成員去掉後只剩 P2，要記 P2：$(cat "$LOG")"
auto_wp merged
rm -rf "$R/openspec/changes/m4"; rm -f "$MEMO"; printf '{}' > "$DISP"

# feature g 能開工的卡全是 P2：不開 session，log 記 P2
printf -- '---\npriority: P2\npriority_reason: 先不做\n---\n' > "$R/openspec/changes/m3/inbox.md"
round || fail "rc: $(cat "$FX/out")"
assert_not_grep "^opsx dispatch --feature g" "$OPSX_FAKE_LOG"
grep 'feature g' "$LOG" | grep -q 'P2' || fail "要記 feature g 的卡是 P2：$(cat "$LOG")"
rm -f "$MEMO"

# 開 session 佔每輪額度、排在單卡派之後：六張單卡派滿，feature g（P1）下輪
mkcard n1 n2 n3 n4 n5 n6 m6
for s in n1 n2 n3 n4 n5 n6; do incident "$s" workaround_exists "手動重跑可過"; done
SIX='{"slug":"n1"},{"slug":"n2"},{"slug":"n3"},{"slug":"n4"},{"slug":"n5"},{"slug":"n6"}'
rm -f "$R/openspec/changes/m3/inbox.md"
cards "[$SIX,{\"slug\":\"m3\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch n')" 6 "六張單卡先派：$(cat "$OPSX_FAKE_LOG")"
assert_not_grep "^opsx dispatch --feature g" "$OPSX_FAKE_LOG"
grep '派滿' "$LOG" | grep -q 'feature g' || fail "feature g 要記派滿：$(cat "$LOG")"
rm -f "$MEMO"

# feature g 的卡是 P0：單卡派滿也照開 session
incident m3 security "tests/auth.test.sh 第 3 案：未登入可讀 /admin"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch --feature g ')" 1 "P0 不佔每輪上限：$(cat "$OPSX_FAKE_LOG")"
rm -f "$MEMO" "$R/openspec/changes/m3/inbox.md"

# 開失敗不佔額度：五張單卡、兩個 feature 都 ready、每個派工都失敗，第二個 feature 照樣去開
auto_wp merged
cat >> "$R/openspec/workplan.yaml" <<'EOF'
  - name: g2
    depends-on: [m1]
    prs:
      - name: m6
        branch: feat/m6/u
        status: pending
        depends-on: []
        changes:
          - name: t6
            status: pending
EOF
cards '[{"slug":"n1"},{"slug":"n2"},{"slug":"n3"},{"slug":"n4"},{"slug":"n5"},{"slug":"m3"},{"slug":"m6"}]'
OPSX_TEST_FAIL_dispatch="dispatch: boom" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch --feature')" 2 "第一個 session 開失敗不佔額度：$(cat "$OPSX_FAKE_LOG")"
auto_wp merged
rm -rf "$R/openspec/changes/n1" "$R/openspec/changes/n2" "$R/openspec/changes/n3" "$R/openspec/changes/n4" "$R/openspec/changes/n5" "$R/openspec/changes/n6" "$R/openspec/changes/m6"
rm -f "$MEMO"; printf '{}' > "$DISP"

# 根 feature r（沒有 depends-on 欄位）有兩個 PR：由 session 代管，r1、r2 不單卡派
root_wp() { # <r1 的 status>
  cat > "$R/openspec/workplan.yaml" <<EOF
features:
  - name: r
    prs:
      - name: r1
        branch: feat/r1/u
        status: $1
        depends-on: []
        changes:
          - name: r1
            status: pending
      - name: r2
        branch: feat/r2/u
        status: pending
        depends-on: []
        changes:
          - name: r2
            status: pending
  - name: s
    depends-on: []
    prs:
      - name: s1
        branch: feat/s1/u
        status: pending
        depends-on: []
        changes:
          - name: s1
            status: pending
EOF
}
root_wp pending
mkcard r1 r2 s1
cards '[{"slug":"r1"},{"slug":"r2"},{"slug":"s1"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch --feature r ')" 1 "多 PR 根 feature 開一次 session：$(cat "$OPSX_FAKE_LOG")"
assert_grep "^opsx dispatch --feature r --only r1,r2 --agent claude --mode autopilot --repo $R\$" "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch r1 " "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch r2 " "$OPSX_FAKE_LOG"
assert_not_grep "KeyError" "$LOG"
# 只有一個 PR 的根 feature s（depends-on: []）：照單卡派，不開 session
assert_grep "^opsx dispatch s1 --agent claude" "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch --feature s " "$OPSX_FAKE_LOG"
rm -f "$MEMO"

# 已合的 r1 也算進 PR 數：r 照樣由 session 代管，只交出 r2
root_wp merged
cards '[{"slug":"r2"}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx dispatch --feature r --only r2 " "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch r2 " "$OPSX_FAKE_LOG"
rm -rf "$R/openspec/changes/r1" "$R/openspec/changes/r2" "$R/openspec/changes/s1"; rm -f "$MEMO"

cp "$WP0" "$R/openspec/workplan.yaml"
rm -rf "$R/openspec/changes/m3"; rm -f "$MEMO"; printf '{}' > "$DISP"

# --- 用量上限暫停（usage-limit-pause）---
AR="$FX/agent-read.txt"; export OPSX_TEST_AGENT_READ="$AR"
ahead() { python3 -I -c 'import datetime,sys; print((datetime.datetime.now().astimezone()+datetime.timedelta(minutes=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
LIMIT_MSG='Usage limit reached · continuing automatically at 7pm · esc to cancel'
idle() { printf '{"slug":"%s","section":"進行中","dispatch":%s,"agent_status":"idle"}' "$1" "$D"; }
rm -f "$MEMO"; printf '{}' > "$DISP"

# 到上限：不派、不答、不重派，通知一次，第二輪不再通知
printf '%s\n' "$LIMIT_MSG" > "$AR"
GATE='{"type":"等待授權","gate_id":"g1","action":"push","question":"要 push","recommended":null,"options":["這次"]}'
LC="[$(idle r1),{\"slug\":\"r2\",\"section\":\"待處理\",\"dispatch\":$D,\"agent_status\":\"idle\",\"waiting\":$GATE},{\"slug\":\"r3\",\"section\":\"進行中\",\"dispatch\":$D,\"agent_status\":\"unknown\"},{\"slug\":\"q1\"}]"
cards "$LC"
round || fail "rc: $(cat "$FX/out")"
for w in '^opsx dispatch' '^opsx answer' '^opsx stop'; do assert_eq "$(count "$w")" 0 "暫停不動 ${w}：$(cat "$OPSX_FAKE_LOG")"; done
assert_eq "$(count '^notification show')" 1 "進入暫停通知一次：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(memo_get _usage_limit resets_at)" ] || fail "memo 要記 resets_at：$(cat "$MEMO")"
assert_grep "預計 $(memo_get _usage_limit resets_at | cut -c6-10) 19:00 恢復" "$OPSX_FAKE_LOG"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "第二輪仍暫停"
assert_eq "$(count '^notification show')" 0 "第二輪不再通知：$(cat "$OPSX_FAKE_LOG")"

# 重置時刻已過、畫面乾淨：恢復派卡、通知一次、不代送繼續
printf 'ok\n' > "$AR"
printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"}}' "$(ago 70)" "$(ago 10)" > "$MEMO"
cards "[$(idle r1),{\"slug\":\"q1\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch q1 ')" 1 "恢復後派卡：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^notification show')" 1 "恢復通知一次"
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG" | grep -vc '^agent prompt opsx-coordinator ' || true)" 0 "不代送繼續（送協調者 session 的通知不算）"
assert_eq "$(memo_get _usage_limit resets_at)" "" "恢復後清掉 _usage_limit"

# 時刻沒到，畫面乾淨也不派
printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"}}' "$(ago 10)" "$(ahead 60)" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "重置時刻沒到不派"

# 警告（grace allowance）不算暫停
rm -f "$MEMO"
printf 'Usage limit reached; a short grace allowance remains, then this turn is cut off without warning.\n' > "$AR"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch q1 ')" 1 "警告照派"
assert_eq "$(memo_get _usage_limit seen_at)" "" "警告不記暫停"

# 讀不出時刻：不猜，記 ??、通知一次、不派；訊息不見了才恢復
rm -f "$MEMO"
printf 'Usage limit reached · something new\n' > "$AR"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "讀不出時刻不派"
grep '??' "$LOG" | grep -q '用量' || fail "要記 ?? 含用量：$(cat "$LOG")"
assert_eq "$(count '^notification show')" 1 "讀不出時刻通知一次"
printf 'ok\n' > "$AR"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch q1 ')" 1 "訊息不見了就恢復"

# working 的 agent 不讀畫面
rm -f "$MEMO"
printf '%s\n' "$LIMIT_MSG" > "$AR"
cards '[{"slug":"r1","section":"進行中","dispatch":'"$D"',"agent_status":"working"},{"slug":"q1"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^agent read')" 0 "working 不讀"
assert_eq "$(count '^opsx dispatch q1 ')" 1 "只有 working 的 agent：不暫停"
printf 'ok\n' > "$AR"

# parse_usage_limit：固定 now 下直接比對輸出（時刻照時鐘算、外來文字不算、分鐘不合法不當掉）
python3 -I - "$OPSX_ROOT/bin/lib" <<'PY' || fail "parse_usage_limit 的案例有錯"
import datetime, sys
sys.path.insert(0, sys.argv[1])
import coordinate
tz = datetime.timezone(datetime.timedelta(hours=8))
def at(day, h, m=0):
    return datetime.datetime(2026, 11, day, h, m, tzinfo=tz)
CONT = "Usage limit reached · continuing automatically at %s · esc to cancel"
cases = [
    (CONT % "7pm", at(10, 20), (True, at(11, 19))),
    (CONT % "7pm", at(10, 18), (True, at(10, 19))),
    (CONT % "12am", at(10, 20), (True, at(11, 0))),
    (CONT % "12pm", at(10, 8), (True, at(10, 12))),
    ("Usage limit reached · limit resets 7:30pm", at(10, 18), (True, at(10, 19, 30))),
    ("  ⎿  Usage limit reached · limit resets 7pm", at(10, 18), (True, at(10, 19))),
    (CONT % "7:99pm", at(10, 18), (True, None)),
    ("Usage limit reached · something new", at(10, 18), (True, None)),
    ("LIMIT_MSG='Usage limit reached · continuing automatically at 7pm'", at(10, 18), (False, None)),
    ("+USAGE_LIMIT = \"Usage limit reached\"", at(10, 18), (False, None)),
    ("Usage limit reached; a short grace allowance remains, then this turn is cut off", at(10, 18), (False, None)),
    ("Usage limit reached again · continuing automatically at 7pm · esc to cancel", at(10, 18), (True, at(10, 19))),
    ("- Usage limit reached · limit resets 7pm", at(10, 18), (False, None)),
    ("> Usage limit reached · limit resets 7pm", at(10, 18), (False, None)),
    ("+Usage limit reached · limit resets 7pm", at(10, 18), (False, None)),
    ("`Usage limit reached · limit resets 7pm`", at(10, 18), (False, None)),
    ("⏺ Usage limit reached 的偵測", at(10, 18), (False, None)),
    ("Usage limit reached 的偵測", at(10, 18), (False, None)),
]
for text, now, want in cases:
    got = coordinate.parse_usage_limit(text, now)
    assert got == want, "%r at %s: want %s got %s" % (text, now, want, got)
PY

# 暫停過了重置時刻 30 分鐘、pane 還顯示訊息：通知一次，不派
rm -f "$MEMO"
printf '%s\n' "$LIMIT_MSG" > "$AR"
printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"}}' "$(ago 100)" "$(ago 40)" > "$MEMO"
cards "[$(idle r1),{\"slug\":\"q1\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "過了重置時刻仍顯示訊息：照暫停"
assert_grep '^notification show \[usage-limit\] 重置時刻過了' "$OPSX_FAKE_LOG"
assert_grep 'w1:p1' "$OPSX_FAKE_LOG"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^notification show')" 0 "仍暫停的通知只送一次"
# 過期那輪的 log 要有 ??
printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"}}' "$(ago 100)" "$(ago 40)" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
grep '??' "$LOG" | grep -q '重置時刻已過' || fail "過期要記 ??：$(cat "$LOG")"
# 還沒過 30 分鐘（10 分鐘前重置）pane 還顯示：不通知
printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"}}' "$(ago 70)" "$(ago 10)" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^notification show')" 0 "未過 30 分鐘不通知：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx dispatch')" 0 "未過 30 分鐘仍暫停"
# 重置時刻讀不出（null）：從進入暫停起算，40 分鐘仍顯示就通知一次，之後不再通知
printf 'Usage limit reached · something new\n' > "$AR"
printf '{"_usage_limit":{"seen_at":"%s","resets_at":null}}' "$(ago 40)" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "null 時刻仍暫停"
assert_grep '^notification show \[usage-limit\] 重置時刻過了' "$OPSX_FAKE_LOG"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^notification show')" 0 "null 的過期通知只送一次"
printf '{"_usage_limit":{"seen_at":"%s","resets_at":null}}' "$(ago 10)" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^notification show')" 0 "null 且未滿 30 分鐘不通知"
rm -f "$MEMO"; printf 'ok\n' > "$AR"

# --- 同時在跑上限（<state>/max-working，沒有這個檔是 6）---
MW="$OPSX_STATE_DIR/max-working"; rm -f "$MW"
cards "[$(busy r1),$(busy r2),$(busy r3),$(busy r4),$(busy r5),$(busy r6),{\"slug\":\"q1\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "六張在跑，不派非 P0：$(cat "$OPSX_FAKE_LOG")"
grep '同時' "$LOG" | grep -q 6 || fail "要記 -- 含上限 6：$(cat "$LOG")"
cards "[$(busy r1),$(busy r2),{\"slug\":\"q1\"}]"
printf '2\n' > "$MW"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "上限 2、兩張在跑不派"
printf '3\n' > "$MW"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch q1 ')" 1 "上限 3 派"
cards "[$(busy r1),$(busy r2),{\"slug\":\"q1\"},{\"slug\":\"q2\"},{\"slug\":\"q3\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 1 "本輪已派的也算進同時數：$(cat "$OPSX_FAKE_LOG")"
# 本輪代答喚醒的卡也算：四張 working，兩張 idle 等可代答的 gate，上限 6
printf '6\n' > "$MW"
cards "[$(busy r1),$(busy r2),$(busy r3),$(busy r4),{\"slug\":\"r5\",\"section\":\"待處理\",\"dispatch\":$D,\"agent_status\":\"idle\",\"waiting\":$GATE},{\"slug\":\"r6\",\"section\":\"待處理\",\"dispatch\":$D,\"agent_status\":\"idle\",\"waiting\":$GATE},{\"slug\":\"q1\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 2 "兩個 gate 都代答：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx dispatch')" 0 "代答喚醒的兩張算進同時數，q1 不派：$(cat "$OPSX_FAKE_LOG")"
# 開 session 也照同時上限：上限 2、兩張在跑，feature g 排第一的是 P1 就下輪；是 P0 照開
auto_wp merged; mkcard m3; rm -f "$MEMO"; printf '{}' > "$DISP"
printf '2\n' > "$MW"
cards "[$(busy r1),$(busy r2),{\"slug\":\"m3\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_not_grep "^opsx dispatch --feature g" "$OPSX_FAKE_LOG"
grep '同時' "$LOG" | grep -q 'feature g' || fail "feature g 要記達同時上限：$(cat "$LOG")"
incident m3 security "tests/auth.test.sh 第 3 案：未登入可讀 /admin"
rm -f "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch --feature g ')" 1 "P0 不受同時上限擋：$(cat "$OPSX_FAKE_LOG")"
rm -rf "$R/openspec/changes/m3"; cp "$WP0" "$R/openspec/workplan.yaml"; rm -f "$MEMO"; printf '{}' > "$DISP"
printf 'abc\n' > "$MW"
round && fail "上限設錯要拒跑"
grep 'max-working' "$LOG" | grep -q abc || fail "log 要含檔名 max-working 與 abc：$(cat "$LOG")"
assert_eq "$(count '^opsx dispatch')" 0 "設錯不動任何卡"
printf '0\n' > "$MW"
round && fail "上限 0 要拒跑"
grep 'max-working' "$LOG" | grep -q "'0'" || fail "log 要含檔名 max-working 與 0：$(cat "$LOG")"
assert_eq "$(count '^opsx dispatch')" 0 "上限 0 不動任何卡"
rm -f "$MW"
unset OPSX_TEST_AGENT_READ

LOCK="$OPSX_STATE_DIR/coordinator.lock"; RERUN="$OPSX_STATE_DIR/coordinator.rerun"
# wait_for <說明> <shell 條件>：最多等 10 秒（背景那輪、lock 放掉）
wait_for() { local i=0; until eval "$2"; do i=$((i+1)); [ $i -lt 100 ] || fail "等不到$1：$(cat "$LOG")"; sleep 0.1; done; }
starts() { grep -c '== coordinator 開始' "$LOG" || true; }
ends() { grep -c '== 結束' "$LOG" || true; }
# lock_free：沒有人拿著 coordinator.lock 的 flock
lock_free() { python3 -I -c 'import fcntl,sys; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)' "$LOCK" 2>/dev/null; }
# hold_lock：背景 process 拿住 flock 直到被 kill，pid 寫在 HOLDER
hold_lock() {
  rm -f "$FX/held"
  python3 -I -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(60)' "$LOCK" "$FX/held" &
  HOLDER=$!
  wait_for " lock 被拿住" '[ -f "$FX/held" ]'
}

# --- 同時只跑一輪：另一輪在跑就不動 ---
mkcard a1
A1_GRANT='[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待授權","gate_id":"g1","action":"push","question":"要 push","recommended":null,"options":["這次"]}},{"slug":"x"}]'
cards "$A1_GRANT"
hold_lock
round; rc=$?
assert_eq "$rc" 0 "lock 被拿著要以 0 結束：$(cat "$FX/out")"
assert_eq "$(grep -cE '^opsx (collect|answer|dispatch|stop)' "$OPSX_FAKE_LOG")" 0 "lock 被拿著不讀狀態、不動手：$(cat "$OPSX_FAKE_LOG")"
assert_file "$RERUN"
grep -q -- '--' "$LOG" || fail "要記一行 --：$(cat "$LOG")"
rm -f "$RERUN"
round --dry
assert_no_file "$RERUN"
# rerun 標記是 symlink：拒絕、非 0、目標不變
victim_reset; ln -s "$VICTIM" "$RERUN"
round; rc=$?
[ $rc -ne 0 ] || fail "rerun 是 symlink 要非 0：$(cat "$FX/out")"
assert_grep coordinator.rerun "$FX/out"
assert_eq "$(cat "$VICTIM")" "keep me" "rerun 不能截斷 symlink 的目標"
rm -f "$RERUN"
kill "$HOLDER"; wait "$HOLDER" 2>/dev/null
rm -f "$RERUN" "$MEMO"

# --- 死掉的 lock 不擋：持有者被 kill -9，lock 檔留著 ---
hold_lock
kill -9 "$HOLDER"; wait "$HOLDER" 2>/dev/null
assert_file "$LOCK"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(ends)" 1 "持有者死掉的 lock 要接手跑完：$(cat "$LOG")"
assert_grep "^opsx answer a1 --gate g1 --grant this --repo $R -- 允許\$" "$OPSX_FAKE_LOG"
lock_free || fail "跑完要放掉 lock"
rm -f "$MEMO"

# --- 結束前看到記號就再跑一輪：一輪讀 collect 時，另一個 opsx coordinate 撞到 lock 留下記號 ---
: > "$FX/once"
printf '[ -f "%s" ] || exit 0\nrm -f "%s"\nbash "%s/bin/opsx" coordinate > "%s" 2>&1\n' "$FX/once" "$FX/once" "$OPSX_ROOT" "$FX/nested.out" > "$FX/on_collect.sh"
OPSX_TEST_ON_COLLECT="$FX/on_collect.sh" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(starts)" 2 "要補跑一輪：$(cat "$LOG") 中途那次：$(cat "$FX/nested.out")"
assert_eq "$(ends)" 2 "要補跑一輪：$(cat "$LOG")"
assert_eq "$(count '^opsx collect')" 2 "補跑那輪重讀 collect：$(cat "$OPSX_FAKE_LOG")"
assert_no_file "$RERUN"; lock_free || fail "跑完要放掉 lock"
rm -f "$MEMO"

# --- kick 立刻回傳：背景那輪讀 collect 要睡 3 秒 ---
printf 'sleep 3\n' > "$FX/slow.sh"
: > "$OPSX_FAKE_LOG"; : > "$LOG"
t0="$(python3 -I -c 'import time; print(time.time())')"
OPSX_TEST_ON_COLLECT="$FX/slow.sh" bash "$OPSX_ROOT/bin/opsx" coordinate --kick > "$FX/out" 2>&1; rc=$?
t1="$(python3 -I -c 'import time; print(time.time())')"
assert_eq "$rc" 0 "kick 要以 0 結束：$(cat "$FX/out")"
python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[2]) - float(sys.argv[1]) < 1 else 1)' "$t0" "$t1" || fail "kick 要在 1 秒內回傳：$t0 → $t1"
wait_for " kick 那輪結束" '[ "$(ends)" = 1 ]'
wait_for " lock 放掉" 'lock_free'
grep -E '== (coordinator 開始|結束)' "$LOG" | sed -E 's/^.*== (coordinator 開始|結束).*$/\1/' > "$FX/order"
assert_eq "$(tr '\n' '|' < "$FX/order")" "coordinator 開始|結束|" "log 依序有開始與結束：$(cat "$LOG")"

# --- kick 那輪照規則答 gate ---
rm -f "$MEMO"; : > "$OPSX_FAKE_LOG"; : > "$LOG"
bash "$OPSX_ROOT/bin/opsx" coordinate --kick > "$FX/out" 2>&1 || fail "kick rc: $(cat "$FX/out")"
wait_for " kick 那輪結束" '[ "$(ends)" = 1 ]'
wait_for " lock 放掉" 'lock_free'
assert_grep "^opsx answer a1 --gate g1 --grant this --repo $R -- 允許\$" "$OPSX_FAKE_LOG"

# --- kick 起不來：記一行原因，仍以 0 結束 ---
: > "$LOG"; rm -f "$OPSX_STATE_DIR/coordinate.out"; mkdir "$OPSX_STATE_DIR/coordinate.out"
bash "$OPSX_ROOT/bin/opsx" coordinate --kick > "$FX/out" 2>&1; rc=$?
assert_eq "$rc" 0 "kick 起不來也要以 0 結束：$(cat "$FX/out")"
grep -q 'kick' "$LOG" || fail "kick 起不來要在 coordinator.log 記原因：$(cat "$LOG")"
rmdir "$OPSX_STATE_DIR/coordinate.out"; rm -f "$MEMO"

# --- coordinate.out 是 symlink：不起背景那輪、記一行原因、以 0 結束、目標不變 ---
: > "$LOG"; victim_reset; ln -s "$VICTIM" "$OPSX_STATE_DIR/coordinate.out"
bash "$OPSX_ROOT/bin/opsx" coordinate --kick > "$FX/out" 2>&1; rc=$?
assert_eq "$rc" 0 "coordinate.out 是 symlink 也要以 0 結束：$(cat "$FX/out")"
grep -q 'coordinate.out' "$LOG" || fail "要在 coordinator.log 記原因並含路徑：$(cat "$LOG")"
sleep 2
assert_eq "$(cat "$VICTIM")" "keep me" "coordinate.out 不能附加到 symlink 的目標"
rm -f "$OPSX_STATE_DIR/coordinate.out" "$MEMO"

notes() { count '^notification show'; }

# --- 要人的 gate 通知一次 ---
HUMAN='[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","gate_id":"g1","question":"這段怎麼驗\n第二行","recommended":"你在 sandbox 外跑","options":["你在 sandbox 外跑","略過"]}}]'
cards "$HUMAN"
round || fail "rc: $(cat "$FX/out")"
n1="$(notes)"; grep '^notification show' "$OPSX_FAKE_LOG" > "$FX/note1"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$((n1 + $(notes)))" 1 "兩輪只通知一次：$(cat "$FX/note1")"
assert_grep '^notification show \[demo/a1\] ' "$FX/note1"
assert_grep ' --body 看板.*這段怎麼驗 --sound request$' "$FX/note1"
assert_not_grep '第二行' "$FX/note1"
[ -n "$(memo_get _notified demo/a1/gate/g1)" ] || fail "_notified 要有 demo/a1/gate/g1：$(cat "$MEMO")"
assert_eq "$(count '^opsx answer')" 0 "要人的 gate 不代答"

# --- memo 的舊暫存檔名被 symlink 占住：不寫到目標，memo 照常更新 ---
rm -f "$MEMO"; victim_reset; ln -s "$VICTIM" "$MEMO.tmp"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(cat "$VICTIM")" "keep me" "memo 的舊暫存檔名上的 symlink 不能被寫"
[ -n "$(memo_get _notified demo/a1/gate/g1)" ] || fail "memo 要照常更新：$(cat "$MEMO")"
rm -f "$MEMO.tmp"

# --- coordinator.log 是 symlink：拒絕、非 0、目標不變 ---
rm -f "$LOG"; victim_reset; ln -s "$VICTIM" "$LOG"
bash "$OPSX_ROOT/bin/opsx" coordinate > "$FX/out" 2>&1; rc=$?
[ $rc -ne 0 ] || fail "log 是 symlink 要非 0：$(cat "$FX/out")"
assert_grep coordinator.log "$FX/out"
assert_eq "$(cat "$VICTIM")" "keep me" "log 不能附加到 symlink 的目標"
rm -f "$LOG" "$MEMO"

# --- --dry 只印，不送不記 ---
rm -f "$MEMO"
round --dry || fail "dry rc: $(cat "$FX/out")"
assert_grep 'DRY herdr agent prompt opsx-coordinator \[demo/a1\]' "$FX/out"
assert_eq "$(notes)" 0 "dry 不送"; assert_no_file "$MEMO"

# --- 代答的 gate 不通知 ---
cards "$A1_GRANT"
round || fail "rc: $(cat "$FX/out")"
assert_grep '^opsx answer a1 --gate g1 --grant this ' "$OPSX_FAKE_LOG"
assert_eq "$(notes)" 0 "代答的不通知：$(cat "$OPSX_FAKE_LOG")"
rm -f "$MEMO"

# --- 通知失敗下一輪再試 ---
printf 'boom\nok\n' > "$FX/nerr"
cards "$HUMAN"
OPSX_TEST_NOTIFY_ERR="$FX/nerr" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 1
grep '??' "$LOG" | grep 'demo/a1/gate/g1' | grep -q boom || fail "失敗要記 ?? 含去重鍵與 herdr 的錯：$(cat "$LOG")"
assert_eq "$(memo_get _notified demo/a1/gate/g1)" "" "失敗不記進 _notified"
OPSX_TEST_NOTIFY_ERR="$FX/nerr" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 1 "下一輪再送一次"
[ -n "$(memo_get _notified demo/a1/gate/g1)" ] || fail "成功後要記：$(cat "$MEMO")"
rm -f "$MEMO"

# --- 協調者在：事件走 agent prompt，不發桌面通知 ---
cards "$HUMAN"
OPSX_TEST_COORDINATOR_UP=1 round || fail "rc: $(cat "$FX/out")"
c1="$(count '^agent prompt opsx-coordinator \[demo/a1\] gate g1 ')"; assert_eq "$(notes)" 0 "協調者在不發桌面通知"
OPSX_TEST_COORDINATOR_UP=1 round || fail "rc: $(cat "$FX/out")"
assert_eq "$((c1 + $(count '^agent prompt opsx-coordinator ')))" 1 "協調者在：兩輪只送一次：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(notes)" 0 "協調者在第二輪也不發桌面通知"
[ -n "$(memo_get _notified demo/a1/gate/g1)" ] || fail "協調者收到要記 _notified：$(cat "$MEMO")"
rm -f "$MEMO"

# --- 協調者 pane 卡住（agent_blocked）：退回桌面通知，人才收得到 ---
printf 'agent_blocked\n' > "$FX/berr"
cards "$HUMAN"
OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_ERR="$FX/berr" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 1 "協調者卡住要退回桌面通知：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(memo_get _notified demo/a1/gate/g1)" ] || fail "退回通知成功要記 _notified：$(cat "$MEMO")"
rm -f "$MEMO"

# --- 協調者那邊出別的錯：不退回桌面通知、不記，下一輪補送 ---
printf 'boom\nok\n' > "$FX/cerr"
cards "$HUMAN"
OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_ERR="$FX/cerr" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 0 "別的錯不退回桌面通知"
grep '??' "$LOG" | grep 'demo/a1/gate/g1' | grep -q boom || fail "失敗要記 ?? 含去重鍵與 herdr 的錯：$(cat "$LOG")"
assert_eq "$(memo_get _notified demo/a1/gate/g1)" "" "失敗不記進 _notified"
OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_ERR="$FX/cerr" round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^agent prompt opsx-coordinator ')" 1 "下一輪補送"
[ -n "$(memo_get _notified demo/a1/gate/g1)" ] || fail "成功後要記：$(cat "$MEMO")"
rm -f "$MEMO"

# --- 終端機等待輸入：綁 pane 通知一次，內文指到 pane ---
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"blocked","waiting":{"type":"終端機等待輸入","gate_id":null,"question":"agent 在終端機等輸入","recommended":"開啟 pane","options":["開啟 pane"]}}]'
round || fail "rc: $(cat "$FX/out")"
grep '^notification show \[demo/a1\]' "$OPSX_FAKE_LOG" | grep -q 'pane w1:p1' || fail "內文要指到 pane：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(memo_get _notified demo/a1/blocked/w1:p1)" ] || fail "_notified 要有 blocked 鍵：$(cat "$MEMO")"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 0 "同一個 pane 不再通知"
# 人處理完、卡不再等人，之後同一個 pane 又卡住要再通知
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"working"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(memo_get _notified demo/a1/blocked/w1:p1)" "" "不等人了要清掉 blocked 鍵：$(cat "$MEMO")"
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"blocked","waiting":{"type":"終端機等待輸入","gate_id":null,"question":"agent 在終端機等輸入","recommended":"開啟 pane","options":["開啟 pane"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 1 "同一個 pane 再卡住要再通知一次"
rm -f "$MEMO"

# --- 可以合併照 head sha 通知 ---
cards '[{"slug":"m","section":"待處理","stage":"babysit","dispatch":'"$D"',"agent_status":"idle","mr":'"$READY"',"waiting":{"type":"可以合併","gate_id":null,"question":"可以合併","recommended":null,"options":[]}}]'
round || fail "rc: $(cat "$FX/out")"; n1="$(notes)"; grep 'merge' "$OPSX_FAKE_LOG" > "$FX/merges"
grep '^notification show \[demo/m\]' "$OPSX_FAKE_LOG" | grep -q '看板' || fail "可以合併要指到看板：$(cat "$OPSX_FAKE_LOG")"
round || fail "rc: $(cat "$FX/out")"; n2="$(notes)"; grep 'merge' "$OPSX_FAKE_LOG" >> "$FX/merges"
cards '[{"slug":"m","section":"待處理","stage":"babysit","dispatch":'"$D"',"agent_status":"idle","mr":'"${READY/abc/s2}"'}]'
round || fail "rc: $(cat "$FX/out")"; n3="$(notes)"; grep 'merge' "$OPSX_FAKE_LOG" >> "$FX/merges"
assert_eq "$((n1 + n2 + n3))" 2 "同一個 sha 一次、新 sha 再一次"
assert_eq "$(cat "$FX/merges")" "" "沒有任何 merge 指令"
[ -n "$(memo_get _notified demo/m/ready/abc)" ] && [ -n "$(memo_get _notified demo/m/ready/s2)" ] || fail "_notified 要綁 head sha：$(cat "$MEMO")"
rm -f "$MEMO"

# --- 十分鐘內第二次掛掉才通知 ---
cards '[{"slug":"u","section":"進行中","dispatch":'"$D"',"agent_status":"unknown"}]'
printf '{"_redispatched":{"demo/u":"%s"}}' "$(ago 5)" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "十分鐘內不重派"
assert_eq "$(notes)" 1 "十分鐘內第二次掛掉要通知：$(cat "$OPSX_FAKE_LOG")"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 0 "同一次重派只通知一次"

# --- 重派成功不通知 ---
rm -f "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx stop u --repo $R\$" "$OPSX_FAKE_LOG"; assert_grep '^opsx dispatch u ' "$OPSX_FAKE_LOG"
assert_eq "$(notes)" 0 "重派成功不通知"
rm -f "$MEMO"

# --- 單卡同一輪重派兩次：gate 答不出去（agent_not_found）又 agent_status unknown，只派一次、不通知 ---
cards '[{"slug":"u","section":"進行中","dispatch":'"$D"',"agent_status":"unknown","waiting":{"type":"等待授權","gate_id":"g1","action":"x","question":"允許嗎","recommended":null,"options":[]}}]'
OPSX_TEST_FAIL_answer=agent_not_found round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 1 "同一輪只重派一次：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(notes)" 0 "同一輪第二次要求重派不通知：$(cat "$OPSX_FAKE_LOG")"
assert_grep '這輪不再派' "$LOG"
# 對照：下一輪、十分鐘內又掛，照樣通知一次
cards '[{"slug":"u","section":"進行中","dispatch":'"$D"',"agent_status":"unknown"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "下一輪十分鐘內不重派"
assert_eq "$(notes)" 1 "下一輪十分鐘內又掛要通知：$(cat "$OPSX_FAKE_LOG")"
rm -f "$MEMO"

# --- 每輪最後回收孤兒 pane：呼叫 opsx reap；dry 只記 DRY；reap 失敗不影響這一輪的結束 ---
cards '[]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx reap$')" 1 "每輪呼叫一次 opsx reap：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(tail -n 1 "$OPSX_FAKE_LOG")" "opsx reap" "reap 是這一輪最後一個動作"
round --dry || fail "dry rc: $(cat "$FX/out")"
assert_grep "DRY opsx reap" "$LOG"
assert_eq "$(count '^opsx reap')" 0 "dry 不呼叫 opsx reap"
export OPSX_TEST_FAIL_reap="herdr 讀不到"
round || fail "reap 失敗不該讓這一輪失敗：$(cat "$FX/out")"
unset OPSX_TEST_FAIL_reap
assert_grep "rc1 .*opsx reap" "$LOG"
assert_grep "== 結束" "$LOG"

# --- 主 change（卡名 = PR 名，changes[] 是子 change）與 feature session ---
sess_wp() { # <m1 的 status>
  cat > "$R/openspec/workplan.yaml" <<EOF
features:
  - name: f
    depends-on: []
    prs:
      - name: m1
        branch: feat/m1/u
        status: $1
        depends-on: []
        changes:
          - name: s1
            status: done
  - name: f2
    prs:
      - name: m2
        branch: feat/m2/u
        status: pending
        depends-on: [m1]
        changes:
          - name: t1
            status: pending
  - name: g
    depends-on: [m1]
    prs:
      - name: m3
        branch: feat/m3/u
        status: pending
        depends-on: []
        changes:
          - name: t3
            status: pending
EOF
}
mkcard m2 m3; printf '{}' > "$DISP"; rm -f "$MEMO"

# 主 change m2 的依賴 m1 沒合：不派；m3 屬於有依賴的 feature g，由 session 派、不單獨派；g 的依賴沒合也不開
sess_wp pending
cards '[{"slug":"m2"},{"slug":"m3"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "依賴沒合：主 change 不派、feature 不開：$(cat "$OPSX_FAKE_LOG")"
grep '⏳' "$LOG" | grep 'm2' | grep -q 'm1' || fail "主 change m2 要記等 m1：$(cat "$LOG")"
grep '⏳' "$LOG" | grep 'feature g' | grep -q 'm1' || fail "feature g 要記等 m1：$(cat "$LOG")"

# m1 合了：m2 照舊單獨派（f2 沒有依賴、只有一個 PR，不是 session feature），g 開一個 session，m3 不單獨派
sess_wp merged
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx dispatch m2 --agent claude" "$OPSX_FAKE_LOG"
assert_eq "$(count '^opsx dispatch --feature g ')" 1 "g 開一次 session：$(cat "$OPSX_FAKE_LOG")"
assert_grep "^opsx dispatch --feature g --only m3 --agent claude --mode autopilot --repo $R" "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch m3" "$OPSX_FAKE_LOG"
rm -f "$MEMO"

# 主 change 合併、agent 不在：PR 標 merged，還沒 done 的子 change 一起標 done
sess_wp merged
printf '{"demo/m2":{"mode":"stopped","agent":"claude","pane":"w1:p3","drive_pid":null,"branch":"feat/m2/u"}}' > "$DISP"
cards "[$(merged m2 2026-11-07T12:00:00Z null null)]"
round || fail "rc: $(cat "$FX/out")"
assert_grep '^openspec archive m2 -y$' "$OPSX_FAKE_LOG"
assert_eq "$(wp_status m2)" merged "主 change 的 PR 要標 merged"
assert_eq "$(wp_change t1)" done "主 change 底下的子 change 要標 done"

# session 還在做別的主 change（m4）：收尾已合併的 m3 不 stop、不移除共用的 worktree，歸檔照做
mkdir -p "$R/.claude/worktrees/g"; rm -f "$MEMO"; mkcard m4
G_SESS='"mode":"autopilot","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"g","feature":"g","drive_pid":null'
printf '{"demo/m3":{%s,"branch":"feat/m3/u","worktree":"%s"},"demo/m4":{%s,"branch":"feat/m4/u","worktree":"%s"}}' "$G_SESS" "$R/.claude/worktrees/g" "$G_SESS" "$R/.claude/worktrees/g" > "$DISP"
cards "[$(merged m3 2026-11-07T12:00:00Z '{"mode":"autopilot","agent":"claude","pane":"w1:p9","feature":"g","drive_pid":null}' '"unknown"')]"
round || fail "rc: $(cat "$FX/out")"
assert_grep '^openspec archive m3 -y$' "$OPSX_FAKE_LOG"
assert_not_grep '^opsx stop m3' "$OPSX_FAKE_LOG"
assert_not_grep 'worktree remove' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."demo/m3".mode' "$DISP")" stopped "歸檔的 m3 條目標 stopped（不送 stop 給 pane）"
assert_eq "$(jq -r '."demo/m4".mode' "$DISP")" autopilot "還在做的 m4 不動"
# 接著 m4 也合併：已歸檔的 m3（資料夾搬走了）不算還活著的兄弟，m4 要 stop、移除 worktree
mv "$R/openspec/changes/m3" "$FX/m3-archived"
cards "[$(merged m4 2026-11-07T12:30:00Z '{"mode":"autopilot","agent":"claude","pane":"w1:p9","feature":"g","drive_pid":null}' '"unknown"')]"
round || fail "rc: $(cat "$FX/out")"
assert_grep '^opsx stop m4' "$OPSX_FAKE_LOG"
assert_grep "worktree remove $R/.claude/worktrees/g" "$OPSX_FAKE_LOG"
mv "$FX/m3-archived" "$R/openspec/changes/m3"

# --- session 條目就位後的收尾（session-archive-wake）：叫醒同 feature 的下一個主 change、最後一個收完關 session ---
wake_wp() { # <m3 的 status>
  cat > "$R/openspec/workplan.yaml" <<EOF
features:
  - name: g
    depends-on: []
    prs:
      - name: m3
        branch: feat/m3/u
        status: $1
        depends-on: []
        changes:
          - name: t3
            status: pending
      - name: m4
        branch: feat/m4/u
        status: pending
        depends-on: [m3]
        changes:
          - name: t4
            status: pending
  - name: h
    depends-on: []
    prs:
      - name: x9
        branch: feat/x9/u
        status: pending
        depends-on: [m3]
        changes:
          - name: t9
            status: pending
EOF
}
# wake_disp <@g 的 mode>：session 條目、m3 是成員；m4 還沒有條目
wake_disp() {
  printf '{"demo/@g":{"workspace":"demo","workspace_id":"w1","tab":"w1:t9","pane":"w1:p9","agent":"claude","model":"claude-opus-5-5","mode":"%s","worktree":"%s","started_at":"2026-11-07T10:00:00+08:00","drive_pid":null},"demo/m3":{"mode":"autopilot","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m3/u","worktree":"%s"}}' "$1" "$R/.claude/worktrees/g" "$R/.claude/worktrees/g" > "$DISP"
}
GM='{"mode":"autopilot","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null}'
mkcard m3 m4 x9; mkdir -p "$R/.claude/worktrees/g"; rm -f "$MEMO"

# 收尾後叫醒同 feature 的下一個主 change：直接送 herdr、不寫佇列；別的 feature 不叫醒；同一輪不再單卡派 m4
wake_wp pending; wake_disp autopilot
cards "[$(merged m3 2026-11-07T12:00:00Z "$GM" '"idle"'),{\"slug\":\"m4\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_grep '^openspec archive m3 -y$' "$OPSX_FAKE_LOG"
assert_grep '^agent prompt g \[m4\] /opsx-workflow:apply m4$' "$OPSX_FAKE_LOG"
assert_not_grep 'x9' "$OPSX_FAKE_LOG"
assert_not_grep '^opsx stop' "$OPSX_FAKE_LOG"
assert_not_grep '^opsx dispatch m4' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."demo/m4" | [.via, .feature, .herdr_name, .branch] | join(" ")' "$DISP")" "@g g g feat/m4/u" "m4 的成員條目"
assert_eq "$(jq -r '."demo/m4".pane' "$DISP")" "$(jq -r '."demo/@g".pane' "$DISP")" "m4 的 pane 取自 session 條目"
assert_eq "$(jq -r '."demo/x9"' "$DISP")" null "別的 feature 不寫條目"
assert_eq "$(jq -r '."demo/m3".mode' "$DISP")" stopped "歸檔的 m3 條目標 stopped"
assert_eq "$(jq -r '."demo/@g".mode' "$DISP")" autopilot "還有 m4，session 不關"
assert_no_file "$OPSX_STATE_DIR/herdr-queue/demo-m4.tsv"

# --dry：不寫 dispatch.json、不送 herdr
wake_wp pending; wake_disp autopilot; cp "$DISP" "$FX/disp-before.json"
round --dry || fail "rc: $(cat "$FX/out")"
assert_eq "$(cat "$DISP")" "$(cat "$FX/disp-before.json")" "--dry 不改 dispatch.json"
assert_not_grep '^agent prompt' "$OPSX_FAKE_LOG"

# session 不活時不叫醒
wake_wp pending; wake_disp stopped
cards "[$(merged m3 2026-11-07T12:00:00Z "$GM" '"idle"')]"
round || fail "rc: $(cat "$FX/out")"
assert_grep '^openspec archive m3 -y$' "$OPSX_FAKE_LOG"
assert_not_grep '^agent prompt g' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."demo/m4"' "$DISP")" null "session 停了不寫 m4 的條目"
assert_eq "$(jq -r '."demo/@g".mode' "$DISP")" stopped "人停的 session 條目留著"

# 最後一個成員收完關 session：m3 早就歸檔（條目 stopped），m4 是唯一的成員
close_disp() {
  printf '{"demo/@g":{"workspace":"demo","workspace_id":"w1","tab":"w1:t9","pane":"w1:p9","agent":"claude","model":"claude-opus-5-5","mode":"autopilot","worktree":"%s","started_at":"2026-11-07T10:00:00+08:00","drive_pid":null},"demo/m3":{"mode":"stopped","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m3/u"},"demo/m4":{"mode":"autopilot","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m4/u"}}' "$R/.claude/worktrees/g" > "$DISP"
}
wake_wp merged; close_disp; mv "$R/openspec/changes/m3" "$FX/m3-archived"
cards "[$(merged m4 2026-11-07T12:30:00Z "$GM" '"idle"')]"
round || fail "rc: $(cat "$FX/out")"
got="$(grep -E '^(openspec archive|opsx stop|git -C [^ ]+ (worktree remove|branch -D))' "$OPSX_FAKE_LOG")"
assert_eq "$got" "openspec archive m4 -y
opsx stop @g --repo $R
git -C $R worktree remove $R/.claude/worktrees/g
git -C $R branch -D feat/m3/u
git -C $R branch -D feat/m4/u" "關 session 的順序：stop、不 --force 移 worktree、刪已合併成員的分支"
assert_eq "$(jq -r '."demo/@g"' "$DISP")" null "session 條目拿掉"
# 之後同名 session 開得起來：真的 opsx dispatch --feature g 不因 session 條目或 agent 名被擋
cat > "$R/openspec/workplan.yaml" <<'EOF'
features:
  - name: g
    depends-on: []
    prs:
      - name: m5
        branch: feat/m5/u
        status: pending
        depends-on: []
        changes:
          - name: t5
            status: pending
EOF
mkcard m5
bash "$OPSX_ROOT/bin/opsx" dispatch --feature g --agent claude --mode autopilot --repo "$R" > "$FX/dispatch-out" 2>&1
assert_not_grep '已經派出去' "$FX/dispatch-out"
assert_not_grep 'agent_name_taken' "$FX/dispatch-out"
assert_grep '^agent start g ' "$OPSX_FAKE_LOG"

# 同名 feature 第二次關 session：上一輪的成員 m3 條目還在、分支已刪（假 git 對 refs/heads/feat/m3/u 回錯），不對它 branch -D，照樣關完
cat > "$R/openspec/workplan.yaml" <<'EOF'
features:
  - name: g
    depends-on: []
    prs:
      - name: m3
        branch: feat/m3/u
        status: merged
        depends-on: []
        changes:
          - name: t3
            status: done
      - name: m5
        branch: feat/m5/u
        status: pending
        depends-on: [m3]
        changes:
          - name: t5
            status: pending
EOF
printf '{"demo/@g":{"workspace":"demo","workspace_id":"w1","tab":"w1:t9","pane":"w1:p9","agent":"claude","model":"claude-opus-5-5","mode":"autopilot","worktree":"%s","started_at":"2026-11-08T10:00:00+08:00","drive_pid":null},"demo/m3":{"mode":"stopped","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m3/u"},"demo/m5":{"mode":"autopilot","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m5/u"}}' "$R/.claude/worktrees/g" > "$DISP"
mkdir -p "$R/.claude/worktrees/g"
cards "[$(merged m5 2026-11-08T12:30:00Z "$GM" '"idle"')]"
OPSX_TEST_GIT_FAIL=refs/heads/feat/m3/u round || fail "rc: $(cat "$FX/out")"
assert_not_grep 'branch -D feat/m3/u' "$OPSX_FAKE_LOG"
assert_grep "^git -C $R branch -D feat/m5/u\$" "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."demo/@g"' "$DISP")" null "第二次關 session 也拿掉條目：$(cat "$LOG")"
# rev-parse 不是「分支不在」而是 git 自己出錯（退出 128）：不刪分支、session 條目留著、記 ??
printf '{"demo/@g":{"workspace":"demo","workspace_id":"w1","tab":"w1:t9","pane":"w1:p9","agent":"claude","model":"claude-opus-5-5","mode":"autopilot","worktree":"%s","started_at":"2026-11-08T10:00:00+08:00","drive_pid":null},"demo/m3":{"mode":"stopped","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m3/u"},"demo/m5":{"mode":"autopilot","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m5/u"}}' "$R/.claude/worktrees/g" > "$DISP"
OPSX_TEST_GIT_FAIL=refs/heads/feat/m3/u OPSX_TEST_GIT_FAIL_RC=128 round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count 'branch -D')" 0 "git 出錯不刪分支：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(jq -r '."demo/@g" | type' "$DISP")" object "git 出錯 session 條目留著"
grep '??' "$LOG" | grep -q 'feat/m3/u' || fail "要記 ?? 含分支名：$(cat "$LOG")"
cards "[$(merged m4 2026-11-07T12:30:00Z "$GM" '"idle"')]"

# worktree 移不掉時留給人
wake_wp merged; close_disp
OPSX_TEST_GIT_FAIL=remove round || fail "rc: $(cat "$FX/out")"
assert_grep "worktree remove $R/.claude/worktrees/g" "$OPSX_FAKE_LOG"
assert_eq "$(count 'branch -D')" 0 "worktree 刪不掉不刪分支"
assert_eq "$(jq -r '."demo/@g".mode' "$DISP")" autopilot "worktree 刪不掉 session 條目留著"
grep '??' "$LOG" | grep -q '刪不掉' || fail "要記 worktree 刪不掉：$(cat "$LOG")"
mv "$FX/m3-archived" "$R/openspec/changes/m3"; rm -rf "$R/openspec/changes/m5" "$R/openspec/changes/x9"

# session 的 pane 不在了：只停 session 條目一次，整個 feature 重派一次，不逐卡 stop、不逐卡派，成員條目不動
sess_wp merged; rm -f "$MEMO"
G_ENTRY='"mode":"autopilot","agent":"claude","pane":"w1:p9","drive_pid":null'
printf '{"demo/@g":{%s},"demo/m3":{%s,"branch":"feat/m3/u"},"demo/m4":{%s,"branch":"feat/m4/u"}}' "$G_ENTRY" "$G_SESS" "$G_SESS" > "$DISP"
cp "$DISP" "$FX/disp-before.json"
GD='{"mode":"autopilot","agent":"claude","pane":"w1:p9","feature":"g","drive_pid":null}'
cards '[{"slug":"m3","section":"進行中","dispatch":'"$GD"',"agent_status":"unknown"},{"slug":"m4","section":"進行中","dispatch":'"$GD"',"agent_status":"unknown"}]'
round || fail "rc: $(cat "$FX/out")"
got="$(grep -E '^opsx (stop|dispatch)' "$OPSX_FAKE_LOG")"
assert_eq "$got" "opsx stop @g --repo $R
opsx dispatch --feature g --agent claude --mode autopilot --repo $R" "session 死掉：停 session 條目、feature 重派一次"
assert_eq "$(jq -S '{m3: ."demo/m3", m4: ."demo/m4"}' "$DISP")" "$(jq -S '{m3: ."demo/m3", m4: ."demo/m4"}' "$FX/disp-before.json")" "成員條目不動"
assert_eq "$(notes)" 0 "session 重派成功（含同一輪第二張卡）不通知：$(cat "$OPSX_FAKE_LOG")"
# 十分鐘內第二次掛掉：新 memo、5 分鐘前重派過；兩張卡一件事，通知一次，鍵綁 feature 與那個時間
rm -f "$MEMO"
seeded="$(ago 5)"
printf '{"_redispatched":{"demo/@g":"%s"}}' "$seeded" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "十分鐘內不再重派這個 feature"
assert_eq "$(notes)" 1 "feature session 十分鐘內第二次掛掉要通知一次：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(memo_get _notified "demo/@g/dead/$seeded")" ] || fail "_notified 要有 demo/@g/dead/${seeded}：$(cat "$MEMO")"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 0 "同一次重派只通知一次"
# session 共用 pane 卡在終端機：兩張卡一件事一則，兩張都不等了才清鍵
rm -f "$MEMO"
BW='"waiting":{"type":"終端機等待輸入","gate_id":null,"question":"agent 在終端機等輸入","recommended":"開啟 pane","options":["開啟 pane"]}'
cards '[{"slug":"m3","section":"待處理","dispatch":'"$GD"',"agent_status":"blocked",'"$BW"'},{"slug":"m4","section":"待處理","dispatch":'"$GD"',"agent_status":"blocked",'"$BW"'}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 1 "共用 pane 卡住兩張卡只通知一次：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(memo_get _notified demo/@g/blocked/w1:p9)" ] || fail "_notified 要有 demo/@g/blocked/w1:p9：$(cat "$MEMO")"
cards '[{"slug":"m3","section":"進行中","dispatch":'"$GD"',"agent_status":"working"},{"slug":"m4","section":"待處理","dispatch":'"$GD"',"agent_status":"blocked",'"$BW"'}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(notes)" 0 "m4 還卡著：m3 不等了不能讓鍵被清而重送：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(memo_get _notified demo/@g/blocked/w1:p9)" ] || fail "m4 還卡著，鍵要留著：$(cat "$MEMO")"
cards '[{"slug":"m3","section":"進行中","dispatch":'"$GD"',"agent_status":"working"},{"slug":"m4","section":"進行中","dispatch":'"$GD"',"agent_status":"working"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(memo_get _notified demo/@g/blocked/w1:p9)" "" "兩張都不等了要清鍵：$(cat "$MEMO")"
rm -f "$MEMO"

# 人停的成員卡不被撿回（C-human-stop）：人先停 m4，之後 session 的 pane 不在了
GS='{"mode":"stopped","agent":"claude","pane":"w1:p9","feature":"g","drive_pid":null}'
printf '{"demo/@g":{%s},"demo/m3":{%s,"branch":"feat/m3/u"},"demo/m4":{"mode":"stopped","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m4/u"}}' "$G_ENTRY" "$G_SESS" > "$DISP"
cards '[{"slug":"m3","section":"進行中","dispatch":'"$GD"',"agent_status":"unknown"},{"slug":"m4","section":"進行中","dispatch":'"$GS"',"agent_status":"unknown"}]'
round || fail "rc: $(cat "$FX/out")"
got="$(grep -E '^opsx (stop|dispatch)' "$OPSX_FAKE_LOG")"
assert_eq "$got" "opsx stop @g --repo $R
opsx dispatch --feature g --agent claude --mode autopilot --repo $R" "人停 m4 後 session 死掉：只停 session 條目、feature 重派一次"
assert_eq "$(jq -r '."demo/m4".mode' "$DISP")" stopped "人停的 m4 仍是 stopped"
rm -f "$MEMO"
cp "$WP0" "$R/openspec/workplan.yaml"; printf '{}' > "$DISP"
echo "coordinate: ok"
