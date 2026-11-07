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
printf '/usr/bin\n' > "$P"
opsx collect --root "$FX" > /dev/null 2> "$FX/err" && fail "python 指到目錄時 collect 要失敗"
assert_grep "/usr/bin" "$FX/err"; assert_grep "opsx init --global" "$FX/err"
rm -f "$P"; RI="$(mk_repo init-nopy)"
(cd "$RI" && opsx init) > /dev/null 2> "$FX/err" && fail "缺 python 檔時 repo 層 opsx init 要失敗"
assert_grep "$P" "$FX/err"; assert_grep "opsx init --global" "$FX/err"
assert_no_file "$RI/openspec"

# ---------- python 在但跑不起來：授權閘門要 deny，不能因為 hook 非 0 結束而放行 ----------
printf '/usr/bin/false\n' > "$P"
out="$(bash_hook "$R" 'glab mr create -F d.md')"; assert_eq "$(decision "$out")" deny "python 跑不起來時要授權的指令要 deny"
reason "$out" | grep -q 'python 執行失敗' || fail "deny 理由要說 python 執行失敗，不是要授權：$(reason "$out")"
out="$(bash_hook "$R" 'pnpm test')"; assert_eq "$(decision "$out")" allow "python 跑不起來時不需授權的指令跟 python 正常時一樣"

# ---------- 授權閘門遇到缺檔就擋，不放行 ----------
rm -f "$P"
out="$(bash_hook "$R" 'pnpm test')"; assert_eq "$(decision "$out")" deny "缺 python 檔時卡上的 Bash 要 deny"
reason "$out" | grep -q 'opsx init --global' || fail "deny 理由要給修法：$(reason "$out")"
out="$(bash_hook "$FX" 'pnpm test')"; assert_eq "$(decision "$out")" allow "不在卡上不管"
out="$(bash_hook "$R" 'opsx init --global')"; assert_eq "$(decision "$out")" allow "修法那一條要放行"
for m in interactive stopped; do
  printf '{"r/c1":{"mode":"%s","grants":[]}}' "$m" > "$OPSX_STATE_DIR/dispatch.json"
  out="$(bash_hook "$R" 'git push')"; assert_eq "$(decision "$out")" allow "缺 python 檔時 $m 卡不歸閘門管"
done
printf '{"r/c1":{"mode":"drive","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(bash_hook "$R" 'pnpm test')"; assert_eq "$(decision "$out")" deny "缺 python 檔時 drive 卡要 deny"
printf '{"r/c1":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
R2="$(mk_repo r2)"; git -C "$R2" checkout -q -b feat/foo/mikaela
out="$(bash_hook "$R2" 'pnpm test')"; assert_eq "$(decision "$out")" allow "三段式 branch 但沒有卡：不管"
mk_change "$R" c2
out="$(bash_hook "$R" 'pnpm test')"; assert_eq "$(decision "$out")" allow "有卡但沒派出去：不管"
git -C "$R" checkout -q feat/c1/mikaela
printf '%s\n' "$REAL" > "$P"

# ---------- dispatch.json 壞掉：檔案裡有這張卡就擋，沒有就不管 ----------
printf '{"r/c1":{"mode":"autopilot",' > "$OPSX_STATE_DIR/dispatch.json"
out="$(bash_hook "$R" 'pnpm test')"; assert_eq "$(decision "$out")" deny "dispatch.json 壞掉時派出去的卡要 deny"
reason "$out" | grep -qF "$OPSX_STATE_DIR/dispatch.json" || fail "deny 理由要寫出 dispatch.json 的路徑：$(reason "$out")"
printf '{"r/other":{"mode":"autopilot",' > "$OPSX_STATE_DIR/dispatch.json"
out="$(bash_hook "$R" 'git push')"; assert_eq "$(decision "$out")" allow "dispatch.json 壞掉、裡面沒有這張卡：不管"
printf '{"r/c1":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
chmod 000 "$OPSX_STATE_DIR/dispatch.json"
out="$(bash_hook "$R" 'git push')"; chmod 644 "$OPSX_STATE_DIR/dispatch.json"
assert_eq "$(decision "$out")" deny "dispatch.json 讀不了時要 deny，不能因為比對不到 key 就放行"
reason "$out" | grep -qF "$OPSX_STATE_DIR/dispatch.json" || fail "deny 理由要寫出 dispatch.json 的路徑：$(reason "$out")"

# ---------- 產品碼裡不能再有直接叫 python3 的地方（上面的假 python3 只走得到幾條路） ----------
hits="$(grep -rnwa 'python3' "$OPSX_ROOT/bin" "$OPSX_ROOT/hooks" | grep -avE ':[0-9]+:[[:space:]]*#' | grep -avF 'Bash(python3:*)' \
  | grep -avE 'bin/lib/init\.sh:[0-9]+:.*(sys\.version_info|python3 --version|print\(sys\.executable\))')"
assert_eq "$hits" "" "bin/ hooks/ 還有直接叫 python3 的地方"
echo ok
