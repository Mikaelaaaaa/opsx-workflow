#!/usr/bin/env bash
# hooks 共用。每支 hook 先 source 這個。讀 stdin 的 hook JSON，提供：
#   HOOK_INPUT · hook_cmd · hook_cwd · hook_tool · hook_file · repo_top · card_slug · card_dir · card_stage · deny · ctx
# 狀態判斷在 bin/lib/stage.sh（跟 drive.sh 共用）。要求檔 §8.5。
set -euo pipefail
HOOK_INPUT="$(cat)"
OPSX_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OPSX_STATE_DIR="${OPSX_STATE_DIR:-$HOME/.local/state/opsx}"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/stage.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/python.sh"
opsx_python_load || true   # 沒有 python 的 hook（router 等）照跑；grant-gate 自己處理 OPSX_PY 為空

jqr() { printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty" 2>/dev/null || true; }
hook_cmd()  { jqr '.tool_input.command'; }
hook_tool() { jqr '.tool_name'; }
hook_file() { jqr '.tool_input.file_path'; }
hook_cwd()  { local c; c="$(jqr '.cwd')"; printf '%s' "${c:-$PWD}"; }
hook_prompt() { jqr '.prompt'; }
hook_event() { jqr '.hook_event_name'; }

# 主 repo 的根（linked worktree 裡也回主 repo：卡在主 repo 的 openspec/，dispatch.json 的 key 是主 repo 名）
repo_top() {
  local common; common="$(git -C "$(hook_cwd)" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 0
  ( cd "$(dirname "$common")" && pwd -P )
}
repo_name() { basename "$(repo_top)"; }
branch() { git -C "$(hook_cwd)" rev-parse --abbrev-ref HEAD 2>/dev/null || true; }
card_slug() { local b; b="$(branch)"; case "$b" in */*/*) printf '%s' "$b" | cut -d/ -f2 ;; *) printf '' ;; esac; }
card_dir() { local t s; t="$(repo_top)"; s="$(card_slug)"; [ -n "$t" ] && [ -n "$s" ] && [ -d "$t/openspec/changes/$s" ] && printf '%s' "$t/openspec/changes/$s" || printf ''; }
card_kind() { st_card_kind "$1"; }
status_tests() { st_status_tests "$1"; }
tasks_open() { st_tasks_open "$1"; }
tasks_done() { st_tasks_done "$1"; }
card_stage() { stage_of "$(repo_top)" "$(card_slug)"; }

deny() { # PreToolUse deny
  jq -n --arg reason "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}
ctx() { # 注入一段 context（PreToolUse / UserPromptSubmit / SessionStart 都吃 additionalContext）
  jq -n --arg ev "$1" --arg text "$2" '{hookSpecificOutput:{hookEventName:$ev,additionalContext:$text}}'
}
stop_block() { jq -n --arg reason "$1" '{decision:"block",reason:$reason}'; exit 0; }

# grants：grants.toml [repos."<repo>"] <action> = true（這個 repo 永遠）、dispatch.json 這張卡的 grants 含 action（這張卡）、
# 或 dispatch.json 這張卡的 once 含 action（這次：用掉就刪；不記的話 agent 重試還是被 deny，等於沒答）。
# grants.toml 壞掉時當成沒授權，不放行。
has_grant() { # <repo> <slug> <action>
  OPSX_REPO="$1" OPSX_SLUG="$2" OPSX_ACTION="$3" OPSX_SD="$OPSX_STATE_DIR" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - <<'PY'
import os, sys, tomllib
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
sd = os.environ["OPSX_SD"]; repo = os.environ["OPSX_REPO"]; slug = os.environ["OPSX_SLUG"]; act = os.environ["OPSX_ACTION"]
key = "%s/%s" % (repo, slug)
try:
    g = tomllib.load(open(os.path.join(sd, "grants.toml"), "rb")).get("repos", {}).get(repo, {})
    if g.get(act) is True: sys.exit(0)
except FileNotFoundError:
    pass
except tomllib.TOMLDecodeError as e:
    print("opsx: grants.toml 壞了（%s），當成沒授權" % e, file=sys.stderr)
p = os.path.join(sd, "dispatch.json")
card = jsonfile.load(p).get(key, {})
if act in card.get("grants", []): sys.exit(0)
if act not in card.get("once", []): sys.exit(1)
consumed = {"ok": False}
def consume(d):
    once = d.get(key, {}).get("once", [])
    if act in once:
        once.remove(act); consumed["ok"] = True
jsonfile.update(p, consume)
sys.exit(0 if consumed["ok"] else 1)
PY
}
card_mode() { # <repo> <slug>：印 interactive、autopilot、drive、stopped，沒派過就空
  OPSX_REPO="$1" OPSX_SLUG="$2" OPSX_SD="$OPSX_STATE_DIR" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
print(jsonfile.load(os.path.join(os.environ["OPSX_SD"], "dispatch.json")).get("%s/%s" % (os.environ["OPSX_REPO"], os.environ["OPSX_SLUG"]), {}).get("mode", ""))
PY
}
