#!/usr/bin/env bash
# opsx merge：重驗五條件 → dispatch.json 寫一次性核准 → decisions → herdr agent prompt "/babysit merge"。不自己跑 glab mr merge。
# 驗收：specs/board-actions/spec.md「核准合併」兩個 Scenario（herdr-board 3.2）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_TEST_GLAB_JSON="$FX/mr.json"

R="$(mk_repo Agentory-AI)"; C="$R/openspec/changes/x"; mk_change "$R" x; mkdir -p "$OPSX_STATE_DIR"
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/Agentory-AI/-/merge_requests/431\n' > "$C/report.md"
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
cd "$R"

# --- 全綠 ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
out="$(opsx merge x 2>&1)"; assert_eq "$?" 0 "merge: $out"
assert_eq "$(jq -r '."Agentory-AI/x".merge_approved' "$OPSX_STATE_DIR/dispatch.json")" abc123
jq -e '."Agentory-AI/x".merge_approved_at | startswith("20")' "$OPSX_STATE_DIR/dispatch.json" >/dev/null || fail "要有 merge_approved_at"
assert_grep $'\tyou\tmerge-approved\tabc123' "$C/decisions.tsv"
assert_grep '^agent prompt x /babysit merge abc123$' "$OPSX_FAKE_LOG"
# 互動模式的卡：沒有閘門，拒絕並說去 pane
printf '{"Agentory-AI/x":{"mode":"interactive","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx merge x 2>&1)"; [ $? -ne 0 ] || fail "互動模式要拒絕"; echo "$out" | grep -q 'pane' || fail "要說去 pane: $out"
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"; : > "$OPSX_FAKE_LOG"
assert_not_grep '^mr merge' "$OPSX_FAKE_LOG"   # 不自己合

# --- 有未解 thread：退出非零、什麼都不寫 ---
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
cp "$C/decisions.tsv" "$FX/before.tsv"; : > "$OPSX_FAKE_LOG"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":2}' > "$OPSX_TEST_GLAB_JSON"
out="$(opsx merge x 2>&1)"; [ $? -ne 0 ] || fail "threads 要退出非零"
echo "$out" | grep -q 'threads' || fail "要說哪條沒過: $out"
assert_eq "$(jq -r '."Agentory-AI/x".merge_approved // "none"' "$OPSX_STATE_DIR/dispatch.json")" none
cmp -s "$C/decisions.tsv" "$FX/before.tsv" || fail "decisions 不該變"; assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG" || true)" 0

# --- 快取裡是舊的全綠，merge 也要重抓（TTL 不作數）---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
OPSX_MR_CACHE_TTL=600 opsx collect --root "$FX" >/dev/null 2>&1 || true   # 把全綠灌進快取
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"failed"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
out="$(opsx merge x 2>&1)"; [ $? -ne 0 ] || fail "merge 要重抓，不吃快取: $out"

# --- 沒派出的卡：沒 agent 可執行，拒絕 ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx merge x 2>&1)"; [ $? -ne 0 ] || fail "沒派出要拒絕"; echo "$out" | grep -q '沒派出' || fail "要說沒派出: $out"
# --- 代管卡（auto-dispatch）：送給 herdr_name，prompt 帶 slug ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"claude","grants":[],"via":"p","herdr_name":"p"}}' > "$OPSX_STATE_DIR/dispatch.json"; : > "$OPSX_FAKE_LOG"
out="$(opsx merge x 2>&1)"; assert_eq "$?" 0 "代管卡 merge: $out"
assert_grep '^agent prompt p /babysit merge abc123 x$' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."Agentory-AI/x".merge_approved' "$OPSX_STATE_DIR/dispatch.json")" abc123
echo ok
