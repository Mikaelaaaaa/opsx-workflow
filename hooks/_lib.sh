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

jqr() { printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty" 2>/dev/null || true; }
hook_cmd()  { jqr '.tool_input.command'; }
hook_tool() { jqr '.tool_name'; }
hook_file() { jqr '.tool_input.file_path'; }
hook_cwd()  { local c; c="$(jqr '.cwd')"; printf '%s' "${c:-$PWD}"; }
hook_prompt() { jqr '.prompt'; }
hook_event() { jqr '.hook_event_name'; }

repo_top() { git -C "$(hook_cwd)" rev-parse --show-toplevel 2>/dev/null || true; }
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

# grants：grants.toml [repos."<repo>"] <action> = true，或 dispatch.json 這張卡的 grants 含 action
has_grant() { # <repo> <slug> <action>
  OPSX_REPO="$1" OPSX_SLUG="$2" OPSX_ACTION="$3" OPSX_SD="$OPSX_STATE_DIR" python3 -I - <<'PY'
import os,sys,json,tomllib
sd=os.environ["OPSX_SD"]; repo=os.environ["OPSX_REPO"]; slug=os.environ["OPSX_SLUG"]; act=os.environ["OPSX_ACTION"]
try:
    g=tomllib.load(open(os.path.join(sd,"grants.toml"),"rb")).get("repos",{}).get(repo,{})
    if g.get(act) is True: sys.exit(0)
except FileNotFoundError: pass
try:
    d=json.load(open(os.path.join(sd,"dispatch.json")))
    if act in d.get(f"{repo}/{slug}",{}).get("grants",[]): sys.exit(0)
except (FileNotFoundError,json.JSONDecodeError): pass
sys.exit(1)
PY
}
card_mode() { # <repo> <slug> → interactive|autopilot|drive|""
  OPSX_REPO="$1" OPSX_SLUG="$2" OPSX_SD="$OPSX_STATE_DIR" python3 -I - <<'PY'
import os,sys,json
try: print(json.load(open(os.path.join(os.environ["OPSX_SD"],"dispatch.json"))).get(f'{os.environ["OPSX_REPO"]}/{os.environ["OPSX_SLUG"]}',{}).get("mode",""))
except (FileNotFoundError,json.JSONDecodeError): print("")
PY
}
