#!/usr/bin/env bash
# opsx timeline [--root ~/code] [--state <dir>] [--since <iso>]：跨卡時間軸，印一份 JSON，不寫檔。
# 輸出 {generated_at, last_seen, events[], errors[]}，events 由新到舊；同一秒的列，檔案裡後寫的在前。
# 每個 event：{ts, repo, slug, archived, who, tag, text, evidence, source}。specs/opsx-log/spec.md「時間軸」。
# repo 的判準跟 collect 一樣：<root>/<name>/openspec/changes 存在，而且 <name>/.git 是目錄。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/log.sh"

opsx_timeline() {
  local root="$HOME/code" state="$OPSX_STATE_DIR" since=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) root="$2"; shift 2 ;;
      --state) state="$2"; shift 2 ;;
      --since) since="$2"; shift 2 ;;
      *) die "timeline: 不認得的參數 $1" ;;
    esac
  done
  [ -d "$root" ] || die "timeline: --root 不是目錄：$root"
  OPSX_T_ROOT="$root" OPSX_T_STATE="$state" OPSX_T_SINCE="$since" OPSX_T_NOW="$(now_iso)" python3 -I - <<'PY'
import datetime, json, operator, os, pathlib, sys

env = os.environ
TAGS = set(env["OPSX_TAGS"].split())
root, state = pathlib.Path(env["OPSX_T_ROOT"]), pathlib.Path(env["OPSX_T_STATE"])

def when(ts):
    try:
        t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None
    return t if t.tzinfo else None

since = when(env["OPSX_T_SINCE"]) if env["OPSX_T_SINCE"] else None
if env["OPSX_T_SINCE"] and since is None:
    sys.exit("opsx: timeline: --since 要是帶時區的 ISO 8601：%s" % env["OPSX_T_SINCE"])

events, errors = [], []

def card_events(repo, path, slug, archived):
    try:
        lines = path.read_text(encoding="utf-8").split("\n")
    except (OSError, UnicodeDecodeError) as e:
        errors.append({"source": str(path), "message": str(e)}); return
    for i, line in enumerate(lines):
        cols = line.split("\t")
        if len(cols) != 5 or cols[2] not in TAGS or when(cols[0]) is None:
            continue
        events.append(((when(cols[0]), str(path), i), {"ts": cols[0], "repo": repo, "slug": slug, "archived": archived,
                       "who": cols[1], "tag": cols[2], "text": cols[3], "evidence": cols[4], "source": "decisions"}))

for repo_dir in sorted(p for p in root.iterdir() if (p / "openspec" / "changes").is_dir() and (p / ".git").is_dir()):
    changes = repo_dir / "openspec" / "changes"
    for f in sorted(changes.glob("*/decisions.tsv")):
        if f.parent.name != "archive":
            card_events(repo_dir.name, f, f.parent.name, False)

if since is not None:
    events = [e for e in events if e[0][0] > since]
events.sort(key=operator.itemgetter(0), reverse=True)
seen = state / "last-seen"
print(json.dumps({"generated_at": env["OPSX_T_NOW"], "last_seen": seen.read_text().strip() if seen.is_file() else None,
                  "events": [e[1] for e in events], "errors": errors}, ensure_ascii=False))
PY
}
