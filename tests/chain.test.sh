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
      - name: q
        branch: feat/q/mikaela
        status: pending   # 還沒合
        depends-on: []
        changes:
          - name: q
            status: pending
      - name: d
        branch: feat/d/mikaela
        status: pending
        depends-on: [p, q]
        changes:
          - name: d
            status: pending
      - name: e
        branch: feat/e/mikaela
        status: pending
        depends-on: [p]
        changes:
          - name: e
            status: pending
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
got="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import chain, json
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
      - name: c1
        branch: feat/c1/mikaela
        status: pending
        depends-on: [p]
        changes:
          - name: c1
            status: pending
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
done
assert_eq "$(jq -r '."fan/c1" | [.branch, .kind, .model] | join(" ")' "$J")" "feat/c1/mikaela bug-fix claude-sonnet-5-5" "c1 的 branch / kind / 照 kind 的 model"
assert_eq "$(jq -r '."fan/c2" | [.branch, .kind, .model] | join(" ")' "$J")" "feat/c2/mikaela dev claude-opus-5-5"
assert_eq "$(jq -r '."fan/p".handed_to | join(",")' "$J")" "c1,c2" "父卡要記交接給誰"
jq -e '."fan/p".handed_at | startswith("20")' "$J" >/dev/null || fail "父卡要有 handed_at"
cp "$J" "$FX/disp.before"; out="$(opsx chain p 2>&1)"; assert_eq "$?" 0; cmp -s "$J" "$FX/disp.before" || fail "已交接再跑不該動 dispatch.json"

# 父卡是 drive：代管卡沒有自己的 agent 可以讓 drive 送話，改記 autopilot 並寫進 decisions
for s in c1 c2; do : > "$R2/openspec/changes/$s/decisions.tsv"; done
fanout_entry drive
out="$(opsx chain p 2>&1)"; assert_eq "$?" 0 "drive fan-out: $out"
assert_eq "$(jq -r '[."fan/c1".mode, ."fan/c2".mode] | join(" ")' "$J")" "autopilot autopilot"
for s in c1 c2; do assert_grep "drive 不支援代管卡" "$R2/openspec/changes/$s/decisions.tsv"; done
cd "$R"
echo ok
