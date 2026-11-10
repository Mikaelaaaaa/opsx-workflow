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
# 指令骨架：只留真的會執行的部分（引號字串、heredoc 本體不算；bash -c、eval、$(…) 內的算）。比對指令用它，不要對原始字串 grep。
cmd_skeleton() { printf '%s' "$1" | perl "$OPSX_ROOT/hooks/cmd-skeleton.pl"; }
# 第三級比對用的文字：原文，只扣掉 commit 訊息、opsx answer 答案、寫檔 heredoc 三種容器的資料部分。認不得的寫法都留著。
cmd_l3text() { printf '%s' "$1" | perl "$OPSX_ROOT/hooks/cmd-containers.pl"; }
hook_event() { jqr '.hook_event_name'; }

# 主 repo 的根（linked worktree 裡也回主 repo：卡在主 repo 的 openspec/，dispatch.json 的 key 是主 repo 名）
repo_top() {
  local common; common="$(git -C "$(hook_cwd)" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 0
  ( cd "$(dirname "$common")" && pwd -P )
}
repo_name() { basename "$(repo_top)"; }
branch() { git -C "$(hook_cwd)" rev-parse --abbrev-ref HEAD 2>/dev/null || true; }
# dispatch 開的 worktree 根是 <top>/.claude/worktrees/<名>，名是派工時的 slug 或 feature 名；不在那種 worktree 裡印空
wt_name() {
  local t w; t="$(repo_top)"
  w="$(git -C "$(hook_cwd)" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$t" ] && [ -n "$w" ] && w="$(cd "$w" && pwd -P)" && [ "${w%/*}" = "$t/.claude/worktrees" ] && printf '%s' "${w##*/}"
  true
}
# branch 對得到卡就用 branch：feature session 的 worktree 用 feature 名，同一個 worktree 會切換多個主 change 的 branch。
# branch 對不到卡（PR 名 ≠ 卡名）才用 worktree 名。
card_slug() {
  local t s w; t="$(repo_top)"
  s="$(branch)"; case "$s" in */*/*) s="$(printf '%s' "$s" | cut -d/ -f2)" ;; *) s='' ;; esac
  [ -n "$t" ] && [ -n "$s" ] && [ -d "$(st_card_dir "$t" "$s")" ] && { printf '%s' "$s"; return 0; }
  w="$(wt_name)"
  [ -n "$w" ] && [ -d "$(st_card_dir "$t" "$w")" ] && { printf '%s' "$w"; return 0; }
  printf '%s' "$s"
}
card_dir() { local t s d; t="$(repo_top)"; s="$(card_slug)"; [ -n "$t" ] && [ -n "$s" ] && d="$(st_card_dir "$t" "$s")" && [ -d "$d" ] && printf '%s' "$d" || printf ''; }
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

# grants：grants.toml [repos."<repo>"] <action> = true（這個 repo 永遠）、受保護位置（bin/lib/authz.py）這張卡的 grants 含 action（這張卡）、
# 或受保護位置這張卡的 once 含 action（這次：用掉就刪；不記的話 agent 重試還是被 deny，等於沒答）。
# dispatch.json 的 grants / once 沙盒內寫得到，一律不看。grants.toml 壞掉時當成沒授權，不放行。
has_grant() { # <repo> <slug> <action>：0 有授權、3 沒授權，其他值是 python 本身失敗
  OPSX_REPO="$1" OPSX_SLUG="$2" OPSX_ACTION="$3" OPSX_SD="$OPSX_STATE_DIR" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - <<'PY'
import os, sys, tomllib
sys.path.insert(0, os.environ["OPSX_LIB"]); import authz
sd = os.environ["OPSX_SD"]; repo = os.environ["OPSX_REPO"]; slug = os.environ["OPSX_SLUG"]; act = os.environ["OPSX_ACTION"]
key = "%s/%s" % (repo, slug)
try:
    g = tomllib.load(open(os.path.join(sd, "grants.toml"), "rb")).get("repos", {}).get(repo, {})
    if g.get(act) is True: sys.exit(0)
except FileNotFoundError:
    pass
except tomllib.TOMLDecodeError as e:
    print("opsx: grants.toml 壞了（%s），當成沒授權" % e, file=sys.stderr)
card = authz.load(sd).get(key, {})
if act in card.get("grants", []): sys.exit(0)
if act not in card.get("once", []): sys.exit(3)
consumed = {"ok": False}
def consume(d):
    once = d.get(key, {}).get("once", [])
    if act in once:
        once.remove(act); consumed["ok"] = True
authz.update(sd, consume)
sys.exit(0 if consumed["ok"] else 3)
PY
}
# repo 有沒有 autopilot / drive 的卡：0 有、1 沒有（含沒有 dispatch.json）、其他值是 dispatch.json 讀不了
repo_has_live_card() { # <repo>
  local f="$OPSX_STATE_DIR/dispatch.json"
  [ -f "$f" ] || return 1
  jq -e --arg p "$1/" 'any(to_entries[]; (.key | startswith($p)) and (.value | type == "object") and (.value.mode == "autopilot" or .value.mode == "drive"))' "$f" >/dev/null 2>&1
}
# 用 jq 不用 python：python 沒記或壞掉時，閘門仍要分得出哪些卡歸它管。
card_mode() { # <repo> <slug>：印 interactive、autopilot、drive、stopped，沒派過就空；dispatch.json 不是合法 JSON 時回非 0
  local f="$OPSX_STATE_DIR/dispatch.json"
  [ -f "$f" ] || return 0
  jq -r --arg k "$1/$2" '.[$k].mode // empty' "$f" 2>/dev/null
}
