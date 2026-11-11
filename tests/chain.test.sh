#!/usr/bin/env bash
# auto-dispatch：pane 撐完一條相依鏈。續接、fan-out 登記、代管卡的送話與停止。
# 驗收：specs/opsx-chain/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_TEST_GLAB_JSON="$FX/mr.json"

R="$(mk_repo Agentory-AI)"; mk_change "$R" p; mkdir -p "$OPSX_STATE_DIR"
cd "$R"

# --- 已交接的父卡：merge / answer / stop 都拒絕，訊息說交給誰，不碰 herdr 也不動檔 ---
P="$R/openspec/changes/p"
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/Agentory-AI/-/merge_requests/431\n' > "$P/report.md"
printf '## g1\ntype: decision\nstatus: open\n問題: q\n選項: a | b\n' > "$P/gates.md"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
printf '{"Agentory-AI/p":{"mode":"autopilot","pane":"w5:pQ","agent":"claude","grants":[],"herdr_name":"p","handed_to":["c"],"handed_at":"2026-11-06T15:00:00+08:00"}}' > "$OPSX_STATE_DIR/dispatch.json"
cp "$OPSX_STATE_DIR/dispatch.json" "$FX/disp.before"; cp "$P/gates.md" "$FX/gates.before"
for cmd in "stop p" "merge p" "answer p --gate g1 a"; do
  : > "$OPSX_FAKE_LOG"
  out="$(opsx $cmd 2>&1)"; rc=$?
  [ $rc -ne 0 ] || fail "已交接的卡 opsx $cmd 要拒絕: $out"
  echo "$out" | grep -q 'c' && echo "$out" | grep -q '交接' || fail "opsx $cmd 的訊息要說交接給 c: $out"
  assert_not_grep '^pane close' "$OPSX_FAKE_LOG"; assert_not_grep '^agent prompt' "$OPSX_FAKE_LOG"
  cmp -s "$OPSX_STATE_DIR/dispatch.json" "$FX/disp.before" || fail "opsx $cmd 不該動 dispatch.json"
  cmp -s "$P/gates.md" "$FX/gates.before" || fail "opsx $cmd 不該動 gates.md"
done

# --- 找子卡（3.1）：workplan 裡 depends-on 父卡的 PR ---
wp() { cat > "$R/openspec/workplan.yaml" <<'EOF'
created: 2026-11-06

features:
  - name: demo
    status: active
    prs:
      - name: p
        branch: feat/p/mikaela
        status: merged
        depends-on: []
        description: "父卡"
        changes:
          - name: p
            status: done
  - name: demo-q
    prs:
      - name: q
        branch: feat/q/mikaela
        status: pending   # 還沒合
        depends-on: []
        changes:
          - name: q
            status: pending
  - name: demo-d
    prs:
      - name: d
        branch: feat/d/mikaela
        status: pending
        depends-on: [p, q]
        changes:
          - name: d
            status: pending
  - name: demo-e
    prs:
      - name: e
        branch: feat/e/mikaela
        status: pending
        depends-on: [p]
        changes:
          - name: e
            status: pending
  - name: demo-f
    prs:
      - name: f
        branch: feat/f/mikaela
        status: pending
        depends-on: [p]
        changes:
          - name: f
            status: pending
EOF
}
wp
for s in d e f; do mkdir -p "$R/openspec/changes/$s"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/$s/.openspec.yaml"; done
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/d/tasks.md"; printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/f/tasks.md"
printf '## 一句話\n\ne\n' > "$R/openspec/changes/e/inbox.md"     # e 只有 inbox.md：收件匣的卡

# 父卡不在 dispatch.json（人手動開的 pane）
printf '{}' > "$OPSX_STATE_DIR/dispatch.json"; : > "$OPSX_FAKE_LOG"
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "父卡沒派出: $out"
echo "$out" | grep -q 'dispatch.json' || fail "要說父卡不在 dispatch.json: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "父卡沒派出不碰 herdr"; assert_eq "$(cat "$OPSX_STATE_DIR/dispatch.json")" "{}"

# 父卡派出了，可是 d 還有沒合的依賴、e 是收件匣的卡、f 已經在跑：一張都不接
printf '{"Agentory-AI/p":{"mode":"autopilot","pane":"w5:pQ","agent":"claude","grants":[],"worktree":"%s","branch":"feat/p/mikaela"},"Agentory-AI/f":{"mode":"autopilot","pane":"w5:pZ","agent":"claude","grants":[]}}' "$R" > "$OPSX_STATE_DIR/dispatch.json"
cp "$OPSX_STATE_DIR/dispatch.json" "$FX/disp.before"; : > "$OPSX_FAKE_LOG"
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "沒有子卡可接: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "沒有子卡可接不碰 herdr"
cmp -s "$OPSX_STATE_DIR/dispatch.json" "$FX/disp.before" || fail "沒有子卡可接，dispatch.json 不該動"
assert_no_file "$R/openspec/changes/e/decisions.tsv"; assert_no_file "$R/openspec/changes/d/decisions.tsv"
assert_eq "$(git -C "$R" branch --show-current)" "feat/p/mikaela" "沒有子卡可接，branch 不動"

# --- workplan 的 YAML 子集（不靠 pyyaml）：block list、[a, b]、引號、行尾註解 ---
cat > "$FX/wp.yaml" <<'EOF'
created: 2026-11-06
features:
  - name: x
    prs:
      - name: a
        branch: "feat/a/m"
        status: merged   # 已合
        depends-on: []
        description: "有 # 號的描述"
        changes:
          - name: a
            status: done
      - name: b
        depends-on:
          - a
          - c
        changes: []
EOF
got="$(python3 -I -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import chain, json
w = chain.load_workplan(sys.argv[2]); prs = w["features"][0]["prs"]
print(json.dumps([prs[0]["branch"], prs[0]["status"], prs[0]["depends-on"], prs[0]["description"], prs[1]["depends-on"], prs[1]["changes"]], ensure_ascii=False))' "$OPSX_ROOT/bin/lib" "$FX/wp.yaml")"
assert_eq "$got" '["feat/a/m", "merged", [], "有 # 號的描述", ["a", "c"], []]' "workplan 解析"

# --- 多張子卡全部 fan out（4.1）：登記代管條目，不切 branch、不改名、不碰 herdr ---
R2="$(mk_repo fan)"; mk_change "$R2" p
cat > "$R2/openspec/workplan.yaml" <<'EOF'
features:
  - name: x
    prs:
      - name: p
        branch: feat/p/mikaela
        status: merged
        changes:
          - name: p
            status: done
  - name: x1
    prs:
      - name: c1
        branch: feat/c1/mikaela
        status: pending
        depends-on: [p]
        changes:
          - name: c1
            status: pending
  - name: x2
    prs:
      - name: c2
        branch: feat/c2/mikaela
        status: pending
        depends-on: [p]
        changes:
          - name: c2
            status: pending
EOF
for s in c1 c2; do mkdir -p "$R2/openspec/changes/$s"; printf -- '- [ ] 1.1 x\n' > "$R2/openspec/changes/$s/tasks.md"; done
printf 'schema: opsx\nkind: bug-fix\n' > "$R2/openspec/changes/c1/.openspec.yaml"; printf 'schema: opsx\nkind: dev\n' > "$R2/openspec/changes/c2/.openspec.yaml"
fanout_entry() { printf '{"fan/p":{"mode":"%s","pane":"w5:pQ","tab":"w5:tJ","workspace":"opsx","workspace_id":"w5","agent":"claude","model":"claude-opus-5-5","kind":"dev","grants":[],"worktree":"%s","branch":"feat/p/mikaela","started_at":"2026-11-06T13:00:00+08:00","drive_pid":null}}' "$1" "$R2" > "$OPSX_STATE_DIR/dispatch.json"; }
fanout_entry autopilot; : > "$OPSX_FAKE_LOG"; cd "$R2"
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "fan-out: $out"
echo "$out" | grep -q 'c1' && echo "$out" | grep -q 'c2' || fail "stdout 要列出 c1、c2: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "fan-out 不碰 herdr（pane 不改名）"
assert_eq "$(git -C "$R2" branch --show-current)" "feat/p/mikaela" "fan-out 不切 branch"
J="$OPSX_STATE_DIR/dispatch.json"
for s in c1 c2; do
  assert_eq "$(jq -r --arg k "fan/$s" '.[$k] | [.via, .herdr_name, .pane, .tab, .workspace_id, .agent, .mode, (.worktree|tostring)] | join(" ")' "$J")" "p p w5:pQ w5:tJ w5 claude autopilot null" "$s 的代管條目"
  assert_grep "自動派：因 p merged" "$R2/openspec/changes/$s/decisions.tsv"
  assert_grep $'\t系統\t已指派\t自動派' "$R2/openspec/changes/$s/decisions.tsv"   # opsx-log 的五欄格式
done
assert_eq "$(jq -r '."fan/c1" | [.branch, .kind, .model] | join(" ")' "$J")" "feat/c1/mikaela bug-fix claude-sonnet-5-5" "c1 的 branch / kind / 照 kind 的 model"
assert_eq "$(jq -r '."fan/c2" | [.branch, .kind, .model] | join(" ")' "$J")" "feat/c2/mikaela dev claude-opus-5-5"
assert_eq "$(jq -r '."fan/p".handed_to | join(",")' "$J")" "c1,c2" "父卡要記交接給誰"
jq -e '."fan/p".handed_at | startswith("20")' "$J" >/dev/null || fail "父卡要有 handed_at"
cp "$J" "$FX/disp.before"; out="$(opsx chain p 2>&1)"; assert_eq "$?" 0; cmp -s "$J" "$FX/disp.before" || fail "已交接再跑不該動 dispatch.json"

# 父卡是 autopilot（或舊名 drive）：代管卡沒有自己的 agent 可以讓 drive 送話，寫進 decisions
for s in c1 c2; do : > "$R2/openspec/changes/$s/decisions.tsv"; done
fanout_entry autopilot
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "autopilot fan-out: $out"
for s in c1 c2; do assert_grep "drive 不支援代管卡" "$R2/openspec/changes/$s/decisions.tsv"; done
for s in c1 c2; do : > "$R2/openspec/changes/$s/decisions.tsv"; done
fanout_entry drive
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "drive fan-out: $out"
assert_eq "$(jq -r '[."fan/c1".mode, ."fan/c2".mode] | join(" ")' "$J")" "autopilot autopilot"
for s in c1 c2; do assert_grep "drive 不支援代管卡" "$R2/openspec/changes/$s/decisions.tsv"; done
cd "$R"

# --- 停一張代管卡（4.2）：請 pane 停那個 subagent，標 stopped；不關 pane，兄弟卡不動 ---
cd "$R2"; fanout_entry autopilot; opsx chain p >/dev/null 2>&1 || fail "fan-out 準備"
cp "$J" "$FX/disp.before"; : > "$OPSX_FAKE_LOG"
out="$(opsx stop c1 2>&1)"; assert_eq "$?" 0 "stop 代管卡: $out"
assert_grep '^agent prompt p \[c1\] stop$' "$OPSX_FAKE_LOG"
assert_not_grep '^pane close' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."fan/c1".mode' "$J")" stopped; jq -e '."fan/c1".stopped_at | startswith("20")' "$J" >/dev/null || fail "c1 要有 stopped_at"
assert_eq "$(jq -c '."fan/c2"' "$J")" "$(jq -c '."fan/c2"' "$FX/disp.before")" "c2 不該被動到"
assert_grep $'\t已停止\t' "$R2/openspec/changes/c1/decisions.tsv"
cd "$R"

# --- 單一子卡續接（3.2–3.4）：本地 bare repo 當 origin，父卡就在 R3 這棵 worktree ---
ORIGIN="$FX/origin3.git"; git init -q --bare "$ORIGIN"
R3="$(mk_repo solo "$ORIGIN")"; git -C "$R3" branch -M main; git -C "$R3" push -q origin main
printf 'openspec/\n' >> "$R3/.git/info/exclude"    # 跟真的 repo 一樣，openspec/ 不進 git
# 6.3：像 Agentory-AI 一樣，gitlab 是主要 remote，origin 是落後的鏡像；父卡的合併只在 gitlab 的 main 上
git clone -q --bare "$ORIGIN" "$FX/mirror3.git"
git -C "$R3" remote rename origin gitlab; git -C "$R3" remote add origin "$FX/mirror3.git"
git clone -q -b main "$ORIGIN" "$FX/pusher3"; git -C "$FX/pusher3" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "merge p"; git -C "$FX/pusher3" push -q origin HEAD:main
mk_change "$R3" p; mkdir -p "$R3/openspec/changes/c"
printf 'schema: opsx\nkind: dev\n' > "$R3/openspec/changes/c/.openspec.yaml"; printf -- '- [ ] 1.1 x\n' > "$R3/openspec/changes/c/tasks.md"
cat > "$R3/openspec/workplan.yaml" <<'EOF'
features:
  - name: x
    prs:
      - name: p
        branch: feat/p/mikaela
        status: merged
        changes:
          - name: p
            status: done
  - name: x2
    prs:
      - name: c
        branch: feat/c/mikaela
        status: pending
        depends-on: [p]
        changes:
          - name: c
            status: pending
EOF
solo_entry() { printf '{"solo/p":{"mode":"%s","pane":"w5:pQ","tab":"w5:tJ","workspace":"opsx","workspace_id":"w5","agent":"claude","model":"claude-opus-5-5","kind":"dev","grants":[],"worktree":"%s","branch":"feat/p/mikaela","started_at":"2026-11-06T13:00:00+08:00","drive_pid":null}}' "$1" "$R3" > "$OPSX_STATE_DIR/dispatch.json"; }
Q="$OPSX_STATE_DIR/herdr-queue/solo-c.tsv"
cd "$R3"

# 髒 tree（3.3）：不接，branch 不動，不寫佇列，decisions 說原因
solo_entry autopilot; echo dirty > "$R3/stray.txt"; : > "$OPSX_FAKE_LOG"
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "髒 tree: $out"
assert_eq "$(git -C "$R3" branch --show-current)" "feat/p/mikaela" "髒 tree 不切 branch"
assert_no_file "$Q"; assert_eq "$(cat "$OPSX_FAKE_LOG")" ""
assert_grep "未 commit 的改動" "$R3/openspec/changes/c/decisions.tsv"
assert_eq "$(jq -r '."solo/c" // "none"' "$OPSX_STATE_DIR/dispatch.json")" none "髒 tree 不登記子卡"
mv "$R3/stray.txt" "$FX/"   # 把 tree 弄回乾淨

# 子卡 branch 被別棵 worktree 佔用（3.3）
: > "$R3/openspec/changes/c/decisions.tsv"; git -C "$R3" worktree add -q "$FX/other-wt" -b feat/c/mikaela main; : > "$OPSX_FAKE_LOG"
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "branch 被佔: $out"
assert_eq "$(git -C "$R3" branch --show-current)" "feat/p/mikaela"; assert_no_file "$Q"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "branch 被佔不碰 herdr"
assert_grep "$(cd "$FX" && pwd -P)/other-wt" "$R3/openspec/changes/c/decisions.tsv"
git -C "$R3" worktree remove -f "$FX/other-wt"; git -C "$R3" branch -q -D feat/c/mikaela

# 子卡 branch 本地已存在（6.5）：不接，不切到可能過時的舊 branch
: > "$R3/openspec/changes/c/decisions.tsv"; git -C "$R3" branch -q feat/c/mikaela main
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "branch 已存在: $out"
assert_eq "$(git -C "$R3" branch --show-current)" "feat/p/mikaela" "branch 已存在不切"; assert_no_file "$Q"
assert_grep "本地已存在" "$R3/openspec/changes/c/decisions.tsv"
git -C "$R3" branch -q -D feat/c/mikaela

# workplan 的 PR 沒有 branch（6.2）：拒絕並說出是哪個 PR，什麼都不動
cp "$R3/openspec/workplan.yaml" "$FX/wp3.bak"; grep -v 'branch: feat/c/mikaela' "$FX/wp3.bak" > "$R3/openspec/workplan.yaml"
cp "$OPSX_STATE_DIR/dispatch.json" "$FX/disp.before"
out="$(opsx chain p 2>&1)"; [ $? -ne 0 ] || fail "PR 沒有 branch 要拒絕: $out"
echo "$out" | grep -q 'branch' && echo "$out" | grep -q '「c」' || fail "要說是 PR c 沒有 branch: $out"
assert_eq "$(git -C "$R3" branch --show-current)" "feat/p/mikaela"; assert_no_file "$Q"
cmp -s "$OPSX_STATE_DIR/dispatch.json" "$FX/disp.before" || fail "PR 沒有 branch 不該動 dispatch.json"
cp "$FX/wp3.bak" "$R3/openspec/workplan.yaml"

# 寫 dispatch.json 失敗（6.4）：chain 要失敗，不寫佇列（lock 檔換成目錄，jsonfile.update 打不開）
mv "$OPSX_STATE_DIR/dispatch.json.lock" "$FX/lock.bak"; mkdir "$OPSX_STATE_DIR/dispatch.json.lock"
out="$(opsx chain p 2>&1)"; [ $? -ne 0 ] || fail "寫 dispatch.json 失敗要讓 chain 失敗: $out"
assert_no_file "$Q"
rmdir "$OPSX_STATE_DIR/dispatch.json.lock"; mv "$FX/lock.bak" "$OPSX_STATE_DIR/dispatch.json.lock"
git -C "$R3" switch -q feat/p/mikaela; git -C "$R3" branch -q -D feat/c/mikaela 2>/dev/null || true

# 乾淨 tree（3.2）：切到子卡 branch（不帶 tracking）、登記、寫佇列；chain 自己不叫 herdr
: > "$R3/openspec/changes/c/decisions.tsv"; : > "$OPSX_FAKE_LOG"
mkdir -p "$(dirname "$Q")"; printf 'keep me\n' > "$FX/victim"; ln -s "$FX/victim" "$Q"   # symlink-safe-writes：佇列檔名被換成 symlink
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "單一續接: $out"
assert_eq "$(cat "$FX/victim")" "keep me" "佇列檔名上的 symlink 不能被寫到目標"
[ ! -L "$Q" ] || fail "佇列檔要換成一般檔，不留 symlink"
assert_eq "$(git -C "$R3" branch --show-current)" "feat/c/mikaela" "切到子卡 branch"
assert_eq "$(git -C "$R3" config --get branch.feat/c/mikaela.remote || echo none)" none "不帶 upstream tracking"
assert_eq "$(git -C "$R3" log -1 --format=%s)" "merge p" "從主要 remote（gitlab）的 main 開，含父卡的合併（6.3）"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "chain 不叫 herdr（D5）"
assert_eq "$(cat "$Q")" "$(printf 'rename\tp\tc\nprompt\tc\t/opsx-workflow:apply c\ndrive\tc\t%s' "$R3")" "佇列：autopilot 一律起 drive"
J="$OPSX_STATE_DIR/dispatch.json"
assert_eq "$(jq -r '."solo/c" | [.pane, .tab, .herdr_name, .mode, .agent, .kind, .branch, (.via // "none")] | join(" ")' "$J")" "w5:pQ w5:tJ c autopilot claude dev feat/c/mikaela none"
assert_eq "$(jq -r '."solo/c".worktree' "$J")" "$R3"
assert_eq "$(jq -r '."solo/p" | [(.handed_to | join(",")), .herdr_name] | join(" ")' "$J")" "c c" "父卡交接，herdr 名跟著改名"
assert_grep "自動派：因 p merged" "$R3/openspec/changes/c/decisions.tsv"

# drive（3.4）：子卡沿用 drive，佇列多一行 drive
git -C "$R3" switch -q feat/p/mikaela; git -C "$R3" branch -q -D feat/c/mikaela; : > "$Q"
solo_entry drive; : > "$R3/openspec/changes/c/decisions.tsv"
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "drive 續接: $out"
assert_eq "$(jq -r '."solo/c".mode' "$J")" drive
assert_eq "$(tail -1 "$Q")" "$(printf 'drive\tc\t%s' "$R3")" "drive 模式佇列最後一行"
cd "$R"

# --- 子卡照等級（priority-dispatch）：P2 不接，其餘 P0 先 ---
R4="$(mk_repo prio)"; mk_change "$R4" p
cat > "$R4/openspec/workplan.yaml" <<'EOF'
features:
  - name: x
    prs:
      - name: p
        branch: feat/p/mikaela
        status: merged
        changes:
          - name: p
            status: done
  - name: xa
    prs:
      - name: child-a
        branch: feat/child-a/mikaela
        status: pending
        depends-on: [p]
        changes:
          - name: child-a
            status: pending
  - name: xb
    prs:
      - name: child-b
        branch: feat/child-b/mikaela
        status: pending
        depends-on: [p]
        changes:
          - name: child-b
            status: pending
EOF
for s in child-a child-b; do mkdir -p "$R4/openspec/changes/$s"; printf -- '- [ ] 1.1 x\n' > "$R4/openspec/changes/$s/tasks.md"; done
printf '{"prio/p":{"mode":"autopilot","pane":"w5:pQ","agent":"claude","grants":[]}}' > "$FX/disp4.json"
kids() { python3 -I -B "$OPSX_ROOT/bin/lib/chain.py" children "$R4" prio p "$FX/disp4.json"; }

# 多張子卡照等級排：child-a 是 P1（在 workplan、沒設 milestone），child-b 是 P0
printf -- '---\nkind_of_work: incident\nimpact: data\nevidence: tests/x.test.sh 第 2 案\n---\n' > "$R4/openspec/changes/child-b/inbox.md"
out="$(kids)"; assert_eq "$?" 0 "children: $out"
assert_eq "$(echo "$out" | cut -f1,2)" "$(printf 'child\tchild-b\nchild\tchild-a')" "P0 的子卡先：$out"

# P2 子卡不接：child-b 改成 P2，只剩 child-a
printf -- '---\npriority: P2\npriority_reason: 不急\n---\n' > "$R4/openspec/changes/child-b/inbox.md"
out="$(kids)"; assert_eq "$?" 0 "children: $out"
assert_eq "$(echo "$out" | cut -f1,2)" "$(printf 'child\tchild-a')" "P2 子卡不接：$out"

# 子卡全是 P2：skip，原因含 P2
cp "$R4/openspec/changes/child-b/inbox.md" "$R4/openspec/changes/child-a/inbox.md"
out="$(kids)"; assert_eq "$?" 0 "children: $out"
echo "$out" | grep -q $'^skip\t.*P2' || fail "全是 P2 要 skip、原因含 P2：$out"
echo "$out" | grep -q '^child' && fail "全是 P2 不能印 child：$out"

# --- 主 change（殼名 = PR 名，changes[] 是子 change）：chain 用 PR 名找得到 ---
R4="$(mk_repo sess)"; mk_change "$R4" m1
# sess_wp <m2 前面插的行>：單卡續接時 m2 自成一個 feature（同 feature 兩個 PR 就由 session 代管），feature session 時 m2 留在 f
sess_wp() { cat > "$R4/openspec/workplan.yaml" <<EOF
features:
  - name: f
    depends-on: []
    prs:
      - name: m1
        branch: feat/m1/u
        status: merged
        depends-on: []
        changes:
          - name: s1
            status: done
          - name: s2
            status: done
$1      - name: m2
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
        depends-on: [m1]
        changes:
          - name: m3
            status: pending
EOF
}
sess_wp "  - name: f2
    prs:
"
for s in m2 m3; do mkdir -p "$R4/openspec/changes/$s"; printf 'schema: opsx\nkind: dev\n' > "$R4/openspec/changes/$s/.openspec.yaml"; printf -- '- [ ] 1.1 x\n' > "$R4/openspec/changes/$s/tasks.md"; done
J="$OPSX_STATE_DIR/dispatch.json"
printf '{"sess/m1":{"mode":"autopilot","pane":"w5:pQ","tab":"w5:tJ","workspace":"opsx","workspace_id":"w5","agent":"claude","kind":"dev","grants":[],"worktree":"%s","branch":"feat/m1/u"}}' "$R4" > "$J"
got="$(python3 -I "$OPSX_ROOT/bin/lib/chain.py" children "$R4" sess m1 "$J")"
assert_eq "$got" "$(printf 'child\tm2\tfeat/m2/u\tdev')" "主 change 合併後找得到依賴它的主 change（不是 changes[0] 的 t1）；m3 在有 depends-on 的 feature g，由 coordinate 開 session，chain 不接"

# --- feature session：m1 合併後同一個 session 接 m2（同 feature），m3 在別的 feature 留給 coordinate ---
# m1 的 pane 是舊值（session 重派過）：新成員的 pane 要取自 session 條目 sess/@f
sess_wp ""
printf '{"sess/@f":{"mode":"autopilot","pane":"w5:pS","tab":"w5:tK","workspace":"opsx","workspace_id":"w5","agent":"claude","model":"m","worktree":"%s","started_at":"t","drive_pid":null},"sess/m1":{"mode":"autopilot","pane":"w5:pQ","tab":"w5:tJ","workspace":"opsx","workspace_id":"w5","agent":"claude","kind":"dev","grants":[],"worktree":"%s","branch":"feat/m1/u","herdr_name":"f","via":"@f","feature":"f"}}' "$R4" "$R4" > "$J"
cd "$R4"; : > "$OPSX_FAKE_LOG"
printf 'keep me\n' > "$FX/victim"; ln -s "$FX/victim" "$OPSX_STATE_DIR/herdr-queue/sess-m2.tsv"   # symlink-safe-writes
out="$(opsx chain m1 2>&1)"; assert_eq "$?" 0 "feature 續接: $out"
assert_eq "$(cat "$FX/victim")" "keep me" "session 佇列檔名上的 symlink 不能被寫到目標"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "feature 續接不開 pane、chain 不直接叫 herdr"
assert_eq "$(cat "$OPSX_STATE_DIR/herdr-queue/sess-m2.tsv")" "$(printf 'prompt\tf\t[m2] /opsx-workflow:apply m2')" "佇列：送進同一個 session，前綴 [m2]"
assert_eq "$(jq -r '."sess/m2" | [.herdr_name, .via, .feature, .pane, .branch, .worktree] | join(" ")' "$J")" "f @f f w5:pS feat/m2/u $R4" "m2 掛在同一個 session，pane 取自 session 條目"
assert_eq "$(jq -r '."sess/m2".tab' "$J")" "w5:tK" "tab 也取自 session 條目"
assert_eq "$(jq -r '."sess/m1".handed_to // "none"' "$J")" none "session 沒交出去，父主 change 不記交接"
assert_eq "$(jq -r '."sess/m3" // "none"' "$J")" none "別的 feature 不由 chain 開"
assert_eq "$(git -C "$R4" branch --show-current)" "feat/m1/mikaela" "chain 不替 session 切 branch"
cd "$R"

# --- 被拆的原卡（split-continue-register）：原卡不在 workplan，照 split_into 接第一個能開工的主 change ---
ORIGIN6="$FX/origin6.git"; git init -q --bare "$ORIGIN6"
R6="$(mk_repo split "$ORIGIN6")"; git -C "$R6" branch -M main; git -C "$R6" push -q origin main
printf 'openspec/\n' >> "$R6/.git/info/exclude"
mk_change "$R6" c
printf -- '---\ntype: bug\nsplit_into: m1, m2\n---\n\n## 一句話\n\nc\n' > "$R6/openspec/changes/c/inbox.md"
for s in m1 m2; do mkdir -p "$R6/openspec/changes/$s"; printf '## 一句話\n\n%s\n' "$s" > "$R6/openspec/changes/$s/inbox.md"; done
split_wp() { cat > "$R6/openspec/workplan.yaml" <<EOF
features:
  - name: x
    prs:
      - name: m1
        branch: fix/m1/mikaela
        status: pending
        depends-on: [$1]
        changes:
          - name: m1
            status: pending
  - name: y
    prs:
      - name: m2
        branch: fix/m2/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m2
            status: pending
EOF
}
split_entry() { printf '{"split/c":{"mode":"autopilot","pane":"w5:pC","tab":"w5:tC","workspace":"opsx","workspace_id":"w5","agent":"claude","model":"claude-opus-5-5","kind":"bug-fix","grants":[],"worktree":"%s","branch":"feat/c/mikaela","herdr_name":"c","started_at":"2026-11-11T10:00:00+08:00","drive_pid":null}}' "$R6" > "$OPSX_STATE_DIR/dispatch.json"; }
split_reset() { git -C "$R6" switch -q feat/c/mikaela; git -C "$R6" branch -q -D fix/m1/mikaela fix/m2/mikaela 2>/dev/null; : > "$OPSX_FAKE_LOG"; rm -f "$OPSX_STATE_DIR"/herdr-queue/split-*.tsv; split_entry; }
cd "$R6"

# 拆卡後接第一個主 change：m1、m2 都沒依賴、都只有 inbox.md
split_wp ""; split_reset
out="$(opsx chain c 2>&1)"; assert_eq "$?" 0 "拆卡續接: $out"
assert_eq "$(git -C "$R6" branch --show-current)" "fix/m1/mikaela" "原卡的 worktree 切到 m1 的分支"
assert_eq "$(jq -r '."split/m1" | [.pane, .tab, .herdr_name, .mode, .branch, .worktree] | join(" ")' "$J")" "w5:pC w5:tC m1 autopilot fix/m1/mikaela $R6" "m1 登記在原卡的 pane"
assert_eq "$(jq -r '."split/c".handed_to | join(",")' "$J")" "m1" "原卡記 handed_to"
assert_eq "$(jq -r '."split/m2" // "none"' "$J")" none "只接一張，不 fan out"
assert_eq "$(cat "$OPSX_STATE_DIR/herdr-queue/split-m1.tsv")" "$(printf 'rename\tc\tm1\nprompt\tm1\t/opsx-workflow:explore m1\ndrive\tm1\t%s' "$R6")" "佇列：改名成 m1、送 explore"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "chain 不直接叫 herdr"

# 原卡已交接過不再接
cp "$J" "$FX/disp6.before"
out="$(opsx chain c 2>&1)"; assert_eq "$?" 0 "已交接: $out"
echo "$out" | grep -q '已經交接給 m1' || fail "要說已經交接給 m1: $out"
cmp -s "$J" "$FX/disp6.before" || fail "已交接過，dispatch.json 不該動"

# 拆出來的主 change 還沒 propose 也接：m1 依賴 m2，接的是 m2
split_wp m2; split_reset
out="$(opsx chain c 2>&1)"; assert_eq "$?" 0 "拆卡續接 m2: $out"
assert_eq "$(git -C "$R6" branch --show-current)" "fix/m2/mikaela" "m1 依賴沒合，接 m2"
assert_eq "$(jq -r '."split/c".handed_to | join(",")' "$J")" "m2"
assert_eq "$(jq -r '."split/m1" // "none"' "$J")" none

# split_into 是空值：照舊當成不在 workplan
for v in '[]' '""' '~' 'null' ''; do
  printf -- '---\nsplit_into: %s\n---\n' "$v" > "$R6/openspec/changes/c/inbox.md"; split_reset
  out="$(opsx chain c 2>&1)"; assert_eq "$?" 0 "split_into 空值 $v: $out"
  echo "$out" | grep -q 'workplan 裡沒有 c' || fail "split_into「$v」算沒拆: $out"
done

# split_into 寫成 [m1, m2] 也認得
printf -- '---\nsplit_into: [m1, "m2"]\n---\n' > "$R6/openspec/changes/c/inbox.md"; split_wp ""; split_reset
got="$(python3 -I "$OPSX_ROOT/bin/lib/chain.py" children "$R6" split c "$J")"
assert_eq "$got" "$(printf 'child\tm1\tfix/m1/mikaela\tdev')" "list 寫法"

# split_into 的主 change 都有活的條目：skip
printf '{"split/c":{"mode":"autopilot","pane":"w5:pC","worktree":"%s"},"split/m1":{"mode":"autopilot"},"split/m2":{"mode":"autopilot"}}' "$R6" > "$J"
out="$(python3 -I "$OPSX_ROOT/bin/lib/chain.py" children "$R6" split c "$J")"
echo "$out" | grep -q $'^skip\t' || fail "主 change 都在做要 skip: $out"

# m1、m2 拆進同一個沒有 depends-on 的 feature x（由 session 代管）：剛拆出來的殼只有 inbox.md，coordinate 不接，所以原卡照樣單卡接 m1
cat > "$R6/openspec/workplan.yaml" <<'EOF'
features:
  - name: x
    prs:
      - name: m1
        branch: fix/m1/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m1
            status: pending
      - name: m2
        branch: fix/m2/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m2
            status: pending
EOF
printf '{"split/c":{"mode":"autopilot","pane":"w5:pC","worktree":"%s"}}' "$R6" > "$J"
out="$(python3 -I "$OPSX_ROOT/bin/lib/chain.py" children "$R6" split c "$J")"
assert_eq "$out" "$(printf 'child\tm1\tfix/m1/mikaela\tdev')" "session 代管的 feature 拆卡照樣接第一張"

# split_into 指到有 depends-on 的 feature 底下的主 change：交給 coordinate 照 feature 依賴開 session，不接
cat > "$R6/openspec/workplan.yaml" <<'EOF'
features:
  - name: f1
    prs:
      - name: a
        branch: fix/a/mikaela
        status: pending
        depends-on: []
        changes:
          - name: a
            status: pending
  - name: f2
    depends-on: [a]
    prs:
      - name: m1
        branch: fix/m1/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m1
            status: pending
EOF
printf -- '---\nsplit_into: m1\n---\n' > "$R6/openspec/changes/c/inbox.md"; split_entry
out="$(python3 -I "$OPSX_ROOT/bin/lib/chain.py" children "$R6" split c "$J")"
echo "$out" | grep -q $'^skip\t' || fail "feature 有 depends-on 的主 change 要 skip: $out"
# feature 的依賴都合了：照常接（coordinate 的 feature_plan 不派沒有 tasks.md 的殼，這裡不接就沒人接）
python3 -I -c 'import sys;p=sys.argv[1];s=open(p).read();open(p,"w").write(s.replace("status: pending","status: merged",1))' "$R6/openspec/workplan.yaml"
out="$(python3 -I "$OPSX_ROOT/bin/lib/chain.py" children "$R6" split c "$J")"
assert_eq "$out" "$(printf 'child\tm1\tfix/m1/mikaela\tdev')" "feature 依賴已合要接 m1"

# --unclaimed：split_into 裡沒合、沒有活條目、沒有 tasks.md 的主 change，一行一張，附還沒合的依賴（PR 與 feature 兩層）
cat > "$R6/openspec/workplan.yaml" <<'EOF'
features:
  - name: f1
    prs:
      - name: a
        branch: fix/a/mikaela
        status: pending
        depends-on: []
        changes:
          - name: a
            status: pending
      - name: m1
        branch: fix/m1/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m1
            status: pending
      - name: m2
        branch: fix/m2/mikaela
        status: pending
        depends-on: [m1]
        changes:
          - name: m2
            status: pending
  - name: f2
    depends-on: [a]
    prs:
      - name: m3
        branch: fix/m3/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m3
            status: pending
EOF
mkdir -p "$R6/openspec/changes/m3"; printf '## 一句話\n\nm3\n' > "$R6/openspec/changes/m3/inbox.md"
printf -- '---\nsplit_into: m1, m2, m3\n---\n' > "$R6/openspec/changes/c/inbox.md"
printf '{"split/c":{"mode":"autopilot","pane":"w5:pC","worktree":"%s","handed_to":["m1"]},"split/m1":{"mode":"autopilot","pane":"w5:pC"}}' "$R6" > "$J"
cp "$J" "$FX/disp-unclaimed.before"
out="$(opsx chain --unclaimed c 2>&1)"; assert_eq "$?" 0 "--unclaimed: $out"
assert_eq "$out" "$(printf 'm2\tm1\nm3\ta')" "m1 有活條目不列；m2 等 m1；m3 等 feature 依賴 a"
cmp -s "$J" "$FX/disp-unclaimed.before" || fail "--unclaimed 只讀，dispatch.json 不該動"
# 有 tasks.md 的交給 coordinate，不列；人停掉的條目不算活的
: > "$R6/openspec/changes/m2/tasks.md"
printf '{"split/m1":{"mode":"stopped","pane":"w5:pC"}}' > "$J"
out="$(opsx chain --unclaimed c 2>&1)"
assert_eq "$out" "$(printf 'm1\t\nm3\ta')" "有 tasks.md 的 m2 不列；停掉的 m1 要列"
rm -f "$R6/openspec/changes/m2/tasks.md"
cd "$R"

# --- 多 PR 根 feature 由 session 代管：單卡 m1 合併後，chain 不接 r2，照接單 PR 根 feature 的 s1 ---
R7="$(mk_repo root)"; mk_change "$R7" m1
cat > "$R7/openspec/workplan.yaml" <<'EOF'
features:
  - name: solo
    prs:
      - name: m1
        branch: feat/m1/u
        status: merged
        changes:
          - name: m1
            status: done
  - name: r
    prs:
      - name: r1
        branch: feat/r1/u
        status: pending
        depends-on: []
        changes:
          - name: r1
            status: pending
      - name: r2
        branch: feat/r2/u
        status: pending
        depends-on: [m1]
        changes:
          - name: r2
            status: pending
  - name: s
    prs:
      - name: s1
        branch: feat/s1/u
        status: pending
        depends-on: [m1]
        changes:
          - name: s1
            status: pending
EOF
for s in r2 s1; do mkdir -p "$R7/openspec/changes/$s"; printf -- '- [ ] 1.1 x\n' > "$R7/openspec/changes/$s/tasks.md"; done
printf '{"root/m1":{"mode":"autopilot","pane":"w5:pQ","agent":"claude","grants":[]}}' > "$FX/disp7.json"
got="$(python3 -I -B "$OPSX_ROOT/bin/lib/chain.py" children "$R7" root m1 "$FX/disp7.json")"
assert_eq "$got" "$(printf 'child\ts1\tfeat/s1/u\tdev')" "多 PR 根 feature 的 r2 留給 coordinate 開 session，單 PR 根 feature 的 s1 照接"
echo ok
