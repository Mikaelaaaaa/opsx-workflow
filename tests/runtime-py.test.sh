#!/usr/bin/env bash
# bin/lib/runtime.py：只產生 herdr argv、不執行；同一張表同時驅動 runtime.sh（看 $OPSX_FAKE_LOG）與 runtime.py（看回傳值），逐列比對。
# 驗收：openspec/changes/runtime-module/subs/runtime-py/specs/agent-runtime/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
use_herdr_argv_log
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_TEST_AGENT_GET_RAW='{}' OPSX_TEST_COORDINATOR_UP=1
source "$OPSX_ROOT/bin/lib/common.sh"
source "$OPSX_ROOT/bin/lib/python.sh"
opsx_python_load || fail "$OPSX_PY_ERR"
J="$OPSX_STATE_DIR/dispatch.json"
calls() { cat "$OPSX_FAKE_LOG"; }
argv_calls() { cat "$OPSX_FAKE_LOG.sep"; }
reset() { : > "$OPSX_FAKE_LOG"; : > "$OPSX_FAKE_LOG.sep"; }

cat > "$J" <<'EOF'
{"r/card-a": {"pane": "w1:p1", "tab": "w1:t1"},
 "r/card-b": {"pane": "w1:p2", "herdr_name": "card-b"},
 "r/child": {"pane": "w1:p3", "herdr_name": "feat-x", "feature": "feat-x", "via": "@feat-x"},
 "r/@feat-x": {"pane": "w1:p3"},
 "r/renamed": {"pane": "w1:p4", "herdr_name": "other"},
 "r/opsx-coordinator": {"pane": "w9:p9", "herdr_name": "zzz"}}
EOF

py() { # <python 運算式；rt 是 runtime 模組、D 是 dispatch.json 路徑> → 印 argv 去掉開頭的 herdr，參數間用 \x1f 分隔（跟 $OPSX_FAKE_LOG.sep 同格式）；raise 時非 0、訊息在 stderr
  OPSX_EXPR="$1" OPSX_D="$J" OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import runtime as rt
D = os.environ["OPSX_D"]
argv = eval(os.environ["OPSX_EXPR"])
assert argv[0] == "herdr", argv
print("\x1f".join(argv[1:]))' < /dev/null
}

# 一列：期望 argv | bash 版呼叫 | python 版呼叫。bash 呼叫的參數不含空白（照空白切）。
# 期望 argv 跟假 herdr 的單行記錄比；bash 與 python 之間逐個參數比（分得出參數邊界）。
# python 版之後 herdr 的記錄要是空的：python 版不執行 herdr。
table() { # <表格檔>
  local want bcall pcall words bash_argv
  while IFS='|' read -r want bcall pcall; do
    [ -n "$want" ] || continue
    read -r -a words <<< "$bcall"
    reset; "${words[@]}" >/dev/null < /dev/null || fail "bash rc：$bcall"
    assert_eq "$(calls)" "$want" "bash：$bcall"
    bash_argv="$(argv_calls)"
    reset; assert_eq "$(py "$pcall")" "$bash_argv" "python 與 bash 逐個參數相同：$pcall"
    assert_eq "$(calls)" "" "python 版不叫 herdr：$pcall"
  done < "$1"
}

# --- 動詞對應的 herdr argv（runtime-sh spec 兩張 Examples 表，不含送 /exit） ---
cat > "$FX/verbs" <<'EOF'
agent prompt card-a hi|runtime_prompt r/card-a hi|rt.prompt("hi", card="r/card-a", dispatch=D)
pane read w1:p1|runtime_read r/card-a|rt.read(card="r/card-a", dispatch=D)
agent read w1:p1 --lines 10 --format text|runtime_read r/card-a --lines 10|rt.read(card="r/card-a", dispatch=D, lines=10)
agent get card-a|runtime_get r/card-a|rt.get(card="r/card-a", dispatch=D)
agent wait card-a|runtime_wait r/card-a|rt.wait(card="r/card-a", dispatch=D)
agent wait card-a --until working|runtime_wait r/card-a --until working|rt.wait(card="r/card-a", dispatch=D, until="working")
agent focus card-a|runtime_focus r/card-a|rt.focus(card="r/card-a", dispatch=D)
pane close w1:p1|runtime_close r/card-a pane|rt.close("pane", card="r/card-a", dispatch=D)
tab close w1:t1|runtime_close r/card-a tab|rt.close("tab", card="r/card-a", dispatch=D)
agent wait card-a --until idle --timeout 60000|runtime_wait r/card-a --until idle --timeout 60000|rt.wait(card="r/card-a", dispatch=D, until="idle", timeout=60000)
agent list|runtime_list|rt.list_agents()
notification show t --body b|runtime_notify t b|rt.notify("t", "b")
notification show t --body b --sound request|runtime_notify t b --sound request|rt.notify("t", "b", sound="request")
EOF
table "$FX/verbs"

# --- 查表規則跟 runtime_target 相同：herdr_name、@feature、沒有條目、--agent 不讀 dispatch.json ---
cat > "$FX/lookup" <<'EOF'
agent prompt card-b hi|runtime_prompt r/card-b hi|rt.prompt("hi", card="r/card-b", dispatch=D)
pane read w1:p2|runtime_read r/card-b|rt.read(card="r/card-b", dispatch=D)
agent prompt feat-x hi|runtime_prompt r/child hi|rt.prompt("hi", card="r/child", dispatch=D)
pane read w1:p3|runtime_read r/child|rt.read(card="r/child", dispatch=D)
agent prompt feat-x hi|runtime_prompt r/@feat-x hi|rt.prompt("hi", card="r/@feat-x", dispatch=D)
pane read w1:p3|runtime_read r/@feat-x|rt.read(card="r/@feat-x", dispatch=D)
agent prompt other hi|runtime_prompt r/renamed hi|rt.prompt("hi", card="r/renamed", dispatch=D)
pane read w1:p4|runtime_read r/renamed|rt.read(card="r/renamed", dispatch=D)
agent prompt fresh hi|runtime_prompt r/fresh hi|rt.prompt("hi", card="r/fresh", dispatch=D)
agent prompt opsx-coordinator hi|runtime_prompt --agent opsx-coordinator hi|rt.prompt("hi", agent="opsx-coordinator")
agent get opsx-coordinator|runtime_get --agent opsx-coordinator|rt.get(agent="opsx-coordinator")
EOF
table "$FX/lookup"
reset; runtime_prompt --agent opsx-coordinator "[x] 停住" >/dev/null || fail "含空白的一行 bash rc"
assert_eq "$(argv_calls)" $'agent\x1fprompt\x1fopsx-coordinator\x1f[x] 停住' "bash：含空白的一行原樣是一個參數"
reset; assert_eq "$(py 'rt.prompt("[x] 停住", agent="opsx-coordinator")')" $'agent\x1fprompt\x1fopsx-coordinator\x1f[x] 停住' "python：含空白的一行原樣是一個參數"
reset; assert_eq "$(py 'rt.notify("[r/x] 併入", "a b 併進 x")')" $'notification\x1fshow\x1f[r/x] 併入\x1f--body\x1fa b 併進 x' "python：通知的標題與內文各是一個參數"

# --agent 不讀 dispatch.json：檔案是壞的 JSON 也照樣產生 argv
cp "$J" "$J.good"; printf '{"opsx-coordinator": {"herdr_name": "zzz"}' > "$J"
reset; assert_eq "$(py 'rt.prompt("hi", agent="opsx-coordinator", dispatch=D)')" $'agent\x1fprompt\x1fopsx-coordinator\x1fhi' "python：--agent 在壞的 dispatch.json 下照樣產生 argv"
mv "$J.good" "$J"

# dispatch.json 不存在：名字照樣推得出來，要 pane 或 tab 的動詞 raise
mv "$J" "$J.bak"
cat > "$FX/nofile" <<'EOF'
agent prompt feat-y hi|runtime_prompt r/@feat-y hi|rt.prompt("hi", card="r/@feat-y", dispatch=D)
EOF
table "$FX/nofile"
reset; err="$(py 'rt.close("tab", card="r/card-a", dispatch=D)' 2>&1 >/dev/null)" && fail "沒有 dispatch.json 時關 tab 要 raise"
case "$err" in *MissingHandle*r/card-a*) ;; *) fail "沒有 dispatch.json 的錯誤要有卡片身分：$err" ;; esac
mv "$J.bak" "$J"

# --- 反例：raise、訊息有對象、herdr 沒被呼叫 ---
raises() { # <期望 stderr 含的字> <python 運算式>
  local err
  err="$(py "$2" 2>&1 >/dev/null)" && fail "要 raise：$2"
  case "$err" in *"$1"*) ;; *) fail "錯誤訊息要含 $1：$err" ;; esac
}
reset
raises 'MissingHandle: runtime: r/fresh' 'rt.read(card="r/fresh", dispatch=D)'
raises 'MissingHandle: runtime: r/card-b' 'rt.close("tab", card="r/card-b", dispatch=D)'
raises 'MissingHandle: runtime: opsx-coordinator' 'rt.read(agent="opsx-coordinator")'
raises 'ValueError' 'rt.prompt("hi", card="card-a", dispatch=D)'
raises 'ValueError' 'rt.prompt("hi", card="r/card-a", agent="x", dispatch=D)'
raises 'ValueError' 'rt.prompt("hi")'
raises 'ValueError' 'rt.prompt("hi", agent="")'
raises 'ValueError' 'rt.prompt("hi", card="r/card-a")'
raises 'ValueError: runtime: r/card-a' 'rt.close("exit", card="r/card-a", dispatch=D)'
assert_eq "$(calls)" "" "raise 的動詞不叫 herdr"
echo ok
