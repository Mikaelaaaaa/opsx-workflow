# 授權閘門測試共用的 fixture：autopilot 的卡 eval-core、repo 永遠授權 push、這張卡授權（PD/authz.json）可以改。
# 由 tests/grant-gate-*.test.sh source，不是測試檔本身（run.sh 只跑 *.test.sh）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

run_hook() { printf '%s' "$2" | bash "$H/$1" 2>"$FX/hook.err"; true; }
j() { python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name=sys.argv[2],tool_input=json.loads(sys.argv[3]),prompt="",hook_event_name="PreToolUse")))' "$1" "$2" "$3"; }
decision() { [ -z "$1" ] && { echo allow; return; }; printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // .decision // "allow"'; }
reason() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // .reason // ""'; }
cmdj() { printf '{"command":%s}' "$(printf '%s' "$1" | jq -Rs .)"; }

R="$(mk_repo Agentory-AI git@gitlab.tsg-navigator.com:agentory/Agentory-AI.git)"
mk_change "$R" eval-core
mkdir -p "$OPSX_STATE_DIR/settings"
PD="${OPSX_STATE_DIR}-protected"; mkdir -p "$PD"
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '[repos."Agentory-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
# dispatch 給這個 agent 的 settings：autopilot 直接做的那一級（bin/lib/launch.sh write_settings 的子集）
SETTINGS="$OPSX_STATE_DIR/settings/Agentory-AI-eval-core-autopilot.json"
printf '{"permissions":{"allow":["Read","Bash(git add:*)","Bash(git commit:*)","Bash(git merge:*)","Bash(git status:*)","Bash(git push:*)","Bash(cat:*)","Bash(git branch:*)"]}}' > "$SETTINGS"
card_grants() { printf '{"Agentory-AI/eval-core":{"grants":%s}}' "$1" > "$PD/authz.json"; }
card_grants '[]'
gg() { run_hook opsx-grant-gate.sh "$(j "${2:-$R}" Bash "$(cmdj "$1")")"; }
