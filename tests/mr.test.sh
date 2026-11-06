#!/usr/bin/env bash
# bin/lib/mr.sh：mr_json 五條件逐項 + head_sha + 60 秒快取（鍵是 URL）+ -R project + GitHub 路徑 + error；mr_state 短字串。
# 驗收：specs/board-collect/spec.md「五條件全綠才是可以合併」「少一個條件留在進行中」「外部來源失敗不毀掉整份」（herdr-board 2.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/glab.log"; : > "$OPSX_FAKE_LOG"
source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; source "$OPSX_ROOT/bin/lib/mr.sh"

field() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1].split("."): d=d[k]
print(json.dumps(d) if isinstance(d,(dict,list,bool)) or d is None else d)' "$2"; }

C="$FX/repo/openspec/changes/x"; mkdir -p "$C" "$OPSX_STATE_DIR"
GREEN='{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}'

# --- 沒有 MR ---
assert_eq "$(mr_state "$C")" none "report.md 不存在"
assert_eq "$(field "$(mr_json "$C")" state)" none

# --- 五條件全綠；-R 從 URL 解出來 ---
printf '# r\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/Agentory-CS/-/merge_requests/431\n' > "$C/report.md"
export OPSX_TEST_GLAB_JSON="$FX/mr.json" OPSX_MR_CACHE_TTL=0
printf '%s' "$GREEN" > "$OPSX_TEST_GLAB_JSON"
j="$(mr_json "$C")"
assert_eq "$(field "$j" state)" ready
assert_eq "$(field "$j" head_sha)" abc123
assert_eq "$(field "$j" conditions)" '{"opened": true, "not_draft": true, "no_conflicts": true, "pipeline": true, "threads": true}'
assert_eq "$(field "$j" blocked_on)" null; assert_eq "$(field "$j" error)" null
assert_eq "$(field "$j" url)" "https://gitlab.tsg-navigator.com/agentory/Agentory-CS/-/merge_requests/431"
assert_grep '^mr view 431 -R gitlab.tsg-navigator.com/agentory/Agentory-CS -F json$' "$OPSX_FAKE_LOG"
assert_eq "$(mr_state "$C")" ready
assert_eq "$(field "$j" created_at)" null "樣本沒有時間就是 null"
# GitLab 的開啟與合併時間
printf '{"state":"merged","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":0,"created_at":"2026-11-05T01:00:00.000Z","merged_at":"2026-11-06T03:00:00.000Z"}' > "$OPSX_TEST_GLAB_JSON"
j="$(mr_json "$C")"
assert_eq "$(field "$j" created_at)" "2026-11-05T01:00:00.000Z"; assert_eq "$(field "$j" merged_at)" "2026-11-06T03:00:00.000Z"
printf '%s' "$GREEN" > "$OPSX_TEST_GLAB_JSON"

# --- pipeline 紅：state 照舊、conditions 指出哪一條、blocked_on ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"failed"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
j="$(mr_json "$C")"
assert_eq "$(field "$j" state)" "pipeline:failed"; assert_eq "$(field "$j" conditions.pipeline)" false; assert_eq "$(field "$j" blocked_on)" pipeline

# --- 兩個未解 thread ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc123","head_pipeline":{"status":"success"},"unresolved_discussions_count":2}' > "$OPSX_TEST_GLAB_JSON"
assert_eq "$(mr_state "$C")" "threads:2"; assert_eq "$(field "$(mr_json "$C")" blocked_on)" threads

# --- glab 讀不到：none、url 留著、error 說是哪條指令 ---
printf '' > "$OPSX_TEST_GLAB_JSON"
j="$(mr_json "$C")"; assert_eq "$(field "$j" state)" none; assert_eq "$(field "$j" conditions)" null
assert_eq "$(field "$j" url)" "https://gitlab.tsg-navigator.com/agentory/Agentory-CS/-/merge_requests/431"
field "$j" error | grep -q 'glab mr view 431 -R gitlab.tsg-navigator.com/agentory/Agentory-CS' || fail "error 要說是哪條指令: $(field "$j" error)"
printf 'not json' > "$OPSX_TEST_GLAB_JSON"; field "$(mr_json "$C")" error | grep -q '不是 JSON' || fail "壞 JSON 要有 error"

# --- GitHub：-R owner/repo、欄位是真 gh 有的、checks 還在跑不算過、CHANGES_REQUESTED 算 threads ---
C2="$FX/repo/openspec/changes/gh"; mkdir -p "$C2"
printf '# r\n\n## MR\nhttps://github.com/Mikaelaaaaa/scam-guard/pull/33\n' > "$C2/report.md"
export OPSX_TEST_GH_JSON="$FX/pr.json"
printf '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"9c1f3a","reviewDecision":"","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","state":"SUCCESS"}]}' > "$OPSX_TEST_GH_JSON"
: > "$OPSX_FAKE_LOG"; j="$(mr_json "$C2")"
assert_eq "$(field "$j" state)" ready "github ready: $j"; assert_eq "$(field "$j" head_sha)" 9c1f3a
assert_grep '^pr view 33 -R Mikaelaaaaa/scam-guard --json ' "$OPSX_FAKE_LOG"
printf '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","headRefOid":"9c1f3a","reviewDecision":"","statusCheckRollup":[{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":null}]}' > "$OPSX_TEST_GH_JSON"
assert_eq "$(mr_state "$C2")" "pipeline:failed" "check 還在跑不算過"
printf '{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","headRefOid":"9c1f3a","reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[]}' > "$OPSX_TEST_GH_JSON"
assert_eq "$(mr_state "$C2")" "threads:1" "CHANGES_REQUESTED 當未解"
printf '{"state":"MERGED","isDraft":false,"mergeable":"UNKNOWN","mergeStateStatus":"CLEAN","headRefOid":"9c1f3a","reviewDecision":"","statusCheckRollup":[],"createdAt":"2026-11-05T02:00:00Z","mergedAt":null}' > "$OPSX_TEST_GH_JSON"
assert_eq "$(mr_state "$C2")" "state:MERGED"
assert_eq "$(field "$(mr_json "$C2")" created_at)" "2026-11-05T02:00:00Z"; assert_eq "$(field "$(mr_json "$C2")" merged_at)" null

# --- 快取：鍵是 URL；TTL 60 內第二次不打；兩個 repo 同 slug 不同 MR 不互串；TTL 0 一定打；讀不到時不寫 ---
: > "$OPSX_FAKE_LOG"; export OPSX_MR_CACHE_TTL=60
printf '%s' "$GREEN" > "$OPSX_TEST_GLAB_JSON"
mr_json "$C" >/dev/null; mr_json "$C" >/dev/null
assert_eq "$(grep -c '^mr view' "$OPSX_FAKE_LOG" || true)" 1 "60 秒內只打一次 glab"
[ "$(ls "$OPSX_STATE_DIR/cache/" | grep -c '^mr-.*\.json$')" -ge 1 ] || fail "要有快取檔"
C3="$FX/other/openspec/changes/x"; mkdir -p "$C3"   # 另一個 repo、同 slug x、不同 MR
printf '# r\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/Other/-/merge_requests/8\n' > "$C3/report.md"
export OPSX_TEST_GLAB_JSON_BY_IID="$FX/mr-"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"fff999","head_pipeline":{"status":"failed"},"unresolved_discussions_count":0}' > "$FX/mr-8.json"
assert_eq "$(mr_state "$C3")" "pipeline:failed" "同 slug 不同 repo 不能吃到 x 的快取"
assert_eq "$(mr_state "$C")" ready "原來那張還是快取的 ready"
unset OPSX_TEST_GLAB_JSON_BY_IID
printf '{"state":"merged","sha":"abc123"}' > "$OPSX_TEST_GLAB_JSON"
assert_eq "$(mr_state "$C")" ready "TTL 內讀快取，不看新值"
export OPSX_MR_CACHE_TTL=0
assert_eq "$(mr_state "$C")" "state:merged" "TTL 0 重抓"
rm -f "$OPSX_STATE_DIR"/cache/mr-*.json; printf '' > "$OPSX_TEST_GLAB_JSON"
OPSX_MR_CACHE_TTL=60 mr_json "$C" >/dev/null; [ -z "$(ls "$OPSX_STATE_DIR/cache/" 2>/dev/null)" ] || fail "讀不到時不該寫快取"
# 並行寫同一個快取：都要成功（固定 tmp 檔名會讓第二個 mv 失敗）
printf '%s' "$GREEN" > "$OPSX_TEST_GLAB_JSON"
( OPSX_MR_CACHE_TTL=60 mr_json "$C" >/dev/null ) & ( OPSX_MR_CACHE_TTL=60 mr_json "$C" >/dev/null ) & wait
[ "$(ls "$OPSX_STATE_DIR/cache/" | grep -c '^mr-.*\.json$')" = 1 ] || fail "並行後應只有一個快取檔：$(ls "$OPSX_STATE_DIR/cache/")"

# --- drive 仍能用 mr_state（它改成 source mr.sh）---
grep -q 'bin/lib/mr.sh' "$OPSX_ROOT/bin/lib/drive.sh" || fail "drive.sh 要 source mr.sh，不自己留一份 mr_state"
! grep -q '^mr_state()' "$OPSX_ROOT/bin/lib/drive.sh" || fail "drive.sh 裡不該再定義 mr_state"
echo ok
