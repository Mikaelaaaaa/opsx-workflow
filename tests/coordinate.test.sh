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
: > "$OPSX_FAKE_LOG"; : > "$LOG"
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","needs":"run","gate_id":"gr","question":"跑一下","recommended":"ls -la /tmp","options":[]}}]'
round || fail "needs run rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "needs: run 不代答：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep -q 'gr' || fail "needs: run 要記 ?? 給人看：$(cat "$LOG")"
: > "$OPSX_FAKE_LOG"; : > "$LOG"
cards '[{"slug":"a1","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待授權","needs":"run","action":"external","gate_id":"ga","question":"要跑 chmod","recommended":"sudo chmod 755 x","options":["這次"]}}]'
round || fail "approval + needs run rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "approval + needs: run 也不代答（指令沒人跑，不能回允許）：$(cat "$OPSX_FAKE_LOG")"
grep '??' "$LOG" | grep -q 'ga' || fail "approval + needs: run 要記 ?? 給人看：$(cat "$LOG")"

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
assert_not_grep 'agent prompt' "$OPSX_FAKE_LOG"; assert_eq "$(grep -cEv '^opsx (collect|reap)' "$OPSX_FAKE_LOG" || true)" 0 "只有 collect 與 reap：$(cat "$OPSX_FAKE_LOG")"

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
cards '[{"slug":"card-p2","section":"待處理","open_gates":[{"id":"g9","opened_at":null}],"waiting":{"type":"等待決定","gate_id":"g9","question":"等 done-pr 合進 main 之後再做","recommended":null,"options":["等"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_grep '^opsx answer card-p2 --gate g9 ' "$OPSX_FAKE_LOG"
assert_grep '^opsx dispatch card-p2 ' "$OPSX_FAKE_LOG"
cp "$WP0" "$R/openspec/workplan.yaml"
rm -f "$MEMO"; printf '{}' > "$DISP"

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

# --- --dry 只印，不送不記 ---
rm -f "$MEMO"
round --dry || fail "dry rc: $(cat "$FX/out")"
assert_grep 'DRY herdr notification show \[demo/a1\]' "$FX/out"
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

# 主 change m2 的依賴 m1 沒合：不派；m3 的 PR 沒依賴，但 feature g 等 m1：也不派
sess_wp pending
cards '[{"slug":"m2"},{"slug":"m3"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "依賴沒合：主 change 不派、feature 的卡不派：$(cat "$OPSX_FAKE_LOG")"
grep '⏳' "$LOG" | grep 'm2' | grep -q 'm1' || fail "主 change m2 要記等 m1：$(cat "$LOG")"
grep '⏳' "$LOG" | grep 'feature g' | grep -q 'm1' || fail "feature g 要記等 m1：$(cat "$LOG")"

# m1 合了：m2、m3 都照單卡派；coordinate 不自動開 session（gate session-bugs-2）
sess_wp merged
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx dispatch m2 --agent claude" "$OPSX_FAKE_LOG"
assert_grep "^opsx dispatch m3 --agent claude" "$OPSX_FAKE_LOG"
assert_not_grep "^opsx dispatch --feature" "$OPSX_FAKE_LOG"

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

# session 的 pane 不在了：同 feature 各卡 stop 一次，整個 feature 重派一次，不逐卡派
sess_wp merged; rm -f "$MEMO"
printf '{"demo/m3":{%s,"branch":"feat/m3/u"},"demo/m4":{%s,"branch":"feat/m4/u"}}' "$G_SESS" "$G_SESS" > "$DISP"
GD='{"mode":"autopilot","agent":"claude","pane":"w1:p9","feature":"g","drive_pid":null}'
cards '[{"slug":"m3","section":"進行中","dispatch":'"$GD"',"agent_status":"unknown"},{"slug":"m4","section":"進行中","dispatch":'"$GD"',"agent_status":"unknown"}]'
round || fail "rc: $(cat "$FX/out")"
got="$(grep -E '^opsx (stop|dispatch)' "$OPSX_FAKE_LOG")"
assert_eq "$got" "opsx stop m3 --repo $R
opsx stop m4 --repo $R
opsx dispatch --feature g --agent claude --mode autopilot --repo $R" "session 死掉：各卡 stop、feature 重派一次"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "十分鐘內不再重派這個 feature"
rm -f "$MEMO"
cp "$WP0" "$R/openspec/workplan.yaml"; printf '{}' > "$DISP"
echo "coordinate: ok"
