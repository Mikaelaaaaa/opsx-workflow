#!/usr/bin/env bash
# 讓一題情境在獨立的 claude -p session 裡跑，看不到本 repo、題目、答案與使用者層設定。
# 用法：run-candidate.sh <skill> <eval-id> <new|old> <results-dir>
# 在 sandbox 外的終端機跑，認證用平常的登入。--setting-sources project,local 讓 user 層的 plugin、skill、hooks 不載入。
# 工作 repo 建在 $TMPDIR 底下、跑完留著給 grader 看；transcript 複製到 <results-dir>/<session id>.jsonl。
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
skill="${1:?usage: run-candidate.sh <skill> <eval-id> <new|old> <results-dir>}"
eval_id="${2:?eval-id}"
variant="${3:?new|old}"
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
parent="$(mktemp -d "${TMPDIR:-/tmp}/run.XXXXXX")"
work="$(cd "$parent" && pwd -P)/$fixture"
if echo "$work" | grep -Eiq "$banned"; then
  rm -rf "$parent"
  echo "work repo path carries claude or a banned word, refusing: $work (set TMPDIR to a neutral directory)" >&2
  exit 2
fi
for p in "$root" "$results"; do
  case "$work/" in "$p"/*) rm -rf "$parent"; echo "work repo $work is under $p, refusing" >&2; exit 2 ;; esac
done

bash "$root/evals/prepare-run.sh" "$skill" "$fixture" "$variant" "$work" >/dev/null

settings="$(mktemp "${TMPDIR:-/tmp}/settings.XXXXXX")"
trap 'rm -f "$settings"' EXIT
# 寫入範圍由 sandbox 的預設限在 cwd（工作 repo）；不給 additionalDirectories，也不留 dangerouslyDisableSandbox 的出口
printf '%s' '{"sandbox": {"enabled": true, "autoAllowBashIfSandboxed": true, "allowUnsandboxedCommands": false}}' > "$settings"

id="$(uuidgen | tr 'A-Z' 'a-z')"
flags=(--setting-sources project,local --settings "$settings" --permission-mode acceptEdits --allowedTools Bash)
(cd "$work" && claude -p "$prompt" --session-id "$id" "${flags[@]}")
if [ -n "$second" ]; then
  (cd "$work" && claude -p "$second" --resume "$id" "${flags[@]}")
fi

src="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(echo "$work" | sed 's/[^a-zA-Z0-9]/-/g')/$id.jsonl"
[ -f "$src" ] || { echo "transcript not found at $src" >&2; exit 1; }
cp "$src" "$results/$id.jsonl"
echo "work: $work"
echo "session: $id"
echo "transcript: $results/$id.jsonl"
