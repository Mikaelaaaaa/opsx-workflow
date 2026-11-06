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
echo ok
