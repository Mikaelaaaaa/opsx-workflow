#!/usr/bin/env bash
# opsx relaunch：用假 herdr 驗前置檢查、送鍵順序、標記、drive 與失敗回報。specs/opsx-relaunch/spec.md（主殼 relaunch-cmd D1–D5）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr ps
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_DRIVE_MAX=0   # 重開後起的 drive 登記完就結束，不在 fixture 上跑迴圈
export OPSX_DISPATCH_RETRY_SLEEP=0
SID=329c1d2a-42f9-4e58-a57d-c55ea78ac173
J="$OPSX_STATE_DIR/dispatch.json"

mk_agents() { # <file> <pane> <status> [session id]：agent list fixture，只放一個 agent；沒給 session id 就不帶 agent_session
  local session=""
  [ -z "${4:-}" ] || session='"agent_session": {"agent": "claude", "kind": "id", "source": "herdr:claude", "value": "'"$4"'"},'
  printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude",%s"agent_status":"%s","pane_id":"%s","tab_id":"w1:tB","workspace_id":"w1"}],"type":"agent_list"}}\n' "$session" "$3" "$2" > "$1"
}
put_entry() { # <key> <json>：dispatch.json 寫一筆
  python3 -I -c 'import json,sys;p=sys.argv[1];
try: d=json.load(open(p))
except FileNotFoundError: d={}
d[sys.argv[2]]=json.loads(sys.argv[3]);json.dump(d,open(p,"w"))' "$J" "$1" "$2"
}
no_keys_sent() { # <訊息>：herdr 沒收到任何送鍵或啟動
  ! grep -qE '^(pane send-keys|pane send-text|agent start|agent prompt)' "$OPSX_FAKE_LOG" || fail "$1：$(cat "$OPSX_FAKE_LOG")"
}

R="$(mk_repo Acmecorp-CS)"
mkdir -p "$R/openspec/changes/retry-backoff"
printf 'schema: opsx\nkind: bug-fix\n' > "$R/openspec/changes/retry-backoff/.openspec.yaml"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/retry-backoff/tasks.md"   # 階段 apply
CARD='{"pane":"w1:pE","tab":"w1:tB","workspace":"acmecorp-ai","workspace_id":"w1","agent":"claude","model":"claude-sonnet-5-5","mode":"autopilot","worktree":"/x","kind":"bug-fix","branch":"fix/retry-backoff/mikaela","grants":[],"once":[],"drive_pid":null}'
put_entry Acmecorp-CS/retry-backoff "$CARD"
export OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
cd "$R"

# --- usage 有 relaunch ---
opsx --help 2>&1 | grep -q '^  relaunch <slug>' || fail "opsx --help 要列 relaunch"

# --- 前置檢查：不符就 exit 非 0、訊息寫出原因與看到的值、不送鍵 ---
# working 的 agent 不動
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE working "$SID"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "working 要拒絕: $out"
case "$out" in *working*) ;; *) fail "訊息要含 working: $out" ;; esac
no_keys_sent "working 不能送鍵"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert "relaunching_at" not in e,e' "$J" || fail "沒動手不該留標記"
# 其他狀態（unknown）也不動
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE unknown "$SID"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "unknown 要拒絕: $out"
case "$out" in *unknown*) ;; *) fail "訊息要含 unknown: $out" ;; esac
no_keys_sent "unknown 不能送鍵"

# codex 拒絕
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE idle "$SID"; : > "$OPSX_FAKE_LOG"
put_entry Acmecorp-CS/retry-backoff "$(printf '%s' "$CARD" | sed 's/"agent":"claude"/"agent":"codex"/')"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "codex 要拒絕: $out"
case "$out" in *只支援\ claude*codex*) ;; *) fail "訊息要說只支援 claude、看到 codex: $out" ;; esac
no_keys_sent "codex 不能送鍵"
put_entry Acmecorp-CS/retry-backoff "$CARD"

# 找不到 session id：列表裡沒有這個 pane
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pZ idle "$SID"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "對不到 pane 要拒絕: $out"
case "$out" in *w1:pE*) ;; *) fail "訊息要含 pane id: $out" ;; esac
no_keys_sent "對不到 pane 不能送鍵"
# 對得到 pane 但沒有 agent_session
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE idle; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "沒有 session id 要拒絕: $out"
case "$out" in *w1:pE*session*) ;; *) fail "訊息要含 pane id 與 session: $out" ;; esac
no_keys_sent "沒有 session id 不能送鍵"
# agent list 本身失敗：印 herdr 的原文
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE idle "$SID"; : > "$OPSX_FAKE_LOG"
out="$(OPSX_TEST_HERDR_LIST_FAIL='socket refused' opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "agent list 失敗要非 0: $out"
case "$out" in *'socket refused'*) ;; *) fail "要印 herdr 的錯誤: $out" ;; esac
no_keys_sent "agent list 失敗不能送鍵"

# 沒派過 / 已 stopped / 已交接
: > "$OPSX_FAKE_LOG"
out="$(opsx relaunch nope 2>&1)"; [ $? -ne 0 ] || fail "沒派過要拒絕: $out"
case "$out" in *沒派過*) ;; *) fail "訊息要說沒派過: $out" ;; esac
put_entry Acmecorp-CS/retry-backoff "$(printf '%s' "$CARD" | sed 's/"mode":"autopilot"/"mode":"stopped"/')"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "stopped 要拒絕: $out"
case "$out" in *stopped*) ;; *) fail "訊息要說 stopped: $out" ;; esac
put_entry Acmecorp-CS/retry-backoff "$(printf '%s' "$CARD" | sed 's/"drive_pid":null/"drive_pid":null,"handed_to":["kid"],"handed_at":"2026-11-11T10:00:00+08:00"/')"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "已交接要拒絕: $out"
case "$out" in *kid*) ;; *) fail "訊息要說交接給誰: $out" ;; esac
no_keys_sent "拒絕時不能送鍵"
put_entry Acmecorp-CS/retry-backoff "$CARD"

# --- 單卡 relaunch 的送鍵順序；送 esc 那一刻條目有 relaunching_at，結束後不在 ---
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE idle "$SID"; : > "$OPSX_FAKE_LOG"
printf '[ "$4" = esc ] && cp "%s" "%s"\nexit 0\n' "$J" "$FX/at-esc.json" > "$FX/on-keys.sh"
export OPSX_TEST_ON_SEND_KEYS="$FX/on-keys.sh"
out="$(opsx relaunch retry-backoff 2>&1)"; assert_eq "$?" 0 "relaunch rc: $out"
START="agent start retry-backoff --kind claude --pane w1:pE -- --resume $SID --model claude-sonnet-5-5 --permission-mode dontAsk --settings $OPSX_STATE_DIR/settings/Acmecorp-CS-retry-backoff-autopilot.json --add-dir $R/openspec --add-dir $OPSX_STATE_DIR"
assert_eq "$(grep -vE '^(pane read)' "$OPSX_FAKE_LOG")" "agent list
pane send-keys w1:pE esc
pane send-text w1:pE /exit
pane send-keys w1:pE enter
$START
agent prompt retry-backoff /opsx-workflow:apply retry-backoff" "送鍵順序"
assert_not_grep 'enter.*esc\|esc.*enter' "$OPSX_FAKE_LOG"
assert_file "$FX/at-esc.json"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert e.get("relaunching_at","").startswith("20"),e' "$FX/at-esc.json" || fail "送 esc 時條目要有 relaunching_at"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert "relaunching_at" not in e,e' "$J" || fail "relaunch 結束要清掉 relaunching_at"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert e["pane"]=="w1:pE" and e["mode"]=="autopilot" and e["agent"]=="claude",e' "$J" || fail "relaunch 不改條目的 pane / mode / agent"
tail -1 "$R/openspec/changes/retry-backoff/decisions.tsv" | grep -q "relaunch.*$SID" || fail "decisions.tsv 要記一列 relaunch"
unset OPSX_TEST_ON_SEND_KEYS
# 跟 dispatch 同一套參數：同一份 launch_args 的輸出
( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/python.sh"; opsx_python_load; source "$OPSX_ROOT/bin/lib/launch.sh"
  launch_args claude claude-sonnet-5-5 autopilot Acmecorp-CS retry-backoff "$R"; printf '%s' "${LAUNCH_ARGS[*]}" ) > "$FX/args.txt"
assert_eq "${START#*--resume $SID }" "$(cat "$FX/args.txt")" "relaunch 的參數要等於 launch_args"

# --- relaunching_at 是鎖：10 分鐘內有別的 relaunch 在跑就拒絕，它的標記不動 ---
NOW="$(python3 -I -c 'import datetime;print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))')"
put_entry Acmecorp-CS/retry-backoff "$(printf '%s' "$CARD" | sed "s/\"drive_pid\":null/\"drive_pid\":null,\"relaunching_at\":\"$NOW\"/")"
: > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "已有人在 relaunch 要拒絕: $out"
case "$out" in *"$NOW"*) ;; *) fail "訊息要印出既有標記的時間: $out" ;; esac
no_keys_sent "已有人在 relaunch 不能送鍵"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert e.get("relaunching_at")==sys.argv[2],e' "$J" "$NOW" || fail "別人的標記不能被清掉"
# 超過 10 分鐘的標記當作殘留（relaunch 被 kill），照常重開
OLDMARK="$(python3 -I -c 'import datetime;print((datetime.datetime.now().astimezone()-datetime.timedelta(hours=1)).isoformat(timespec="seconds"))')"
put_entry Acmecorp-CS/retry-backoff "$(printf '%s' "$CARD" | sed "s/\"drive_pid\":null/\"drive_pid\":null,\"relaunching_at\":\"$OLDMARK\"/")"
out="$(opsx relaunch retry-backoff 2>&1)"; assert_eq "$?" 0 "殘留的舊標記不擋: $out"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert "relaunching_at" not in e,e' "$J" || fail "結束後要清掉標記"
put_entry Acmecorp-CS/retry-backoff "$CARD"

# --- shell 還沒好就重試：兩次 agent_pane_busy 再成功 ---
export OPSX_TEST_BUSY_LEFT="$FX/busy-left"; echo 2 > "$OPSX_TEST_BUSY_LEFT"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; assert_eq "$?" 0 "busy 兩次再成功: $out"
assert_eq "$(grep -c '^agent start retry-backoff ' "$OPSX_FAKE_LOG")" 3 "兩次 busy 加一次成功 = 三次 agent start"
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
assert_not_grep '^pane close' "$OPSX_FAKE_LOG"
# 一直 busy：六次後失敗，不關 tab 或 pane
echo 99 > "$OPSX_TEST_BUSY_LEFT"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "一直 busy 要失敗: $out"
assert_eq "$(grep -c '^agent start retry-backoff ' "$OPSX_FAKE_LOG")" 6 "六次後放棄"
case "$out" in *agent_pane_busy*) ;; *) fail "要印 herdr 的錯誤: $out" ;; esac
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
assert_not_grep '^pane close' "$OPSX_FAKE_LOG"
unset OPSX_TEST_BUSY_LEFT

# --- /exit 後 herdr 還沒放掉名字：agent_name_taken 兩次再成功 ---
export OPSX_TEST_TAKEN_LEFT="$FX/taken-left"; echo 2 > "$OPSX_TEST_TAKEN_LEFT"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; assert_eq "$?" 0 "name_taken 兩次再成功: $out"
assert_eq "$(grep -c '^agent start retry-backoff ' "$OPSX_FAKE_LOG")" 3 "兩次 name_taken 加一次成功 = 三次 agent start"
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
assert_not_grep '^pane close' "$OPSX_FAKE_LOG"
# busy 與 name_taken 共用同一個六次：各回三次就用完
echo 3 > "$OPSX_TEST_TAKEN_LEFT"; export OPSX_TEST_BUSY_LEFT="$FX/busy-left"; echo 3 > "$OPSX_TEST_BUSY_LEFT"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "共用計數用完要失敗: $out"
assert_eq "$(grep -c '^agent start retry-backoff ' "$OPSX_FAKE_LOG")" 6 "busy 加 name_taken 共六次後放棄"
unset OPSX_TEST_BUSY_LEFT
# 一直被占：六次後失敗，印 herdr 的錯誤與 pane 畫面，標記清掉，不關 tab 或 pane
echo 99 > "$OPSX_TEST_TAKEN_LEFT"; : > "$OPSX_FAKE_LOG"
out="$(OPSX_TEST_PANE_TEXT='$ claude-pane-screen-xyz' opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "一直 name_taken 要失敗: $out"
assert_eq "$(grep -c '^agent start retry-backoff ' "$OPSX_FAKE_LOG")" 6 "name_taken 六次後放棄"
case "$out" in *agent_name_taken*claude-pane-screen-xyz*) ;; *) fail "要印 herdr 錯誤與 pane 畫面: $out" ;; esac
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
assert_not_grep '^pane close' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert "relaunching_at" not in e,e' "$J" || fail "失敗後要清掉標記"
unset OPSX_TEST_TAKEN_LEFT

# --- 可重開的狀態：idle、blocked、done 都照常送鍵並成功 ---
for st in idle blocked done; do
  mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE "$st" "$SID"; : > "$OPSX_FAKE_LOG"
  out="$(opsx relaunch retry-backoff 2>&1)"; assert_eq "$?" 0 "$st 要能重開: $out"
  assert_grep '^pane send-text w1:pE /exit' "$OPSX_FAKE_LOG"
  assert_grep '^agent start retry-backoff ' "$OPSX_FAKE_LOG"
done
# 拒絕訊息列出可重開的全部狀態
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE working "$SID"
out="$(opsx relaunch retry-backoff 2>&1)"
case "$out" in *idle*blocked*done*) ;; *) fail "拒絕訊息要列出 idle、blocked、done: $out" ;; esac
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE idle "$SID"

# --- drive 先停、後起：條目的 drive_pid 是活著的行程 ---
# 行程不掛在測試 shell 底下，被 kill 後才不會留成 zombie（zombie 對 kill -0 還是成功）
# fd 全部導走：不然它握著 run.sh 收輸出的 pipe，測試失敗時要等它睡完
( sleep 300 < /dev/null > /dev/null 2>&1 & echo $! > "$FX/old-drive.pid" )
OLD="$(cat "$FX/old-drive.pid")"
trap 'kill "$OLD" 2>/dev/null; rm -rf "$FX"' EXIT
kill -0 "$OLD" || fail "fixture 的 drive 行程沒起來"
export OPSX_TEST_PS_CMD="bash /x/bin/opsx drive retry-backoff --repo $R"   # 假 ps：這個 pid 看起來是這張卡的 drive
put_entry Acmecorp-CS/retry-backoff "$(printf '%s' "$CARD" | sed "s/\"drive_pid\":null/\"drive_pid\":$OLD/")"
# 壞的 grants.toml：寫 settings 失敗要在送鍵、kill drive 之前就停
printf 'repos = [\n' > "$OPSX_STATE_DIR/grants.toml"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "壞 grants.toml 要失敗: $out"
rm -f "$OPSX_STATE_DIR/grants.toml"
no_keys_sent "壞 grants.toml 不能送鍵"
kill -0 "$OLD" || fail "壞 grants.toml 時 drive 不能被 kill"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert "relaunching_at" not in e,e' "$J" || fail "沒動手不該留標記"
DL="$OPSX_STATE_DIR/drive-Acmecorp-CS-retry-backoff.log"; rm -f "$DL"
printf '[ "$4" = esc ] || exit 0\nif kill -0 %s 2>/dev/null; then echo alive; else echo dead; fi > "%s"\n' "$OLD" "$FX/drive-at-esc" > "$FX/on-keys.sh"
export OPSX_TEST_ON_SEND_KEYS="$FX/on-keys.sh"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; assert_eq "$?" 0 "relaunch with drive: $out"
unset OPSX_TEST_ON_SEND_KEYS
assert_eq "$(cat "$FX/drive-at-esc")" dead "送 esc 之前 drive 要已經被 kill"
n=0; until grep -q '跑滿 0 輪' "$DL" 2>/dev/null; do n=$((n+1)); [ $n -lt 50 ] || fail "relaunch 成功後要在背景起 drive：$(cat "$DL" 2>&1)"; sleep 0.1; done
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert e["drive_pid"]!=int(sys.argv[2]),e' "$J" "$OLD" || fail "被 kill 的 drive pid 不能留在條目上"
# pid 被別的行程重用：command 不是這張卡的 drive 就不 kill（spec 的 Scenario Outline 四列），relaunch 照樣接回 session 並起 drive
for row in "bash /x/bin/opsx drive retry-backoff --repo $R|dead" "bash /x/bin/opsx drive retry-backoff|dead" "/usr/bin/vim notes.md|alive" "bash /x/bin/opsx drive retry --repo $R|alive" "bash /x/bin/opsx drive retry-backoff-2 --repo $R|alive"; do
  ( sleep 300 < /dev/null > /dev/null 2>&1 & echo $! > "$FX/row.pid" ); ROWPID="$(cat "$FX/row.pid")"
  export OPSX_TEST_PS_CMD="${row%|*}"; want="${row##*|}"
  put_entry Acmecorp-CS/retry-backoff "$(printf '%s' "$CARD" | sed "s/\"drive_pid\":null/\"drive_pid\":$ROWPID/")"
  rm -f "$DL"; : > "$OPSX_FAKE_LOG"
  out="$(opsx relaunch retry-backoff 2>&1)"; assert_eq "$?" 0 "relaunch（${row%|*}）: $out"
  n=0; until grep -q '跑滿 0 輪' "$DL" 2>/dev/null; do n=$((n+1)); [ $n -lt 50 ] || fail "drive 沒起來：$(cat "$DL" 2>&1)"; sleep 0.1; done
  if kill -0 "$ROWPID" 2>/dev/null; then got=alive; else got=dead; fi
  kill "$ROWPID" 2>/dev/null
  assert_eq "$got" "$want" "command「${row%|*}」"
  [ "$want" = dead ] || case "$out" in *"$ROWPID"*) ;; *) fail "不 kill 時訊息要含 pid $ROWPID: $out" ;; esac
  assert_grep '^agent start retry-backoff ' "$OPSX_FAKE_LOG"
done
export OPSX_TEST_PS_CMD="bash /x/bin/opsx drive retry-backoff --repo $R"
# interactive 單卡：不起 drive
put_entry Acmecorp-CS/retry-backoff "$(printf '%s' "$CARD" | sed 's/"mode":"autopilot"/"mode":"interactive"/')"
rm -f "$DL"
out="$(opsx relaunch retry-backoff 2>&1)"; assert_eq "$?" 0 "interactive relaunch: $out"
assert_grep "^agent start retry-backoff --kind claude --pane w1:pE -- --resume $SID --model claude-sonnet-5-5 --settings $OPSX_STATE_DIR/settings/Acmecorp-CS-retry-backoff-interactive.json " "$OPSX_FAKE_LOG"
sleep 0.3; assert_no_file "$DL"
put_entry Acmecorp-CS/retry-backoff "$CARD"

# --- fan-out 子卡（via 父卡名）：父卡在 fan-out 前就已歸檔；重開父卡的 pane，對每個沒停的子卡送 [<kid>] …，不起 drive ---
mkdir -p "$R/openspec/changes/archive/2026-11-10-par" "$R/openspec/changes/kid" "$R/openspec/changes/kid2"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/kid/tasks.md"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/kid2/tasks.md"
put_entry Acmecorp-CS/par '{"pane":"w1:pP","agent":"claude","model":"claude-opus-5-5","mode":"autopilot","drive_pid":null,"handed_to":["kid","kid2","kid3"],"handed_at":"2026-11-10T10:00:00+08:00"}'
KIDE='{"pane":"w1:pP","agent":"claude","model":"claude-opus-5-5","mode":"autopilot","via":"par","herdr_name":"par"}'
put_entry Acmecorp-CS/kid "$KIDE"
put_entry Acmecorp-CS/kid2 "$KIDE"
put_entry Acmecorp-CS/kid3 "$(printf '%s' "$KIDE" | sed 's/"mode":"autopilot"/"mode":"stopped"/')"
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pP idle "$SID"; : > "$OPSX_FAKE_LOG"
rm -f "$OPSX_STATE_DIR/drive-Acmecorp-CS-par.log" "$OPSX_STATE_DIR/drive-Acmecorp-CS-kid.log"
out="$(opsx relaunch kid 2>&1)"; assert_eq "$?" 0 "fan-out 子卡 relaunch: $out"
assert_grep "^agent start par --kind claude --pane w1:pP -- --resume $SID --model claude-opus-5-5 --permission-mode dontAsk --settings $OPSX_STATE_DIR/settings/Acmecorp-CS-par-autopilot.json " "$OPSX_FAKE_LOG"
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt par [kid] /opsx-workflow:apply kid
agent prompt par [kid2] /opsx-workflow:apply kid2" "每個沒停的子卡各收到一句，帶 [<kid>]"
sleep 0.3; assert_no_file "$OPSX_STATE_DIR/drive-Acmecorp-CS-par.log"; assert_no_file "$OPSX_STATE_DIR/drive-Acmecorp-CS-kid.log"
tail -1 "$R/openspec/changes/kid/decisions.tsv" | grep -q 'relaunch' || fail "decisions.tsv 要記在被要求的子卡上"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/par"];assert "relaunching_at" not in e,e' "$J" || fail "結束後要清掉父卡條目的標記"
# 巢狀：kid 合併歸檔後自己再 fan-out 出 gk1、gk2（via kid、herdr 名仍是 par、同一個 pane）。
# 重開的是根條目 par（它的 model 與鎖），走得到 par 的每張沒停、沒交接的卡都收一句
mv "$R/openspec/changes/kid" "$R/openspec/changes/archive/2026-11-11-kid"
mkdir -p "$R/openspec/changes/gk1" "$R/openspec/changes/gk2"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/gk1/tasks.md"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/gk2/tasks.md"
put_entry Acmecorp-CS/kid "$(printf '%s' "$KIDE" | sed -e 's/"model":"claude-opus-5-5"/"model":"claude-sonnet-5-5"/' -e 's/"herdr_name":"par"/"herdr_name":"par","handed_to":["gk1","gk2"],"handed_at":"2026-11-11T10:00:00+08:00"/')"
GKE='{"pane":"w1:pP","agent":"claude","model":"claude-haiku-5-5","mode":"autopilot","via":"kid","herdr_name":"par"}'
put_entry Acmecorp-CS/gk1 "$GKE"
put_entry Acmecorp-CS/gk2 "$GKE"
printf '[ "$4" = esc ] && cp "%s" "%s"\nexit 0\n' "$J" "$FX/nest-at-esc.json" > "$FX/on-keys.sh"
export OPSX_TEST_ON_SEND_KEYS="$FX/on-keys.sh"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch gk1 2>&1)"; assert_eq "$?" 0 "巢狀 fan-out relaunch: $out"
unset OPSX_TEST_ON_SEND_KEYS
assert_grep "^agent start par --kind claude --pane w1:pP -- --resume $SID --model claude-opus-5-5 " "$OPSX_FAKE_LOG"
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt par [kid2] /opsx-workflow:apply kid2
agent prompt par [gk1] /opsx-workflow:apply gk1
agent prompt par [gk2] /opsx-workflow:apply gk2" "同一個 pane 代管的每張沒停、沒交接的卡都收一句"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["Acmecorp-CS/par"].get("relaunching_at"),d["Acmecorp-CS/par"];assert "relaunching_at" not in d["Acmecorp-CS/kid"],d["Acmecorp-CS/kid"]' "$FX/nest-at-esc.json" || fail "鎖要寫在根條目 par，不是 kid"
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE idle "$SID"

# --- session 成員導到 session pane ---
RF="$(mk_repo Feat-Repo)"
for s in m1 m2 m3; do mkdir -p "$RF/openspec/changes/$s"; printf 'schema: opsx\nkind: dev\n' > "$RF/openspec/changes/$s/.openspec.yaml"; printf -- '- [ ] 1.1 x\n' > "$RF/openspec/changes/$s/tasks.md"; done
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$RF/openspec/changes/m3/explore.md"; rm "$RF/openspec/changes/m3/tasks.md"   # m3 在 propose
put_entry Feat-Repo/@fs '{"pane":"w1:pS","tab":"w1:tS","agent":"claude","model":"claude-opus-5-5","mode":"autopilot","worktree":"/x","drive_pid":null}'
MEMBER='{"pane":"w1:pS","agent":"claude","model":"claude-opus-5-5","mode":"autopilot","herdr_name":"fs","feature":"fs","via":"@fs"}'
put_entry Feat-Repo/m1 "$MEMBER"
put_entry Feat-Repo/m2 "$(printf '%s' "$MEMBER" | sed 's/"mode":"autopilot"/"mode":"stopped"/')"
put_entry Feat-Repo/m3 "$MEMBER"
put_entry Other-Repo/m9 "$MEMBER"   # 別的 repo 同名 feature 的成員不是這個 session 的
mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pS idle "$SID"; : > "$OPSX_FAKE_LOG"
printf '[ "$4" = esc ] && cp "%s" "%s"\nexit 0\n' "$J" "$FX/fs-at-esc.json" > "$FX/on-keys.sh"
export OPSX_TEST_ON_SEND_KEYS="$FX/on-keys.sh"
out="$(cd "$RF" && opsx relaunch m1 2>&1)"; assert_eq "$?" 0 "session 成員 relaunch: $out"
unset OPSX_TEST_ON_SEND_KEYS
assert_grep "^agent start fs --kind claude --pane w1:pS -- --resume $SID --model claude-opus-5-5 --permission-mode dontAsk --settings $OPSX_STATE_DIR/settings/Feat-Repo-fs-autopilot.json --add-dir $RF/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"
assert_file "$OPSX_STATE_DIR/settings/Feat-Repo-fs-autopilot.json"
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt fs [m1] /opsx-workflow:apply m1
agent prompt fs [m3] /opsx-workflow:propose m3" "每個沒停的成員各收到一句"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["Feat-Repo/@fs"].get("relaunching_at"),d["Feat-Repo/@fs"]' "$FX/fs-at-esc.json" || fail "session 條目在送 esc 時要有 relaunching_at"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert not any("relaunching_at" in e for e in d.values()),d' "$J" || fail "結束後 relaunching_at 要清掉"
sleep 0.3; assert_no_file "$OPSX_STATE_DIR/drive-Feat-Repo-fs.log"; assert_no_file "$OPSX_STATE_DIR/drive-Feat-Repo-m1.log"
tail -1 "$RF/openspec/changes/m1/decisions.tsv" | grep -q 'relaunch' || fail "decisions.tsv 要記一列 relaunch"
# 沒停的成員卡目錄不在（歸檔了）：不對它送 /explore，送鍵前就停
put_entry Feat-Repo/gone "$MEMBER"; : > "$OPSX_FAKE_LOG"
out="$(cd "$RF" && opsx relaunch m1 2>&1)"; [ $? -ne 0 ] || fail "成員卡目錄不在要拒絕: $out"
case "$out" in *gone*) ;; *) fail "訊息要指名 gone: $out" ;; esac
no_keys_sent "成員卡目錄不在不能送鍵"
put_entry Feat-Repo/gone "$(printf '%s' "$MEMBER" | sed 's/"mode":"autopilot"/"mode":"stopped"/')"
# 成員已歸檔（session 自己 /archive 過，條目沒標 stopped）：略過它，照送其他成員
mkdir -p "$RF/openspec/changes/archive/2026-11-10-old"; put_entry Feat-Repo/old "$MEMBER"; : > "$OPSX_FAKE_LOG"
out="$(cd "$RF" && opsx relaunch m1 2>&1)"; assert_eq "$?" 0 "已歸檔的成員要略過: $out"
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt fs [m1] /opsx-workflow:apply m1
agent prompt fs [m3] /opsx-workflow:propose m3" "已歸檔的成員不收話，其他成員照送"

# --- agent start 失敗大聲報：exit 非 0、herdr 錯誤與 pane 畫面、decisions.tsv 一列、標記清掉、不關 pane / tab ---
cd "$R"; mk_agents "$OPSX_TEST_HERDR_AGENTS" w1:pE idle "$SID"; : > "$OPSX_FAKE_LOG"
TSV="$R/openspec/changes/retry-backoff/decisions.tsv"; rows="$(wc -l < "$TSV")"
out="$(OPSX_TEST_START_FAIL=agent_name_taken OPSX_TEST_PANE_TEXT='$ claude-pane-screen-xyz' opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "agent start 失敗要非 0: $out"
case "$out" in *agent_name_taken*) ;; *) fail "要印 herdr 錯誤: $out" ;; esac
case "$out" in *claude-pane-screen-xyz*) ;; *) fail "要印 pane 畫面: $out" ;; esac
assert_eq "$(( $(wc -l < "$TSV") ))" "$((rows + 1))" "decisions.tsv 多一列"
tail -1 "$TSV" | grep -q 'relaunch 失敗' || fail "那一列要寫 relaunch 失敗：$(tail -1 "$TSV")"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert "relaunching_at" not in e,e' "$J" || fail "失敗也要清掉 relaunching_at"
assert_grep '^pane read w1:pE' "$OPSX_FAKE_LOG"
assert_not_grep '^pane close' "$OPSX_FAKE_LOG"
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
assert_not_grep '^agent prompt' "$OPSX_FAKE_LOG"
# 送站失敗也一樣
printf 'agent_not_found\n' > "$FX/prompt-err"; : > "$OPSX_FAKE_LOG"
out="$(OPSX_TEST_PROMPT_ERR="$FX/prompt-err" opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "送站失敗要非 0: $out"
case "$out" in *agent_not_found*) ;; *) fail "要印 herdr 錯誤: $out" ;; esac
tail -1 "$TSV" | grep -q 'relaunch 失敗' || fail "送站失敗也要記一列"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert "relaunching_at" not in e,e' "$J" || fail "失敗也要清掉 relaunching_at"
assert_not_grep '^pane close' "$OPSX_FAKE_LOG"
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
# pane 已讀不到：當成沒輸出，照樣報原本的錯
: > "$OPSX_FAKE_LOG"
out="$(OPSX_TEST_START_FAIL=agent_name_taken OPSX_TEST_PANE_READ_FAIL=1 opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "要非 0: $out"
case "$out" in *agent_name_taken*'pane 沒有任何輸出'*) ;; *) fail "pane read 失敗要當成沒輸出: $out" ;; esac

# --- 送 /exit 中途失敗（esc 那一步）：非 0，不再送 /exit、不重起，pane 不關 ---
# 假 herdr 的 send-keys 不會自己失敗：hook 把假 herdr 本身 kill 掉，呼叫端就拿到非 0
printf '[ "$4" = esc ] || exit 0\nkill -TERM "$PPID"\n' > "$FX/esc-fail.sh"
: > "$OPSX_FAKE_LOG"
out="$(OPSX_TEST_ON_SEND_KEYS="$FX/esc-fail.sh" opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "esc 送不出去要非 0: $out"
case "$out" in *w1:pE*) ;; *) fail "訊息要含 pane id: $out" ;; esac
assert_grep '^pane send-keys w1:pE esc$' "$OPSX_FAKE_LOG"
assert_not_grep '^pane send-text' "$OPSX_FAKE_LOG"
assert_not_grep '^agent start' "$OPSX_FAKE_LOG"
assert_not_grep '^pane close' "$OPSX_FAKE_LOG"
assert_not_grep '^tab close' "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["Acmecorp-CS/retry-backoff"];assert "relaunching_at" not in e,e' "$J" || fail "失敗也要清掉 relaunching_at"

# --- drive log 是 symlink：pane 已接回但不起 drive，訊息寫原因與 pane ---
put_entry Acmecorp-CS/retry-backoff "$CARD"
DL="$OPSX_STATE_DIR/drive-Acmecorp-CS-retry-backoff.log"; rm -f "$DL"; ln -s "$FX/elsewhere" "$DL"; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch retry-backoff 2>&1)"; [ $? -ne 0 ] || fail "drive log 是 symlink 要非 0: $out"
case "$out" in *'refuse to write through symlink'*w1:pE*) ;; *) fail "要寫出 symlink 原因與 pane: $out" ;; esac
assert_grep '^agent prompt retry-backoff ' "$OPSX_FAKE_LOG"
rm -f "$DL"

echo ok
