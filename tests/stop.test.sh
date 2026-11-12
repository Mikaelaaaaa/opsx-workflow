#!/usr/bin/env bash
# opsx stop 只 kill 確實是這張卡 drive 的 pid。specs/opsx-drive/spec.md「drive 自己登記」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr ps
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
J="$OPSX_STATE_DIR/dispatch.json"
KEY=Acmecorp-CS/retry-backoff

R="$(mk_repo Acmecorp-CS)"
mkdir -p "$R/openspec/changes/retry-backoff"
printf 'schema: opsx\nkind: bug-fix\n' > "$R/openspec/changes/retry-backoff/.openspec.yaml"
cd "$R"

# 行程不掛在測試 shell 底下，被 kill 後才不會留成 zombie（zombie 對 kill -0 還是成功）；fd 全部導走，不握著 run.sh 的 pipe
spawn() { ( sleep 300 < /dev/null > /dev/null 2>&1 & echo $! > "$FX/spawned.pid" ); cat "$FX/spawned.pid"; }
put_pid() { # <pid>：dispatch.json 寫一筆 autopilot 單卡，drive_pid 是給的 pid
  printf '{"%s":{"pane":"w1:pE","agent":"claude","model":"claude-sonnet-5-5","mode":"autopilot","drive_pid":%s}}' "$KEY" "$1" > "$J"
}
alive() { kill -0 "$1" 2>/dev/null; }
dies() { local n=0; while alive "$1"; do n=$((n+1)); [ $n -lt 30 ] || return 1; sleep 0.1; done; }
assert_stopped() { # 條目標 stopped、drive_pid 清成 null
  python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))[sys.argv[2]];assert e["mode"]=="stopped" and e["drive_pid"] is None,e' "$J" "$KEY" || fail "條目要 stopped 且 drive_pid 是 null"
}

# --- 正例：pid 是這張卡的 drive，被 kill ---
PID="$(spawn)"; trap 'kill "$PID" 2>/dev/null; rm -rf "$FX"' EXIT
put_pid "$PID"; export OPSX_TEST_PS_CMD="bash /x/bin/opsx drive retry-backoff --repo $R"
out="$(opsx stop retry-backoff 2>&1)"; assert_eq "$?" 0 "stop: $out"
dies "$PID" || fail "是 drive 的 pid 要被 kill：$out"
case "$out" in *"已 kill"*) ;; *) fail "訊息要說已 kill: $out" ;; esac
assert_stopped

# --- 正例：手動跑的 opsx drive <slug> 沒有 --repo，也是這張卡的 drive ---
PID="$(spawn)"
put_pid "$PID"; export OPSX_TEST_PS_CMD="/bin/bash /home/u/.local/bin/opsx drive retry-backoff"
out="$(opsx stop retry-backoff 2>&1)"; assert_eq "$?" 0 "stop: $out"
dies "$PID" || fail "沒有 --repo 的手動 drive 也要被 kill：$out"
assert_stopped

# --- 反例：pid 被別的行程重用，不 kill，印 pid 與 command，其餘照做 ---
PID="$(spawn)"
put_pid "$PID"; export OPSX_TEST_PS_CMD="/usr/bin/vim notes.md"; : > "$OPSX_FAKE_LOG"
out="$(opsx stop retry-backoff 2>&1)"; assert_eq "$?" 0 "stop: $out"
alive "$PID" || fail "不是 drive 的 pid 不能被 kill：$out"
case "$out" in *"$PID"*vim*) ;; *) fail "訊息要含 pid 與 vim: $out" ;; esac
assert_stopped
assert_grep '^pane close w1:pE' "$OPSX_FAKE_LOG"

# --- 邊界：slug 是別張卡 slug 的前綴或延伸，都不是這張卡的 drive ---
for cmd in "bash /x/bin/opsx drive retry --repo $R" "bash /x/bin/opsx drive retry-backoff-2 --repo $R"; do
  put_pid "$PID"; export OPSX_TEST_PS_CMD="$cmd"
  out="$(opsx stop retry-backoff 2>&1)"; assert_eq "$?" 0 "stop: $out"
  alive "$PID" || fail "別張卡的 drive command 不能被當成這張的：$cmd"
done
kill "$PID" 2>/dev/null
