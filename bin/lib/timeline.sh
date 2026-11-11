#!/usr/bin/env bash
# opsx timeline [--root ~/code] [--state <dir>] [--since <iso>]：跨卡時間軸，印一份 JSON，不寫檔。
# 輸出 {generated_at, last_seen, events[], errors[]}，events 由新到舊；同一秒的列，檔案裡後寫的在前。
# 每個 event：{ts, repo, slug, archived, who, tag, text, evidence, source}。specs/opsx-log/spec.md「時間軸」。
# 另讀 <state>/sync.log，一列一個 source: sync 事件（evidence 是來源名，new 是新卡數）。
# 讀全部 archive，不套 collect 的張數上限。不是五欄新格式的列 tag 記「其他」、text 是整列原文。
# repo 的判準跟 collect 一樣：<root>/<name>/openspec/changes 存在，而且 <name>/.git 是目錄。

opsx_timeline() {
  local root="${OPSX_CODE_ROOT:-$HOME/code}" state="$OPSX_STATE_DIR" since=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) root="$2"; shift 2 ;;
      --state) state="$2"; shift 2 ;;
      --since) since="$2"; shift 2 ;;
      *) die "timeline: 不認得的參數 $1" ;;
    esac
  done
  [ -d "$root" ] || die "timeline: --root 不是目錄：$root"
  OPSX_T_ROOT="$root" OPSX_T_STATE="$state" OPSX_T_SINCE="$since" OPSX_T_NOW="$(now_iso)" "$OPSX_PY" -I - <<'PY'
import datetime, json, operator, os, pathlib, re, sys

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
    print("opsx: timeline: --since 要是帶時區的 ISO 8601：%s" % env["OPSX_T_SINCE"], file=sys.stderr)
    sys.exit(2)

events, errors = [], []
EPOCH = datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)

def card_events(repo, path, slug, archived):
    try:
        lines = path.read_text(encoding="utf-8").split("\n")
    except (OSError, UnicodeDecodeError) as e:
        errors.append({"source": str(path), "message": str(e)}); return
    for i, line in enumerate(lines):
        if not line.strip() or line.startswith("ts\tphase\t"):
            continue
        cols = line.split("\t")
        t = when(cols[0])
        base = {"repo": repo, "slug": slug, "archived": archived, "source": "decisions"}
        if len(cols) == 5 and cols[2] in TAGS and t is not None:
            e = {"ts": cols[0], "who": cols[1], "tag": cols[2], "text": cols[3], "evidence": cols[4], **base}
        else:
            # 舊格式的列照原文放，不猜 who / tag
            e = {"ts": cols[0] if t is not None else None, "who": None, "tag": "其他", "text": line, "evidence": "", **base}
        # 沒有時間的列排在所有有時間的列之後
        events.append(((t is not None, t or EPOCH, str(path), i), e))

for repo_dir in sorted(p for p in root.iterdir() if (p / "openspec" / "changes").is_dir() and (p / ".git").is_dir()):
    changes = repo_dir / "openspec" / "changes"
    for f in sorted(changes.glob("*/decisions.tsv")):
        if f.parent.name != "archive":
            card_events(repo_dir.name, f, f.parent.name, False)
    for f in sorted(changes.glob("archive/*/decisions.tsv")):
        card_events(repo_dir.name, f, re.sub(r"^\d{4}-\d{2}-\d{2}-", "", f.parent.name), True)

sync_path = state / "sync.log"
if sync_path.is_file():
    try:
        sync_lines = sync_path.read_text(encoding="utf-8").split("\n")
    except (OSError, UnicodeDecodeError) as e:
        errors.append({"source": str(sync_path), "message": str(e)}); sync_lines = []
    for i, line in enumerate(sync_lines):
        cols = line.split("\t")
        t = when(cols[0])
        if len(cols) != 4 or t is None or not cols[2].isdigit():
            if line.strip():
                errors.append({"source": "%s:%d" % (sync_path, i + 1), "message": "不是 ts · source · 新卡數 · 文字：%s" % line})
            continue
        events.append(((True, t, str(sync_path), i), {"ts": cols[0], "repo": None, "slug": None, "archived": False, "who": "系統",
                       "tag": "同步", "text": cols[3], "evidence": cols[1], "new": int(cols[2]), "source": "sync"}))

if since is not None:
    events = [e for e in events if e[0][0] and e[0][1] > since]
events.sort(key=operator.itemgetter(0), reverse=True)
seen = state / "last-seen"
print(json.dumps({"generated_at": env["OPSX_T_NOW"], "last_seen": seen.read_text().strip() if seen.is_file() else None,
                  "events": [e[1] for e in events], "errors": errors}, ensure_ascii=False))
PY
}
