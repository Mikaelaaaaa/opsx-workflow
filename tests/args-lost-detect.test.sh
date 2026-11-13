#!/usr/bin/env bash
# 啟動參數遺失的判定：argv 有沒有這張卡該有的 --settings 檔；認不得的輸入 raise，不退回猜。
# 驗收：specs/args-lost-guard/spec.md（判定啟動參數遺失）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

S=/state/settings/repo-card-autopilot.json

lost() { # <argv 元素…> → args_lost 的結果；raise 時印 ERR:<訊息>
  OPSX_LIB="$OPSX_ROOT/bin/lib" OPSX_S="$S" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import argslost
try:
    print(argslost.args_lost(sys.argv[1:], os.environ["OPSX_S"]))
except ValueError as e:
    print("ERR:" + str(e))' "$@"
}

assert_eq "$(lost claude --model m --settings "$S")" False "帶了該卡的 settings"
assert_eq "$(lost /usr/local/bin/claude --settings="$S")" False "等號形式、argv[0] 是完整路徑"
assert_eq "$(lost claude --model m)" True "沒帶 settings"
assert_eq "$(lost claude --settings /state/settings/other.json)" True "帶了別的檔"
assert_eq "$(lost claude --settings "$S.bak")" True "路徑只是前綴相同不算"
assert_eq "$(lost claude --settings-x "$S")" True "旗標名只是前綴相同不算"

V=/Users/me/.local/share/claude/versions/2.1.322
assert_eq "$(lost "$V" --model m --settings "$S")" False "argv[0] 是 claude 的版本執行檔、帶了該卡的 settings"
assert_eq "$(lost "$V" --model m)" True "argv[0] 是 claude 的版本執行檔、沒帶 settings"
out="$(lost /x/other/versions/1 --settings "$S")"; case "$out" in ERR:*argv\[0\]*/x/other/versions/1*) ;; *) fail "不是 claude 的版本目錄要點名欄位與值：$out" ;; esac
out="$(lost 2.1.322 --settings "$S")"; case "$out" in ERR:*argv\[0\]*2.1.322*) ;; *) fail "單獨的版本號檔名不算 claude：$out" ;; esac

out="$(lost)"; case "$out" in ERR:*argv*) ;; *) fail "空 argv 要 raise 並點名 argv：$out" ;; esac
out="$(lost bash --settings "$S")"; case "$out" in ERR:*argv\[0\]*bash*) ;; *) fail "argv[0] 不是 claude 要點名欄位與值：$out" ;; esac
out="$(lost claude --settings)"; case "$out" in ERR:*--settings*) ;; *) fail "--settings 無值要點名：$out" ;; esac

# settings_path 非絕對路徑
rel="$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import argslost
try:
    argslost.args_lost(["claude"], "relative/x.json")
except ValueError as e:
    print("ERR:" + str(e))')"
case "$rel" in ERR:*settings_path*relative/x.json*) ;; *) fail "相對路徑要點名 settings_path 與值：$rel" ;; esac

# argv 不是 list、含非 str
bad="$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import argslost
for v in ("claude --settings x", ["claude", 3]):
    try:
        argslost.args_lost(v, "/a.json")
    except ValueError as e:
        print("ERR:" + str(e))')"
[ "$(printf '%s\n' "$bad" | grep -c '^ERR:')" = 2 ] || fail "非 list 與含非 str 都要 raise：$bad"

# CLI：stdin 一行 ps 輸出，退出碼 0 有帶 / 1 遺失 / 2 認不得
cli() { printf '%s\n' "$1" | OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I "$OPSX_ROOT/bin/lib/argslost.py" "$S" 2>"$FX/cli.err"; }
cli "claude --model m --settings $S"; assert_eq "$?" 0 "CLI 有帶"
cli "claude --model m"; assert_eq "$?" 1 "CLI 遺失"
cli "$V --model m --settings $S"; assert_eq "$?" 0 "CLI 版本執行檔有帶"
cli "$V --model m"; assert_eq "$?" 1 "CLI 版本執行檔遺失"
cli "node server.js"; assert_eq "$?" 2 "CLI 認不得"
assert_grep "argv\[0\]" "$FX/cli.err"
cli ""; assert_eq "$?" 2 "CLI 空輸入"
cli "claude --settings 'unclosed"; assert_eq "$?" 2 "CLI 引號沒收"
assert_grep "unclosed" "$FX/cli.err"
# --settings 出現多次：任何一個等於該卡的檔就算有帶（寧可不放行，不要把健康的 agent 判成遺失）
assert_eq "$(lost claude --settings /state/settings/other.json --model m --settings "$S")" False "第二個 --settings 才是該卡的"
assert_eq "$(lost claude --settings "$S" --settings /state/settings/other.json)" False "第一個是該卡的"
assert_eq "$(lost claude --settings /a.json --settings /b.json)" True "兩個都不是"

# settings_path 含空白：ps 輸出切不回 argv，會把健康的 agent 判成遺失，所以 raise
sp="$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import argslost
try:
    argslost.args_lost(["claude", "--settings", "/a", "b/s.json"], "/a b/s.json")
except ValueError as e:
    print("ERR:" + str(e))')"
case "$sp" in ERR:*settings_path*"/a b/s.json"*) ;; *) fail "含空白的 settings_path 要 raise 並點名欄位與值：$sp" ;; esac
printf '%s\n' "claude --settings /a b/s.json" | OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I "$OPSX_ROOT/bin/lib/argslost.py" "/a b/s.json" 2>"$FX/cli.err"
assert_eq "$?" 2 "CLI：含空白的 settings_path 認不得"

# CLI --process-info：stdin 是 herdr pane process-info 的 JSON，取前景唯一的 claude 判定；退出碼同上
# 驗收：openspec/changes/agent-20261113-1355/specs/args-lost-guard/spec.md（判遺失前用 pane 的 claude 確認）
SAMPLES="$OPSX_ROOT/tests/fakes/herdr-samples"
PS_SETTINGS=/Users/dev/.local/state/opsx/settings/opsx-workflow-relaunch-auto-autopilot.json
pi_cli() { # <settings_path> < process-info JSON
  OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I "$OPSX_ROOT/bin/lib/argslost.py" --process-info "$1" 2>"$FX/cli.err"
}
pi_cli "$PS_SETTINGS" < "$SAMPLES/process-info-claude.json"; assert_eq "$?" 0 "process-info：pane 的 claude 帶了該卡的 settings"
pi_cli "$S" < "$SAMPLES/process-info-claude.json"; assert_eq "$?" 1 "process-info：pane 的 claude 帶的是別張卡的 settings"
pi_cli "$S" < "$SAMPLES/process-info-shell.json"; assert_eq "$?" 2 "process-info：前景沒有 claude"
assert_grep "前景沒有 claude" "$FX/cli.err"
jq -c '.result.process_info.foreground_processes += [.result.process_info.foreground_processes[1]]' "$SAMPLES/process-info-claude.json" > "$FX/pi-two.json"
pi_cli "$PS_SETTINGS" < "$FX/pi-two.json"; assert_eq "$?" 2 "process-info：前景有兩個 claude"
assert_grep "2 個 claude" "$FX/cli.err"
printf '{"result":{}}' | pi_cli "$S"; assert_eq "$?" 2 "process-info：形狀不對"
assert_grep "foreground_processes" "$FX/cli.err"
printf 'not json' | pi_cli "$S"; assert_eq "$?" 2 "process-info：不是 JSON"
assert_grep "JSON" "$FX/cli.err"

# claude_argv 認不得時 raise ValueError，coordinate 照舊接得住
cv="$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import argslost
try:
    argslost.claude_argv({"result": {"process_info": {"foreground_processes": []}}})
except ValueError as e:
    print("ERR:" + str(e))')"
case "$cv" in ERR:*前景沒有\ claude*) ;; *) fail "前景空的要 raise ValueError：$cv" ;; esac
echo ok
