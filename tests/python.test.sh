#!/usr/bin/env bash
# opsx 與 hooks 只用 $OPSX_STATE_DIR/python，不用 PATH 上的 python3；缺檔或路徑壞了就報錯，不退回。
# 驗收：specs/opsx-python/spec.md（collect-perf）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo r)"; mk_change "$R" c1
printf '{"r/c1":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
bash_hook() { # <cwd> <command> → grant-gate 的 stdout
  jq -n --arg cwd "$1" --arg c "$2" '{cwd:$cwd,tool_name:"Bash",tool_input:{command:$c},hook_event_name:"PreToolUse"}' \
    | bash "$OPSX_ROOT/hooks/opsx-grant-gate.sh" 2>/dev/null; true
}
decision() { [ -z "$1" ] && { echo allow; return; }; printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision'; }
reason() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }

# ---------- PATH 上的 python3 不會被叫到 ----------
mkdir -p "$FX/fakepy"; : > "$FX/py.log"
printf '#!/bin/sh\necho "$@" >> "%s/py.log"; exit 97\n' "$FX" > "$FX/fakepy/python3"; chmod +x "$FX/fakepy/python3"
OLDPATH="$PATH"; export PATH="$FX/fakepy:$PATH"
out="$(opsx collect --root "$FX")" || fail "collect 在假 python3 下失敗：$out"
case "$out" in *'"cards"'*) ;; *) fail "collect 沒輸出 JSON：$out" ;; esac
( cd "$R" && opsx status apply 1/2 x --change c1 >/dev/null ) || fail "status 寫入在假 python3 下失敗"
assert_eq "$(cd "$R" && opsx status --show --change c1 | cut -d' ' -f1-2)" "apply 1/2"
out="$(bash_hook "$R" 'glab mr create -F d.md')"; assert_eq "$(decision "$out")" deny "autopilot 沒授權的 mr 要 deny"
out="$(bash_hook "$R" 'pnpm test')"; assert_eq "$(decision "$out")" allow
assert_eq "$(cat "$FX/py.log")" "" "PATH 上的 python3 被叫到了"
export PATH="$OLDPATH"

# ---------- 找不到 python 就報錯，不退回 ----------
P="$OPSX_STATE_DIR/python"; REAL="$(cat "$P")"
rm -f "$P"
opsx collect --root "$FX" > "$FX/out" 2> "$FX/err"; rc=$?
[ "$rc" -ne 0 ] || fail "缺 python 檔時 collect 要失敗"
assert_eq "$(cat "$FX/out")" "" "失敗時 stdout 不該有 JSON"
assert_grep "$P" "$FX/err"; assert_grep "opsx init --global" "$FX/err"
: > "$P"
opsx collect --root "$FX" > /dev/null 2> "$FX/err" && fail "空的 python 檔時 collect 要失敗"
assert_grep "$P" "$FX/err"; assert_grep "opsx init --global" "$FX/err"
printf '/nonexistent/py3\n' > "$P"
opsx collect --root "$FX" > /dev/null 2> "$FX/err" && fail "python 指到不存在的路徑時 collect 要失敗"
assert_grep "/nonexistent/py3" "$FX/err"; assert_grep "opsx init --global" "$FX/err"

# ---------- 授權閘門遇到缺檔就擋，不放行 ----------
rm -f "$P"
out="$(bash_hook "$R" 'pnpm test')"; assert_eq "$(decision "$out")" deny "缺 python 檔時卡上的 Bash 要 deny"
reason "$out" | grep -q 'opsx init --global' || fail "deny 理由要給修法：$(reason "$out")"
out="$(bash_hook "$FX" 'pnpm test')"; assert_eq "$(decision "$out")" allow "不在卡上不管"
printf '%s\n' "$REAL" > "$P"
echo ok
