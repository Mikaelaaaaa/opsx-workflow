#!/usr/bin/env bash
# bin/lib/mr.sh：mr_json 五條件逐項 + head_sha + 60 秒快取；mr_state 照舊印短字串（drive 用）。
# 驗收：specs/board-collect/spec.md「五條件全綠才是可以合併」「少一個條件留在進行中」（herdr-board 2.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/glab.log"; : > "$OPSX_FAKE_LOG"
source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; source "$OPSX_ROOT/bin/lib/mr.sh"

field() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1].split("."): d=d[k]
print(json.dumps(d) if isinstance(d,(dict,list,bool)) or d is None else d)' "$2"; }

C="$FX/repo/openspec/changes/x"; mkdir -p "$C" "$OPSX_STATE_DIR"

# --- 沒有 MR ---
assert_eq "$(mr_state "$C")" none "report.md 不存在"
assert_eq "$(field "$(mr_json "$C")" state)" none

# --- 五條件全綠 ---
printf '# r\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/Agentory-CS/-/merge_requests/431\n' > "$C/report.md"
export OPSX_TEST_GLAB_JSON="$FX/mr.json" OPSX_MR_CACHE_TTL=0
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
j="$(mr_json "$C")"
assert_eq "$(field "$j" state)" ready
assert_eq "$(field "$j" head_sha)" abc123
assert_eq "$(field "$j" conditions)" '{"opened": true, "not_draft": true, "no_conflicts": true, "pipeline": true, "threads": true}'
assert_eq "$(field "$j" blocked_on)" null
assert_eq "$(field "$j" url)" "https://gitlab.tsg-navigator.com/agentory/Agentory-CS/-/merge_requests/431"
assert_eq "$(mr_state "$C")" ready

# --- pipeline 紅：state 照舊、conditions 指出哪一條、blocked_on ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"failed"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
j="$(mr_json "$C")"
assert_eq "$(field "$j" state)" "pipeline:failed"
assert_eq "$(field "$j" conditions.pipeline)" false
assert_eq "$(field "$j" blocked_on)" pipeline

# --- 兩個未解 thread ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":2}' > "$OPSX_TEST_GLAB_JSON"
assert_eq "$(mr_state "$C")" "threads:2"
assert_eq "$(field "$(mr_json "$C")" blocked_on)" threads

# --- glab 讀不到：none 但 url 留著 ---
printf '' > "$OPSX_TEST_GLAB_JSON"
j="$(mr_json "$C")"; assert_eq "$(field "$j" state)" none; assert_eq "$(field "$j" conditions)" null
assert_eq "$(field "$j" url)" "https://gitlab.tsg-navigator.com/agentory/Agentory-CS/-/merge_requests/431"

# --- 快取：TTL 60 內第二次不打 glab；TTL 0 一定打；讀不到時不寫快取 ---
: > "$OPSX_FAKE_LOG"; export OPSX_MR_CACHE_TTL=60
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
mr_json "$C" >/dev/null; mr_json "$C" >/dev/null
assert_eq "$(grep -c '^mr view' "$OPSX_FAKE_LOG" || true)" 1 "60 秒內只打一次 glab"
assert_file "$OPSX_STATE_DIR/cache/mr-x.json"
printf '{"state":"merged","sha":"abc123"}' > "$OPSX_TEST_GLAB_JSON"
assert_eq "$(mr_state "$C")" ready "TTL 內讀快取，不看新值"
export OPSX_MR_CACHE_TTL=0
assert_eq "$(mr_state "$C")" "state:merged" "TTL 0 重抓"
rm -f "$OPSX_STATE_DIR/cache/mr-x.json"; printf '' > "$OPSX_TEST_GLAB_JSON"
mr_json "$C" >/dev/null; assert_no_file "$OPSX_STATE_DIR/cache/mr-x.json"

# --- drive 仍能用 mr_state（它改成 source mr.sh）---
grep -q 'bin/lib/mr.sh' "$OPSX_ROOT/bin/lib/drive.sh" || fail "drive.sh 要 source mr.sh，不自己留一份 mr_state"
! grep -q '^mr_state()' "$OPSX_ROOT/bin/lib/drive.sh" || fail "drive.sh 裡不該再定義 mr_state"
echo ok
