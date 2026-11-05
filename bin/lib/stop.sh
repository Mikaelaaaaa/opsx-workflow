#!/usr/bin/env bash
# opsx stop <slug> [--repo <top>]：板上的「停止」。kill drive 迴圈、關掉 pane、dispatch.json 標 stopped。
# worktree 和 branch 留著（重派會重用）。

opsx_stop() {
  local slug="" top=""
  while [ $# -gt 0 ]; do
    case "$1" in --repo) top="$2"; shift 2 ;; *) [ -z "$slug" ] && slug="$1" || die "stop: 多餘的參數 $1"; shift ;; esac
  done
  [ -n "$slug" ] || die "stop: 要給 slug"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "stop: 不在 git repo 裡，或給 --repo"
  local repo; repo="$(basename "$(cd "$top" && pwd -P)")"
  local f="$OPSX_STATE_DIR/dispatch.json"
  [ -f "$f" ] || die "stop: 沒有 dispatch.json"
  local entry; entry="$(OPSX_KEY="$repo/$slug" python3 -I -c 'import json,os,sys;d=json.load(open(sys.argv[1]));print(json.dumps(d.get(os.environ["OPSX_KEY"],{})))' "$f")"
  [ "$entry" != "{}" ] || die "stop: $repo/$slug 沒派過"
  local pid pane; pid="$(printf '%s' "$entry" | jq -r '.drive_pid // empty')"; pane="$(printf '%s' "$entry" | jq -r '.pane // empty')"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; say "stop: drive pid $pid 已 kill"; fi
  if [ -n "$pane" ]; then herdr pane close "$pane" >/dev/null 2>&1 && say "stop: pane $pane 關了" || say "stop: pane $pane 關不掉（可能已經不在）"; fi
  OPSX_KEY="$repo/$slug" OPSX_AT="$(now_iso)" python3 -I - "$f" <<'PY'
import json,os,sys
p=sys.argv[1]; d=json.load(open(p)); e=d[os.environ["OPSX_KEY"]]; e["mode"]="stopped"; e["drive_pid"]=None; e["stopped_at"]=os.environ["OPSX_AT"]
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PY
  printf '%s\t%s\t%s\n' "$(now_iso)" "停止" "stopped" >> "$top/openspec/changes/$slug/decisions.tsv"
  say "stop: $repo/$slug 標 stopped"
}
