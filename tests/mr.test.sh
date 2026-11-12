#!/usr/bin/env bash
# bin/lib/mr.sh：mr_json 五條件逐項 + head_sha + 60 秒快取（鍵是 URL）+ -R project + GitHub 路徑 + error；mr_state 短字串。
# 驗收：specs/board-collect/spec.md「五條件全綠才是可以合併」「少一個條件留在進行中」「外部來源失敗不毀掉整份」（herdr-board 2.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/glab.log"; : > "$OPSX_FAKE_LOG"
source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; source "$OPSX_ROOT/bin/lib/mr.sh"; source "$OPSX_ROOT/bin/lib/python.sh"; opsx_python_load || fail "$OPSX_PY_ERR"

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

# --- OPSX_MR_STALE_OK=1（只有 collect 帶）：過期快取先回舊的、背景重抓一次；其他呼叫端照舊同步抓（collect-background / mr-fetch-off-path）---
ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
wait_unlock() { # 背景重抓結束時會拿掉 lock 目錄；最多等 5 秒
  local i
  for i in $(seq 50); do [ -d "$1" ] || return 0; sleep 0.1; done
  fail "背景重抓 5 秒內沒放掉 $1"
}
CACHE="$OPSX_STATE_DIR/cache/mr-$(printf '%s' "https://gitlab.tsg-navigator.com/agentory/Agentory-CS/-/merge_requests/431" | shasum | cut -c1-12).json"
OLD='{"url": "x", "state": "ready", "head_sha": "old111"}'
SLOWBIN="$FX/slow-glab"; mkdir -p "$SLOWBIN"
printf '#!/usr/bin/env bash\n[ "$1 $2" = "mr view" ] && sleep 2\nexec bash "%s/tests/fakes/glab" "$@"\n' "$OPSX_ROOT" > "$SLOWBIN/glab"; chmod +x "$SLOWBIN/glab"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"new222","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
stale_cache() { printf '%s\n' "$OLD" > "$CACHE"; touch -t 202601010000 "$CACHE"; : > "$OPSX_FAKE_LOG"; }

# 過期：1 秒內回舊內容；連叫兩次只重抓一次；重抓完快取換成新的
stale_cache
t0="$(ms)"; j="$(PATH="$SLOWBIN:$PATH" OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C")"; elapsed=$(( $(ms) - t0 ))
assert_eq "$j" "$OLD" "過期快取要先回舊內容"
[ "$elapsed" -lt 1000 ] || fail "STALE_OK 不該等 glab，花了 ${elapsed} ms"
assert_eq "$(PATH="$SLOWBIN:$PATH" OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C")" "$OLD" "重抓還沒完成，第二次也回舊內容"
wait_unlock "$CACHE.lock"
assert_eq "$(grep -c '^mr view' "$OPSX_FAKE_LOG" || true)" 1 "同一個 MR 只重抓一次"
assert_eq "$(field "$(cat "$CACHE")" head_sha)" new222 "背景重抓要寫回快取"
# 背景重抓不在呼叫端的 process group 裡（server.py 逾時會 killpg collect）
stale_cache
PATH="$SLOWBIN:$PATH" perl -e 'setpgrp(0, 0); exec @ARGV' bash -c '
  source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; source "$OPSX_ROOT/bin/lib/mr.sh"; source "$OPSX_ROOT/bin/lib/python.sh"; opsx_python_load
  OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$1" >/dev/null; sleep 5' _ "$C" &
pg=$!; sleep 0.5; kill -TERM -- "-$pg"; wait "$pg"
wait_unlock "$CACHE.lock"
assert_eq "$(field "$(cat "$CACHE")" head_sha)" new222 "呼叫端的 process group 被殺，背景重抓仍要寫完快取"
# 抓不到不寫快取，lock 照樣放掉
stale_cache; printf '' > "$OPSX_TEST_GLAB_JSON"
OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C" >/dev/null
wait_unlock "$CACHE.lock"
assert_eq "$(cat "$CACHE")" "$OLD" "抓不到時保留舊快取"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"new222","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
# 別支還拿著 lock：不重抓；lock 超過 120 秒當死鎖，接手重抓
stale_cache; mkdir "$CACHE.lock"
OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C" >/dev/null; sleep 0.5
assert_eq "$(grep -c '^mr view' "$OPSX_FAKE_LOG" || true)" 0 "lock 被拿著時不重抓"
touch -t 202601010000 "$CACHE.lock"
OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C" >/dev/null
wait_unlock "$CACHE.lock"
assert_eq "$(grep -c '^mr view' "$OPSX_FAKE_LOG" || true)" 1 "死鎖接手後要重抓"
# lock 裡記了持有者 pid：pid 已經不在就立即接手（不等 120 秒）；pid 還活著就不接手
stale_cache; mkdir "$CACHE.lock"; ( : ) & DEAD=$!; wait "$DEAD"; printf '%s\n' "$DEAD" > "$CACHE.lock/pid"
OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C" >/dev/null
wait_unlock "$CACHE.lock"
assert_eq "$(grep -c '^mr view' "$OPSX_FAKE_LOG" || true)" 1 "持有者 pid 已死要立即接手重抓"
stale_cache; mkdir "$CACHE.lock"; sleep 30 & LIVE=$!; printf '%s\n' "$LIVE" > "$CACHE.lock/pid"
OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C" >/dev/null; sleep 0.5
assert_eq "$(grep -c '^mr view' "$OPSX_FAKE_LOG" || true)" 0 "持有者 pid 還活著不能接手"
kill "$LIVE"; rm -f "$CACHE.lock/pid"; rmdir "$CACHE.lock"
# 背景重抓開起來後 lock 裡有它的 pid
stale_cache
PATH="$SLOWBIN:$PATH" OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C" >/dev/null
[ -s "$CACHE.lock/pid" ] || fail "背景重抓要把 pid 寫進 lock 目錄"
wait_unlock "$CACHE.lock"
# 沒帶 STALE_OK：過期照舊同步抓、回新內容
stale_cache
j="$(PATH="$SLOWBIN:$PATH" OPSX_MR_CACHE_TTL=60 mr_json "$C")"
assert_eq "$(field "$j" head_sha)" new222 "其他呼叫端同步抓"
assert_no_file "$CACHE.lock"
# 沒有快取：STALE_OK 也同步抓
rm -f "$CACHE"; : > "$OPSX_FAKE_LOG"
assert_eq "$(field "$(OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C")" head_sha)" new222 "沒快取時同步抓"
assert_file "$CACHE"
# 除錯用的子命令：opsx mr <card dir> 印 mr_json
assert_eq "$(field "$(OPSX_MR_CACHE_TTL=60 opsx mr "$C")" head_sha)" new222
# 手動 --refresh 沒拿鎖：正常結束，也不刪別支拿著的鎖
rm -f "$CACHE"; rm -rf "$CACHE.lock"
OPSX_MR_CACHE_TTL=60 opsx mr "$C" --refresh || fail "沒有鎖時手動 --refresh 要退出 0"
assert_file "$CACHE"
mkdir "$CACHE.lock"
OPSX_MR_CACHE_TTL=60 opsx mr "$C" --refresh || fail "別支拿著鎖時手動 --refresh 要退出 0"
[ -d "$CACHE.lock" ] || fail "手動 --refresh 不該刪別支拿著的鎖"
rmdir "$CACHE.lock"
# 背景重抓的 forge 呼叫要有時間上限，而且比 120 秒的死鎖上限短，接手死鎖時舊的那支已經被殺了
ENVBIN="$FX/env-glab"; mkdir -p "$ENVBIN"
printf '#!/usr/bin/env bash\n[ "$1 $2" = "mr view" ] && echo "timeout=${OPSX_MR_TIMEOUT:-}" >> "%s/refresh-env"\nexec bash "%s/tests/fakes/glab" "$@"\n' "$FX" "$OPSX_ROOT" > "$ENVBIN/glab"; chmod +x "$ENVBIN/glab"
stale_cache; rm -f "$FX/refresh-env"
# 呼叫端沒設 OPSX_MR_TIMEOUT：上限要是 mr.sh 自己帶的，不是從呼叫端繼承來的
(unset OPSX_MR_TIMEOUT; PATH="$ENVBIN:$PATH" OPSX_MR_CACHE_TTL=60 OPSX_MR_STALE_OK=1 mr_json "$C" >/dev/null)
wait_unlock "$CACHE.lock"
t="$(sed -n 's/^timeout=//p' "$FX/refresh-env")"
[ -n "$t" ] && [ "$t" -gt 0 ] && [ "$t" -lt 120 ] || fail "背景重抓的 OPSX_MR_TIMEOUT 要介於 0 和 120 秒之間，實際是「${t}」"
# 帶著鎖的 --refresh 碰上掛住的 forge：時限內殺掉、放掉鎖、快取不動
stale_cache; mkdir "$CACHE.lock"
t0="$(date +%s)"
OPSX_TEST_GLAB_SLEEP=30 OPSX_MR_TIMEOUT=1 OPSX_MR_CACHE_TTL=60 opsx mr "$C" --refresh "$CACHE.lock" || fail "逾時的 --refresh 要退出 0"
elapsed=$(( $(date +%s) - t0 ))
[ "$elapsed" -lt 5 ] || fail "掛住的 forge 要在時限內被殺，花了 ${elapsed} 秒"
assert_no_file "$CACHE.lock"
assert_eq "$(cat "$CACHE")" "$OLD" "逾時抓不到時保留舊快取"
printf '%s' "$GREEN" > "$OPSX_TEST_GLAB_JSON"

# --- forge 查詢的時間上限：OPSX_MR_TIMEOUT 沒設就不限時，設了逾時要殺掉、錯誤文字說逾時 ---
unset OPSX_MR_TIMEOUT
assert_eq "$(mr_forge sh -c 'sleep 2; echo ok')" ok "沒設 OPSX_MR_TIMEOUT 不限時"
t0="$(date +%s)"; OPSX_MR_TIMEOUT=1 mr_forge sleep 6 >/dev/null; rc=$?; elapsed=$(( $(date +%s) - t0 ))
assert_eq "$rc" 124 "逾時退出碼 124"; [ "$elapsed" -lt 4 ] || fail "要在時限內殺掉，花了 ${elapsed} 秒"
printf '%s' "$GREEN" > "$OPSX_TEST_GLAB_JSON"
t0="$(date +%s)"; j="$(OPSX_TEST_GLAB_SLEEP=6 OPSX_MR_TIMEOUT=1 mr_json "$C")"; elapsed=$(( $(date +%s) - t0 ))
[ "$elapsed" -lt 4 ] || fail "忽略 SIGALRM 的 CLI 也要在時限內殺掉，花了 ${elapsed} 秒"
assert_eq "$(field "$j" state)" none
field "$j" error | grep -q '逾時' || fail "error 要說逾時: $(field "$j" error)"
field "$j" error | grep -q '沒登入' && fail "逾時不該說沒登入: $(field "$j" error)"
mkdir -p "$FX/noperl"; printf '#!/bin/sh\nexit 127\n' > "$FX/noperl/perl"; chmod +x "$FX/noperl/perl"
j="$(PATH="$FX/noperl:$PATH" OPSX_MR_TIMEOUT=1 mr_json "$C")"
field "$j" error | grep -q 'perl' || fail "找不到 perl 要點名: $(field "$j" error)"
field "$j" error | grep -q '沒登入' && fail "找不到 perl 不該說沒登入: $(field "$j" error)"

# --- drive 仍能用 mr_state（它改成 source mr.sh）---
grep -q 'bin/lib/mr.sh' "$OPSX_ROOT/bin/lib/drive.sh" || fail "drive.sh 要 source mr.sh，不自己留一份 mr_state"
! grep -q '^mr_state()' "$OPSX_ROOT/bin/lib/drive.sh" || fail "drive.sh 裡不該再定義 mr_state"
echo ok
