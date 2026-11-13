#!/usr/bin/env bash
# bin/lib/runtime.sh：卡片身分查表、每個動詞送給 herdr 的 argv、開 agent、回報協調者。
# 驗收：openspec/changes/runtime-module/subs/runtime-sh/specs/agent-runtime/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
use_herdr_argv_log
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_DISPATCH_RETRY_SLEEP=0
source "$OPSX_ROOT/bin/lib/common.sh"
source "$OPSX_ROOT/bin/lib/python.sh"
opsx_python_load || fail "$OPSX_PY_ERR"
J="$OPSX_STATE_DIR/dispatch.json"
calls() { cat "$OPSX_FAKE_LOG"; }
argv_calls() { cat "$OPSX_FAKE_LOG.sep"; }
reset() { : > "$OPSX_FAKE_LOG"; : > "$OPSX_FAKE_LOG.sep"; }

# --- 卡片身分查出 herdr agent 名與 pane（Examples 一般與邊界） ---
cat > "$J" <<'EOF'
{"r/card-a": {"pane": "w1:p1", "tab": "w1:t1"},
 "r/card-b": {"pane": "w1:p2", "herdr_name": "card-b"},
 "r/child": {"pane": "w1:p3", "herdr_name": "feat-x", "feature": "feat-x", "via": "@feat-x"},
 "r/@feat-x": {"pane": "w1:p3"},
 "r/renamed": {"pane": "w1:p4", "herdr_name": "other"},
 "r/opsx-coordinator": {"pane": "w9:p9", "herdr_name": "zzz"}}
EOF
row() { # <key> <名> <pane>
  reset
  runtime_prompt "$1" hi nowait >/dev/null || fail "$1 傳話 rc"
  runtime_read "$1" >/dev/null || fail "$1 讀畫面 rc"
  assert_eq "$(calls)" "agent prompt $2 hi
pane read $3" "$1 的 argv"
}
row r/card-a card-a w1:p1
row r/card-b card-b w1:p2
row r/child feat-x w1:p3
row r/@feat-x feat-x w1:p3
row r/renamed other w1:p4

# --- 沒有條目的卡：傳話用 slug；讀畫面查不到 pane，非 0、stderr 含卡片身分、不叫 herdr ---
reset; runtime_prompt r/fresh hi nowait >/dev/null || fail "沒有條目的卡傳話 rc"
assert_eq "$(calls)" "agent prompt fresh hi" "沒有條目的卡傳話用 slug"
reset; err="$( (runtime_read r/fresh) 2>&1 >/dev/null)"; [ $? -ne 0 ] || fail "沒有條目的卡讀畫面要非 0"
case "$err" in *r/fresh*) ;; *) fail "錯誤訊息要有卡片身分：$err" ;; esac
assert_eq "$(calls)" "" "查不到 pane 不叫 herdr"
# dispatch.json 不存在：名字照樣推得出來
mv "$J" "$J.bak"
reset; runtime_prompt r/@feat-y hi nowait >/dev/null || fail "dispatch.json 不存在時傳話 rc"
assert_eq "$(calls)" "agent prompt feat-y hi" "沒有 dispatch.json 時 @feature 去掉 @"
reset; (runtime_close r/card-a tab) >/dev/null 2>&1 && fail "沒有 dispatch.json 時關 tab 要非 0"
assert_eq "$(calls)" "" "沒有 dispatch.json 時不叫 herdr"
mv "$J.bak" "$J"
# 不是卡片身分的字（沒有 /）不當成卡
reset; (runtime_prompt card-a hi nowait) >/dev/null 2>&1 && fail "沒有 / 的對象要非 0"
assert_eq "$(calls)" "" "對象不是卡片身分不叫 herdr"

# --- 不是卡的 agent：--agent 指名，不讀 dispatch.json ---
reset; OPSX_TEST_COORDINATOR_UP=1 runtime_prompt --agent opsx-coordinator "[x] 停住" nowait >/dev/null || fail "--agent 傳話 rc"
assert_eq "$(calls)" "agent prompt opsx-coordinator [x] 停住" "對協調者傳話"
assert_eq "$(argv_calls)" $'agent\x1fprompt\x1fopsx-coordinator\x1f[x] 停住' "含空白的一行原樣是一個參數"
reset; OPSX_TEST_COORDINATOR_UP=1 runtime_prompt --agent opsx-coordinator hi nowait >/dev/null
assert_eq "$(calls)" "agent prompt opsx-coordinator hi" "agent 參數不被當成卡片身分（r/opsx-coordinator 的 herdr_name 是 zzz）"
# 壞的 JSON、又有 opsx-coordinator 這個 key：--agent 只要讀了 dispatch.json 就會失敗或改名
cp "$J" "$J.good"; printf '{"opsx-coordinator": {"herdr_name": "zzz"}' > "$J"
reset; OPSX_TEST_COORDINATOR_UP=1 runtime_prompt --agent opsx-coordinator hi nowait >/dev/null || fail "--agent 在壞的 dispatch.json 下要 rc 0"
assert_eq "$(argv_calls)" $'agent\x1fprompt\x1fopsx-coordinator\x1fhi' "--agent 不讀 dispatch.json"
mv "$J.good" "$J"
reset; (runtime_read --agent opsx-coordinator) >/dev/null 2>&1 && fail "--agent 沒有 pane，讀畫面要非 0"
assert_eq "$(calls)" "" "--agent 讀畫面不叫 herdr"

# --- 動詞對應的 herdr argv ---
verb() { # <期望 argv> <動詞與參數…>
  local want="$1"; shift
  reset; "$@" >/dev/null || fail "$* rc"
  assert_eq "$(calls)" "$want" "$*"
}
verb "agent prompt card-a hi" runtime_prompt r/card-a hi nowait
verb "pane read w1:p1" runtime_read r/card-a
verb "agent read w1:p1 --lines 10 --format text" runtime_read r/card-a --lines 10
OPSX_TEST_AGENT_GET_RAW='{}' verb "agent get card-a" runtime_get r/card-a
verb "agent wait card-a" runtime_wait r/card-a
verb "agent wait card-a --until working" runtime_wait r/card-a --until working
verb "agent focus card-a" runtime_focus r/card-a
verb "pane close w1:p1" runtime_close r/card-a pane
verb "tab close w1:t1" runtime_close r/card-a tab
verb "agent wait card-a --until idle --timeout 60000" runtime_wait r/card-a --until idle --timeout 60000
verb "pane send-keys w1:p1 esc
pane send-text w1:p1 /exit
pane send-keys w1:p1 enter" runtime_close r/card-a exit
verb "agent list" runtime_list
verb "notification show t --body b" runtime_notify t b
verb "notification show t --body b --sound request" runtime_notify t b --sound request
# 不認得的參數：非 0，不叫 herdr
reset; (runtime_wait r/card-a --forever) >/dev/null 2>&1 && fail "wait 不認得的參數要非 0"
reset; (runtime_close r/card-a window) >/dev/null 2>&1 && fail "close 不認得的模式要非 0"
reset; (runtime_notify t b --volume 3) >/dev/null 2>&1 && fail "notify 不認得的參數要非 0"
reset; (runtime_notify t b --sound) >/dev/null 2>&1 && fail "notify 的 --sound 沒有值要非 0"
assert_eq "$(calls)" "" "參數不對不叫 herdr"
# 有條目但沒有 tab：關 tab 非 0、訊息有卡片身分
reset; err="$( (runtime_close r/card-b tab) 2>&1 >/dev/null)"; [ $? -ne 0 ] || fail "沒有 tab 的卡關 tab 要非 0"
case "$err" in *r/card-b*) ;; *) fail "關 tab 的錯誤要有卡片身分：$err" ;; esac
assert_eq "$(calls)" "" "沒有 tab 不叫 herdr"
# 送 /exit：esc 送不出去就停，不再送 /exit 與 enter
mkdir -p "$FX/escfail"
cat > "$FX/escfail/herdr" <<'EOF'
#!/usr/bin/env bash
case "$*" in "pane send-keys "*" esc") printf '%s\n' "$*" >> "$OPSX_FAKE_LOG"; echo '{"error":{"code":"pane_not_found","message":"fake"}}' >&2; exit 1 ;; esac
exec bash "$OPSX_ROOT/tests/fakes/herdr" "$@"
EOF
chmod +x "$FX/escfail/herdr"
reset; (PATH="$FX/escfail:$PATH"; runtime_close r/card-a exit) >/dev/null 2>&1 && fail "esc 失敗時 exit 要非 0"
assert_eq "$(calls)" "pane send-keys w1:p1 esc" "esc 失敗後不送 /exit 與 enter"

# --- 傳話失敗時回傳 herdr 的錯誤 ---
echo agent_not_found > "$FX/prompt-err"
reset; err="$(OPSX_TEST_PROMPT_ERR="$FX/prompt-err" runtime_prompt r/card-a hi nowait 2>&1 >/dev/null)"; [ $? -ne 0 ] || fail "herdr 失敗時傳話要非 0"
case "$err" in *'"code":"agent_not_found"'*) ;; *) fail "要原樣交出 herdr 的錯誤：$err" ;; esac

# --- 模式決定帶不帶 --wait ---
verb "agent prompt card-a hi --wait" runtime_prompt r/card-a hi wait
assert_eq "$(argv_calls)" $'agent\x1fprompt\x1fcard-a\x1fhi\x1f--wait' "--wait 是最後一個獨立參數"
OPSX_TEST_COORDINATOR_UP=1 verb "agent prompt opsx-coordinator hi" runtime_prompt --agent opsx-coordinator hi nowait
verb "agent prompt fresh hi --wait" runtime_prompt r/fresh hi wait

# --- 模式不對就不送：rc 2、stderr 寫出收到的值、不叫 herdr ---
bad_mode() { # <stderr 要含的字> <模式參數…>
  local want="$1" err rc; shift
  reset; err="$(runtime_prompt r/card-a hi "$@" 2>&1 >/dev/null)"; rc=$?
  assert_eq "$rc" 2 "模式 [$*] 的 rc"
  case "$err" in *"$want"*) ;; *) fail "模式 [$*] 的錯誤要含 $want：$err" ;; esac
  assert_eq "$(calls)" "" "模式 [$*] 不叫 herdr"
}
bad_mode wait
bad_mode yes yes
bad_mode --wait --wait
bad_mode Wait Wait
bad_mode wait ""

# --- 回報協調者：走 --agent opsx-coordinator；送不出去記 coordinator.log、回 1 ---
reset; OPSX_TEST_COORDINATOR_UP=1 coordinator_say "[c] 停住" || fail "協調者在時要回 0"
assert_eq "$(calls)" "agent prompt opsx-coordinator [c] 停住" "coordinator_say 的 argv"
reset; coordinator_say "[c] 停住" && fail "協調者不在時要回 1"
assert_grep 'opsx-coordinator' "$OPSX_STATE_DIR/coordinator.log"
assert_grep 'agent_not_found' "$OPSX_STATE_DIR/coordinator.log"

# --- 開 agent ---
open_card() { # 在子 shell 開 r/card-a，印 rc 與交出的 pane / tab / workspace
  ( runtime_open r/card-a --kind claude --workspace-id w5 --cwd /wt --label card-a -- --model m
    printf 'rc=%s pane=%s tab=%s ws=%s\n' "$?" "${RUNTIME_PANE:-}" "${RUNTIME_TAB:-}" "${RUNTIME_WORKSPACE_ID:-}" ) 2>&1
}
export OPSX_TEST_BUSY_LEFT="$FX/busy-left"
busy() { # <busy 次數> <agent start 次數>
  echo "$1" > "$OPSX_TEST_BUSY_LEFT"; reset
  out="$(open_card)"
  case "$out" in *"rc=0 pane=w1:pE tab=w1:tB ws=w5"*) ;; *) fail "busy $1 次要成功並交出 pane 與 tab：$out" ;; esac
  assert_eq "$(grep -c '^agent start card-a --kind claude --pane w1:pE -- --model m$' "$OPSX_FAKE_LOG")" "$2" "busy $1 次的 agent start 次數"
  assert_eq "$(head -1 "$OPSX_FAKE_LOG")" "tab create --workspace w5 --cwd /wt --label card-a --no-focus" "先開 tab"
  assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
}
busy 0 1
busy 2 3
busy 5 6
echo 6 > "$OPSX_TEST_BUSY_LEFT"; reset
out="$(open_card)"
case "$out" in *rc=0*) fail "busy 6 次要失敗：$out" ;; esac
case "$out" in *r/card-a*agent_pane_busy*) ;; *) fail "失敗訊息要有卡片身分與 herdr 錯誤：$out" ;; esac
assert_eq "$(grep -c '^agent start ' "$OPSX_FAKE_LOG")" 6 "超過上限只試六次"
assert_eq "$(tail -1 "$OPSX_FAKE_LOG")" "tab close w1:tB" "失敗時收掉剛開的 tab"
unset OPSX_TEST_BUSY_LEFT

# trust 對話框：按 Yes 再等 idle
: > "$FX/not-ready"; reset
out="$(OPSX_TEST_NOT_READY_ONCE="$FX/not-ready" OPSX_TEST_PANE_TEXT='Yes, I trust this folder' open_card)"
case "$out" in *rc=0*) ;; *) fail "trust 對話框要成功：$out" ;; esac
grep -E '^(pane send-keys|agent wait)' "$OPSX_FAKE_LOG" > "$FX/trust"
assert_eq "$(cat "$FX/trust")" "pane send-keys w1:pE down enter
agent wait card-a --until idle --timeout 60000" "trust 之後的 argv"
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"

# 名字被占用：回 3，收 tab，HERDR_TAKEN_AT 是占用者的位置
reset
out="$(OPSX_TEST_START_FAIL=agent_name_taken open_card)"
case "$out" in *"rc=3 "*) ;; *) fail "名字被占用要回 3：$out" ;; esac
( OPSX_TEST_START_FAIL=agent_name_taken runtime_open r/card-a --kind claude --workspace-id w5 --cwd /wt --label card-a
  printf '%s' "$HERDR_TAKEN_AT" ) > "$FX/taken"
case "$(cat "$FX/taken")" in *pane_id=w9:p1*workspace_id=w9*tab_id=w9:t1*) ;; *) fail "HERDR_TAKEN_AT：$(cat "$FX/taken")" ;; esac
assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"

# 名字只從卡片身分推，不讀 dispatch.json（重派時舊條目的 herdr_name 不算）
reset; ( runtime_open r/renamed --kind claude --workspace-id w5 --cwd /wt --label renamed ) >/dev/null 2>&1 || fail "開 r/renamed rc"
assert_grep '^agent start renamed --kind claude --pane w1:pE --$' "$OPSX_FAKE_LOG"
reset; ( runtime_open r/@feat-z --kind codex --workspace-id w5 --cwd /wt --label feat-z ) >/dev/null 2>&1 || fail "開 r/@feat-z rc"
assert_grep '^agent start feat-z --kind codex --pane w1:pE --$' "$OPSX_FAKE_LOG"
# --agent：協調者
reset; ( runtime_open --agent opsx-coordinator --kind claude --workspace-id w5 --cwd /top --label opsx-coordinator -- --settings s ) >/dev/null 2>&1 || fail "開協調者 rc"
assert_eq "$(calls)" "tab create --workspace w5 --cwd /top --label opsx-coordinator --no-focus
agent start opsx-coordinator --kind claude --pane w1:pE -- --settings s" "開協調者的 argv"
rm -f "$OPSX_FAKE_LOG.coordinator-up"

# workspace：label 用 list 換 id；create 開新的；label 不存在列出現有的、不開 tab
reset; out="$( ( runtime_open r/card-a --kind claude --workspace-label acmecorp-ai --cwd /wt --label card-a; printf 'ws=%s' "$RUNTIME_WORKSPACE_ID" ) 2>&1)"
case "$out" in *ws=w1) ;; *) fail "label 換 id：$out" ;; esac
assert_eq "$(head -2 "$OPSX_FAKE_LOG")" "workspace list
tab create --workspace w1 --cwd /wt --label card-a --no-focus" "label 的 argv"
reset; out="$( ( runtime_open r/card-a --kind claude --workspace-create scam-guard /top --cwd /wt --label card-a; printf 'ws=%s' "$RUNTIME_WORKSPACE_ID" ) 2>&1)"
case "$out" in *ws=w9) ;; *) fail "create 交出新 id：$out" ;; esac
assert_eq "$(head -2 "$OPSX_FAKE_LOG")" "workspace create --label scam-guard --cwd /top --no-focus
tab create --workspace w9 --cwd /wt --label card-a --no-focus" "create 的 argv"
# --on-workspace-created：新 id 建好就呼叫，在 tab create 之前；它失敗就結束、不開 tab
on_created() { printf 'created %s %s\n' "$1" "$2" >> "$OPSX_FAKE_LOG"; }
on_created_fail() { return 1; }
reset; ( runtime_open r/card-a --kind claude --workspace-create scam-guard /top --on-workspace-created on_created --cwd /wt --label card-a ) >/dev/null 2>&1 || fail "--on-workspace-created rc"
assert_eq "$(head -3 "$OPSX_FAKE_LOG")" "workspace create --label scam-guard --cwd /top --no-focus
created scam-guard w9
tab create --workspace w9 --cwd /wt --label card-a --no-focus" "回呼在 workspace 建好之後、tab create 之前"
reset; out="$( (runtime_open r/card-a --kind claude --workspace-create scam-guard /top --on-workspace-created on_created_fail --cwd /wt --label card-a) 2>&1)"; [ $? -ne 0 ] || fail "回呼失敗要非 0"
case "$out" in *on_created_fail*) ;; *) fail "回呼失敗的訊息要有函式名：$out" ;; esac
assert_not_grep '^tab create' "$OPSX_FAKE_LOG"
reset; (runtime_open r/card-a --kind claude --workspace-id w5 --on-workspace-created on_created --cwd /wt --label card-a) >/dev/null 2>&1 && fail "--on-workspace-created 只配 --workspace-create"
assert_eq "$(calls)" "" "--on-workspace-created 配錯不叫 herdr"
reset; out="$( (runtime_open r/card-a --kind claude --workspace-label nope --cwd /wt --label card-a) 2>&1)"; [ $? -ne 0 ] || fail "沒有的 label 要非 0"
case "$out" in *nope*acmecorp-ai*) ;; *) fail "要列出現有 label：$out" ;; esac
assert_not_grep '^tab create' "$OPSX_FAKE_LOG"
# 兩個 workspace 旗標都給、都沒給：非 0、不叫 herdr
reset; (runtime_open r/card-a --kind claude --workspace-id w5 --workspace-label x --cwd /wt --label card-a) >/dev/null 2>&1 && fail "兩個 workspace 旗標要非 0"
(runtime_open r/card-a --kind claude --cwd /wt --label card-a) >/dev/null 2>&1 && fail "沒有 workspace 旗標要非 0"
assert_eq "$(calls)" "" "旗標不對不叫 herdr"
# 收值的旗標缺值：非 0、說出旗標名、不叫 herdr、不卡住（在新的 bash 裡跑，5 秒沒結束就算卡住）
open_missing() { # <runtime_open 的參數…>
  perl -e 'alarm 5; exec @ARGV' bash -c 'source "$OPSX_ROOT/bin/lib/common.sh"; runtime_open "$@"' _ "$@" 2>&1
}
reset; out="$(open_missing r/x --kind claude --workspace-id w1 --cwd /x --label)"; rc=$?
[ "$rc" -ne 0 ] && [ "$rc" -ne 142 ] || fail "--label 缺值要非 0 且不卡住（rc $rc）：$out"
case "$out" in *--label*) ;; *) fail "缺值訊息要有旗標名：$out" ;; esac
reset; out="$(open_missing r/x --kind claude --cwd /x --label x --workspace-create scam-guard)"; rc=$?
[ "$rc" -ne 0 ] && [ "$rc" -ne 142 ] || fail "--workspace-create 少一個值要非 0 且不卡住（rc $rc）：$out"
case "$out" in *--workspace-create*) ;; *) fail "缺值訊息要有 --workspace-create：$out" ;; esac
assert_eq "$(calls)" "" "旗標缺值不叫 herdr"
# tab create 沒回 tab id：非 0、不起 agent
reset; out="$( (OPSX_TEST_TAB_NO_TAB=1 runtime_open r/card-a --kind claude --workspace-id w5 --cwd /wt --label card-a) 2>&1)"; [ $? -ne 0 ] || fail "沒有 tab id 要非 0"
case "$out" in *r/card-a*) ;; *) fail "訊息要有卡片身分：$out" ;; esac
assert_not_grep '^agent start' "$OPSX_FAKE_LOG"

echo ok
