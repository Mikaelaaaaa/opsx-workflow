#!/usr/bin/env bash
# evals/run-candidate.sh：候選者在系統 temp 的中性工作 repo 裡另開只載專案層設定的 claude -p session，transcript 進結果目錄。
# 用假 claude（tests/fakes/claude）看外部行為：cwd、旗標、--settings 內容、第二輪 id、結果目錄。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes claude
runner="$OPSX_ROOT/evals/run-candidate.sh"
banned='claude|eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena'

# 端到端測試的 base：不含禁用字，且上層沒有 CLAUDE.md、.claude/（runner 會拒跑那種位置）。
# 沙盒裡 $TMPDIR 含 claude、/tmp 不可寫、$HOME 有 CLAUDE.md，常常一個都沒有；沒有時端到端部分 SKIP，拒跑類測試照跑
marker_above() { # marker_above <dir>：印出 <dir> 上層第一個含 CLAUDE.md 或 .claude 的 "目錄/檔名"，沒有就不印
  local d="$1" m
  while [ "$d" != "/" ]; do
    d="$(dirname "$d")"
    for m in CLAUDE.md .claude; do
      [ -e "$d/$m" ] && { echo "$d/$m"; return; }
    done
  done
}
real() { (cd "$1" && pwd -P); }
NT=""; skip_why=""
for base in "$TMPDIR" /tmp "$HOME/.local/state/opsx"; do
  d="$(mktemp -d "$base/run.XXXXXX" 2>/dev/null)" || { skip_why="$skip_why [$base: not writable]"; continue; }
  if real "$d" | grep -Eiq "$banned"; then rm -rf "$d"; skip_why="$skip_why [$base: banned word in path]"; continue; fi
  above="$(marker_above "$(real "$d")")"
  if [ -n "$above" ]; then rm -rf "$d"; skip_why="$skip_why [$base: $above above it]"; continue; fi
  NT="$(real "$d")"; break
done
trap 'rm -rf "$FX" "$NT"' EXIT

export CLAUDE_CONFIG_DIR="$FX/cfg"
export OPSX_FAKE_LOG="$FX/calls.jsonl"
unset ANTHROPIC_API_KEY

run() { # run <label> <runner args...>：stdout、stderr 寫到 $FX/<label>.out / .err，回傳 rc
  local label="$1"; shift
  : > "$OPSX_FAKE_LOG"
  TMPDIR="$NT" bash "$runner" "$@" >"$FX/$label.out" 2>"$FX/$label.err"
}
field() { sed -n "s/^$1: //p" "$2"; }   # runner 印的 work: / session: / transcript:
calls() { wc -l < "$OPSX_FAKE_LOG" | tr -d ' '; }
call_py() { # call_py <n> <python 運算式，c 是第 n 次呼叫的紀錄>
  python3 -I -c 'import json,sys; c=[json.loads(l) for l in open(sys.argv[1])][int(sys.argv[2])]; print(eval(sys.argv[3]))' "$OPSX_FAKE_LOG" "$1" "$2"
}
arg_after() { call_py "$1" "c['argv'][c['argv'].index('$2')+1] if '$2' in c['argv'] else ''"; }
prompt_of() { python3 -I -c 'import json,sys; print(next(e for e in json.load(open(sys.argv[1]))["evals"] if e["id"]==int(sys.argv[2]))[sys.argv[3]])' "$OPSX_ROOT/skills/$1/evals/evals.json" "$2" "$3"; }

refuse() { # refuse <label> <runner 的 TMPDIR> <結果目錄>：runner 要非零結束、沒呼叫 claude；stderr 在 $FX/<label>.err
  local label="$1"
  : > "$OPSX_FAKE_LOG"
  TMPDIR="$2" bash "$runner" grill 1 new "$3" >"$FX/$label.out" 2>"$FX/$label.err" && fail "runner must refuse: $label"
  assert_eq "$(calls)" "0" "no claude call when refusing: $label"
}

# 拒跑：工作 repo 的上層目錄有 CLAUDE.md 或 .claude/，訊息指名該目錄與檔名（這幾條不需要中性 base）
mkdir -p "$FX/anc-md/t" "$FX/anc-dot/.claude" "$FX/anc-dot/t"
: > "$FX/anc-md/CLAUDE.md"
refuse anc-md "$FX/anc-md/t" "$FX/res-anc-md"
assert_grep "$(real "$FX/anc-md")" "$FX/anc-md.err"
assert_grep "CLAUDE.md" "$FX/anc-md.err"
refuse anc-dot "$FX/anc-dot/t" "$FX/res-anc-dot"
assert_grep "$(real "$FX/anc-dot")" "$FX/anc-dot.err"
assert_grep "\.claude" "$FX/anc-dot.err"

# 拒跑：工作 repo 落在 root 或結果目錄底下，訊息印出路徑
rt="$(mktemp -d "$OPSX_ROOT/rc-tmp.XXXXXX")"
refuse under-root "$rt" "$FX/res-under-root"
assert_grep "is under $(real "$OPSX_ROOT")" "$FX/under-root.err"
rm -rf "$rt"
mkdir -p "$FX/res-under/t"
refuse under-res "$FX/res-under/t" "$FX/res-under"
assert_grep "is under $(real "$FX/res-under")" "$FX/under-res.err"

[ -n "$NT" ] || { echo "SKIP run-candidate end-to-end: no usable temp base:$skip_why"; echo ok; exit 0; }

# 單輪題（grill 1 empty-pending-stops），沒有 API key：只跑一次，帶 --setting-sources project,local / --session-id / --settings，不帶 --bare，prompt 逐字相同
res="$FX/results-single"
run single grill 1 new "$res" || fail "single-turn run without an API key failed: $(cat "$FX/single.err")"
work="$(field work "$FX/single.out")"; id="$(field session "$FX/single.out")"; tr="$(field transcript "$FX/single.out")"
[ -n "$work" ] && [ -n "$id" ] && [ -n "$tr" ] || fail "runner must print work / session / transcript: $(cat "$FX/single.out")"
assert_eq "$(calls)" "1" "single-turn question calls claude once"
cwd0="$(call_py 0 "c['cwd']")"   # 執行當下的工作 repo（在 temp 底下）；跑完 runner 把它搬進結果目錄
assert_eq "$work" "$(real "$res")/$id/empty-pending" "work: is the final path inside the results dir"
[ "$cwd0" != "$work" ] || fail "claude must run in the temp work repo, not in the results dir: $cwd0"
assert_eq "$(call_py 0 "'-p' in c['argv']")" "True" "claude needs -p"
assert_eq "$(arg_after 0 --setting-sources)" "project,local" "user settings, plugins and skills must not load"
assert_eq "$(call_py 0 "'--bare' in c['argv']")" "False" "--bare needs an API key the user does not have"
assert_eq "$(arg_after 0 --session-id)" "$id"
echo "$id" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || fail "session id must be a lowercase uuid, got $id"
assert_eq "$(arg_after 0 -p)" "$(prompt_of grill 1 prompt)" "prompt must equal evals.json verbatim"
assert_eq "$(call_py 0 "'--resume' in c['argv']")" "False"

# 工作 repo：執行當下在 temp 底下，不在本 repo、題目目錄、結果目錄底下，路徑不含禁用字；跑完是 git repo，專案名是 fixture 名
git -C "$work" rev-parse --git-dir >/dev/null 2>&1 || fail "work dir $work is not a git repo"
case "$cwd0" in "$NT"/*) ;; *) fail "work repo $cwd0 was not under the system temp dir $NT while claude ran" ;; esac
for p in "$OPSX_ROOT" "$OPSX_ROOT/skills/grill/evals/fixtures/empty-pending" "$(cd "$res" && pwd -P)"; do
  case "$cwd0/" in "$p"/*) fail "work repo $cwd0 was under $p while claude ran" ;; esac
done
! echo "$cwd0" | grep -Eiq "$banned" || fail "work path carries a banned word: $cwd0"

# 跑完：temp 裡不留 run.*；stdout 先有 starting:（在假 claude 印 fake-claude-ran 之前），再有結束時的三行
assert_eq "$(ls "$NT" | grep -c '^run\.' || true)" "0" "no run.* left in temp after the run"
assert_grep "^starting: session=$id work=$cwd0\$" "$FX/single.out"
[ "$(grep -n '^starting:' "$FX/single.out" | cut -d: -f1)" -lt "$(grep -n '^fake-claude-ran' "$FX/single.out" | cut -d: -f1)" ] || fail "starting: must be printed before claude runs"
assert_eq "$(grep -c '^work: ' "$FX/single.out")" "1"
assert_eq "$(grep -c '^session: ' "$FX/single.out")" "1"
assert_eq "$(grep -c '^transcript: ' "$FX/single.out")" "1"
assert_eq "$(basename "$work")" "empty-pending" "project name is the fixture name"
assert_file "$work/.claude/skills/grill/SKILL.md"

# --settings：開 sandbox、不留沒 sandbox 的後門、不多給可寫目錄；跑完 settings 檔刪掉
assert_eq "$(call_py 0 "c['settings']['sandbox']['enabled']")" "True" "settings must enable the sandbox"
assert_eq "$(call_py 0 "c['settings']['sandbox']['allowUnsandboxedCommands']")" "False"
assert_eq "$(call_py 0 "'additionalDirectories' in c['settings'].get('permissions', {})")" "False" "no write dir beyond the work repo"
assert_eq "$(call_py 0 "sorted(c['settings']['sandbox']['filesystem']['denyWrite'])")" "['/private/tmp/claude', '/tmp/claude']" "the shared claude temp dir must not be writable"
settings_path="$(arg_after 0 --settings)"
assert_no_file "$settings_path"
case "$settings_path" in "$work"/*|"$res"/*) fail "settings file must live outside the work repo and results dir" ;; esac

# transcript 進結果目錄，跟 session 的那份一樣
assert_eq "$tr" "$(cd "$res" && pwd -P)/$id.jsonl"
src="$CLAUDE_CONFIG_DIR/projects/$(echo "$cwd0" | sed 's/[^a-zA-Z0-9]/-/g')/$id.jsonl"
assert_file "$tr"
cmp -s "$src" "$tr" || fail "results transcript differs from the session transcript"

# 兩輪題（grill 0 three-bucket-pending）：第二次以同一個 id --resume，prompt 是 second_turn；transcript 含兩輪
res="$FX/results-two"
run two grill 0 new "$res" || fail "two-turn run failed: $(cat "$FX/two.err")"
id="$(field session "$FX/two.out")"; tr="$(field transcript "$FX/two.out")"
assert_eq "$(calls)" "2" "two-turn question calls claude twice"
assert_eq "$(arg_after 0 --session-id)" "$id"
assert_eq "$(arg_after 0 -p)" "$(prompt_of grill 0 prompt)"
assert_eq "$(arg_after 1 --resume)" "$id" "second turn resumes the same session"
assert_eq "$(call_py 1 "'--session-id' in c['argv']")" "False"
assert_eq "$(arg_after 1 -p)" "$(prompt_of grill 0 second_turn)" "second turn prompt is second_turn verbatim"
assert_eq "$(arg_after 1 --setting-sources)" "project,local" "second turn keeps project,local setting sources"
assert_eq "$(call_py 1 "c['settings']['sandbox']['enabled']")" "True" "second turn keeps the sandbox"
assert_eq "$(call_py 1 "c['cwd']")" "$(call_py 0 "c['cwd']")" "both turns run in the same work repo"
# 同一個 temp 連跑第二次：這次執行期間 temp 裡只有自己的 run.*，上一次的工作 repo 已在它的結果目錄
assert_eq "$(call_py 0 "len([x for x in c['siblings'] if x.startswith('run.')])")" "1" "no earlier run.* beside this run while claude ran"
assert_dir "$(real "$FX/results-single")/$(field session "$FX/single.out")/empty-pending/.git"
assert_eq "$(wc -l < "$tr" | tr -d ' ')" "2" "results transcript holds both turns"

# claude 中途非零結束（例如撞到用量上限）：transcript 與工作 repo 照樣留下、三行照印，退出碼沿用 claude 的
res="$FX/results-fail"
rc=0; OPSX_FAKE_EXIT=3 run fail grill 1 new "$res" || rc=$?
assert_eq "$rc" "3" "runner exit code is claude's"
fid="$(field session "$FX/fail.out")"
assert_file "$res/$fid.jsonl"
assert_dir "$res/$fid/empty-pending/.git"
assert_eq "$(field work "$FX/fail.out")" "$(real "$res")/$fid/empty-pending"
assert_eq "$(grep -c '^transcript: ' "$FX/fail.out")" "1"
assert_eq "$(ls "$NT" | grep -c '^run\.' || true)" "0" "no run.* left in temp after a failed run"

# transcript 不在預期位置：非零結束、訊息含找的路徑；工作 repo 照樣搬進結果目錄
res="$FX/results-notr"
rc=0; OPSX_FAKE_NO_TRANSCRIPT=1 run notr grill 1 new "$res" || rc=$?
[ "$rc" -ne 0 ] || fail "a missing transcript must make the runner fail"
assert_grep "transcript not found at $CLAUDE_CONFIG_DIR/projects/" "$FX/notr.err"
assert_dir "$res/$(field session "$FX/notr.out")/empty-pending/.git"

# 路徑含 claude 或禁用字：拒跑、印出路徑、沒呼叫 claude
mkdir -p "$NT/claude-tmp"
res="$FX/results-banned"
: > "$OPSX_FAKE_LOG"
TMPDIR="$NT/claude-tmp" bash "$runner" grill 1 new "$res" >"$FX/banned.out" 2>"$FX/banned.err" && fail "runner must refuse a work path with claude in it"
assert_grep "$NT/claude-tmp" "$FX/banned.err"
assert_eq "$(calls)" "0"

echo ok
