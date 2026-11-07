#!/usr/bin/env bash
# evals/run-candidate.sh：候選者在系統 temp 的中性工作 repo 裡另開 claude --bare -p session，transcript 進結果目錄。
# 用假 claude（tests/fakes/claude）看外部行為：cwd、旗標、--settings 內容、第二輪 id、結果目錄。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes claude
runner="$OPSX_ROOT/evals/run-candidate.sh"
banned='claude|eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena'

# 工作 repo 的父目錄要在不含禁用字的 temp 底下。沙盒裡的 $TMPDIR 本身含 claude，/tmp 又不可寫，才退到 ~/.local/state/opsx
NT=""
for base in "$TMPDIR" /tmp "$HOME/.local/state/opsx"; do
  d="$(mktemp -d "$base/run.XXXXXX" 2>/dev/null)" || continue
  if (cd "$d" && pwd -P) | grep -Eiq "$banned"; then rm -rf "$d"; continue; fi
  NT="$(cd "$d" && pwd -P)"; break
done
[ -n "$NT" ] || fail "no writable temp dir without a banned word"
trap 'rm -rf "$FX" "$NT"' EXIT

export CLAUDE_CONFIG_DIR="$FX/cfg"
export OPSX_FAKE_LOG="$FX/calls.jsonl"
key="sk-ant-fake-9f3c2e71d0"

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

# 沒有 API key 就拒跑：建 repo、呼叫 claude 之前就退出
res="$FX/results-nokey"
( unset ANTHROPIC_API_KEY OPSX_API_KEY_HELPER; run nokey grill 1 new "$res" ) && fail "runner without a key should exit non-zero"
assert_grep "ANTHROPIC_API_KEY" "$FX/nokey.err"
assert_eq "$(calls)" "0" "claude must not run without a key"
assert_eq "$(find "$NT" -mindepth 1 | head -1)" "" "no work repo may be created without a key"

export ANTHROPIC_API_KEY="$key"
unset OPSX_API_KEY_HELPER

# 單輪題（grill 1 empty-pending-stops）：只跑一次，帶 --bare / --session-id / --settings，prompt 逐字相同
res="$FX/results-single"
run single grill 1 new "$res" || fail "single-turn run failed: $(cat "$FX/single.err")"
work="$(field work "$FX/single.out")"; id="$(field session "$FX/single.out")"; tr="$(field transcript "$FX/single.out")"
[ -n "$work" ] && [ -n "$id" ] && [ -n "$tr" ] || fail "runner must print work / session / transcript: $(cat "$FX/single.out")"
assert_eq "$(calls)" "1" "single-turn question calls claude once"
assert_eq "$(call_py 0 "c['cwd']")" "$work" "claude runs inside the work repo"
assert_eq "$(call_py 0 "'--bare' in c['argv'] and '-p' in c['argv']")" "True" "claude needs --bare -p"
assert_eq "$(arg_after 0 --session-id)" "$id"
echo "$id" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || fail "session id must be a lowercase uuid, got $id"
assert_eq "$(arg_after 0 -p)" "$(prompt_of grill 1 prompt)" "prompt must equal evals.json verbatim"
assert_eq "$(call_py 0 "'--resume' in c['argv']")" "False"

# 工作 repo：git repo，在 temp 底下，不在本 repo、題目目錄、結果目錄底下，路徑不含禁用字，專案名是 fixture 名
git -C "$work" rev-parse --git-dir >/dev/null 2>&1 || fail "work dir $work is not a git repo"
case "$work" in "$NT"/*) ;; *) fail "work repo $work is not under the system temp dir $NT" ;; esac
for p in "$OPSX_ROOT" "$OPSX_ROOT/skills/grill/evals/fixtures/empty-pending" "$(cd "$res" && pwd -P)"; do
  case "$work/" in "$p"/*) fail "work repo $work is under $p" ;; esac
done
! echo "$work" | grep -Eiq "$banned" || fail "work path carries a banned word: $work"
assert_eq "$(basename "$work")" "empty-pending" "project name is the fixture name"
assert_file "$work/.claude/skills/grill/SKILL.md"

# --settings：開 sandbox、不留沒 sandbox 的後門、不多給可寫目錄；跑完 settings 檔刪掉
assert_eq "$(call_py 0 "c['settings']['sandbox']['enabled']")" "True" "settings must enable the sandbox"
assert_eq "$(call_py 0 "c['settings']['sandbox']['allowUnsandboxedCommands']")" "False"
assert_eq "$(call_py 0 "'additionalDirectories' in c['settings'].get('permissions', {})")" "False" "no write dir beyond the work repo"
settings_path="$(arg_after 0 --settings)"
assert_no_file "$settings_path"
case "$settings_path" in "$work"/*|"$res"/*) fail "settings file must live outside the work repo and results dir" ;; esac

# transcript 進結果目錄，跟 session 的那份一樣
assert_eq "$tr" "$(cd "$res" && pwd -P)/$id.jsonl"
src="$CLAUDE_CONFIG_DIR/projects/$(echo "$work" | sed 's/[^a-zA-Z0-9]/-/g')/$id.jsonl"
assert_file "$tr"
cmp -s "$src" "$tr" || fail "results transcript differs from the session transcript"

# key 不落地：工作 repo、結果目錄都沒有 key 的值
! grep -rqF "$key" "$work" "$res" || fail "API key landed in the work repo or results dir"

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
assert_eq "$(call_py 1 "'--bare' in c['argv'] and c['settings']['sandbox']['enabled']")" "True" "second turn keeps --bare and the sandbox"
assert_eq "$(call_py 1 "c['cwd']")" "$(field work "$FX/two.out")"
assert_eq "$(wc -l < "$tr" | tr -d ' ')" "2" "results transcript holds both turns"

# apiKeyHelper：沒有 ANTHROPIC_API_KEY 也能跑，helper 進 --settings
res="$FX/results-helper"
( unset ANTHROPIC_API_KEY; export OPSX_API_KEY_HELPER="security find-generic-password -w -s anthropic"; run helper grill 1 new "$res" ) \
  || fail "run with only OPSX_API_KEY_HELPER failed: $(cat "$FX/helper.err")"
assert_eq "$(call_py 0 "c['settings']['apiKeyHelper']")" "security find-generic-password -w -s anthropic"

# 路徑含 claude 或禁用字：拒跑、印出路徑、沒呼叫 claude
mkdir -p "$NT/claude-tmp"
res="$FX/results-banned"
: > "$OPSX_FAKE_LOG"
TMPDIR="$NT/claude-tmp" bash "$runner" grill 1 new "$res" >"$FX/banned.out" 2>"$FX/banned.err" && fail "runner must refuse a work path with claude in it"
assert_grep "$NT/claude-tmp" "$FX/banned.err"
assert_eq "$(calls)" "0"

echo ok
