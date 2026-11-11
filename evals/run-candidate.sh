#!/usr/bin/env bash
# 讓一題情境在獨立的 claude -p session 裡跑，看不到本 repo、題目、答案與使用者層設定。
# 用法：run-candidate.sh <skill> <eval-id> <new|old|without> <results-dir>
# 在 sandbox 外的終端機跑，認證用平常的登入。--setting-sources project,local 讓 user 層的 plugin、skill、hooks 不載入。
# 工作 repo 建在 $TMPDIR 底下；跑完（含 claude 失敗）搬到 <results-dir>/<session id>/<fixture> 給 grader 看，transcript 複製到 <results-dir>/<session id>.jsonl。
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
skill="${1:?usage: run-candidate.sh <skill> <eval-id> <new|old|without> <results-dir>}"
eval_id="${2:?eval-id}"
variant="${3:?new|old|without}"
results="${4:?results-dir}"
banned='claude|eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena'

evals="$root/skills/$skill/evals/evals.json"
field() { # field <fixture|prompt|second_turn>：evals.json 這一題的欄位；沒有 second_turn 印空字串，表示單輪題
  python3 -I -c '
import json, os, sys
e = next(x for x in json.load(open(sys.argv[1]))["evals"] if x["id"] == int(sys.argv[2]))
print(os.path.basename(e["files"][0]) if sys.argv[3] == "fixture" else e.get(sys.argv[3], ""))' "$evals" "$eval_id" "$1"
}
fixture="$(field fixture)"
prompt="$(field prompt)"
second="$(field second_turn)"

mkdir -p "$results"
results="$(cd "$results" && pwd -P)"
settings=""
id=""

finish() { # EXIT trap：不論怎麼結束都清掉 temp 裡的父目錄；claude 跑過就把 transcript 與工作 repo 留進結果目錄、印出位置。退出碼沿用進來時的
  local rc=$? src
  rm -f "$settings"
  if [ -z "$id" ]; then
    rm -rf "$parent"
    exit "$rc"
  fi
  src="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(echo "$work" | sed 's/[^a-zA-Z0-9]/-/g')/$id.jsonl"
  if [ -f "$src" ]; then
    cp "$src" "$results/$id.jsonl"
  else
    echo "transcript not found at $src" >&2
    [ "$rc" -ne 0 ] || rc=1
  fi
  mkdir -p "$results/$id"
  mv "$work" "$results/$id/$fixture"
  rm -rf "$parent"
  echo "work: $results/$id/$fixture"
  echo "session: $id"
  [ ! -f "$results/$id.jsonl" ] || echo "transcript: $results/$id.jsonl"
  exit "$rc"
}

parent="$(mktemp -d "${TMPDIR:-/tmp}/run.XXXXXX")"
trap finish EXIT
work="$(cd "$parent" && pwd -P)/$fixture"
tmp="$(cd "$(dirname "$parent")" && pwd -P)"
for p in "$root" "$results"; do
  case "$work/" in "$p"/*) echo "work repo $work is under $p, refusing" >&2; exit 2 ;; esac
done
# 結果目錄在 temp 底下，候選者 ls ../.. 就看得到搬進去的前幾次工作 repo 與 transcript
case "$results/" in "$tmp"/*) echo "results dir $results is inside $tmp, refusing (the candidate can list it with ls ../..)" >&2; exit 2 ;; esac
# Claude Code 會往上載入每一層的 CLAUDE.md；上層有這些，候選者一開 session 就看得到
d="$work"
while [ "$d" != "/" ]; do
  d="$(dirname "$d")"
  for m in CLAUDE.md .claude; do
    [ -e "$d/$m" ] || continue
    echo "work repo $work has $d/$m above it, refusing (set TMPDIR to a directory with no CLAUDE.md or .claude above it)" >&2
    exit 2
  done
done
if echo "$work" | grep -Eiq "$banned"; then
  echo "work repo path carries claude or a banned word, refusing: $work (set TMPDIR to a directory whose path has no such word and with no CLAUDE.md or .claude above it)" >&2
  exit 2
fi

bash "$root/evals/prepare-run.sh" "$skill" "$fixture" "$variant" "$work" >/dev/null

settings="$(mktemp "${TMPDIR:-/tmp}/settings.XXXXXX")"
# 寫入範圍由 sandbox 的預設限在 cwd（工作 repo）；不給 additionalDirectories，也不留 dangerouslyDisableSandbox 的出口。
# /tmp/claude 是 CLI 預設可寫的共用目錄，候選者能留東西給下一次執行讀，所以明列不可寫（macOS 的 /tmp 連到 /private/tmp，兩個都列）
printf '%s' '{"sandbox": {"enabled": true, "autoAllowBashIfSandboxed": true, "allowUnsandboxedCommands": false, "filesystem": {"denyWrite": ["/tmp/claude", "/private/tmp/claude"]}}}' > "$settings"

id="$(uuidgen | tr 'A-Z' 'a-z')"
echo "starting: session=$id work=$work"
flags=(--setting-sources project,local --settings "$settings" --permission-mode acceptEdits --allowedTools Bash)
(cd "$work" && claude -p "$prompt" --session-id "$id" "${flags[@]}")
if [ -n "$second" ]; then
  (cd "$work" && claude -p "$second" --resume "$id" "${flags[@]}")
fi
