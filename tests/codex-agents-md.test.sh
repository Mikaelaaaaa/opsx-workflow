#!/usr/bin/env bash
# codex-agents-md：規則單一來源（router 與 AGENTS.md 同源）、render_agents_md、dispatch codex 放 AGENTS.md。
# 驗收：specs/codex-agents-md/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"
source "$OPSX_ROOT/bin/lib/rules.sh"

# --- 1.1 router 輸出以 ` · ` 接 rule_autopilot / rule_interactive ---
R="$(mk_repo Agentory-AI git@gitlab.tsg-navigator.com:agentory/Agentory-AI.git)"
mkdir -p "$R/openspec/changes/eval-core" "$OPSX_STATE_DIR"
printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$R/openspec/changes/eval-core/.openspec.yaml"
git -C "$R" checkout -q -b feat/eval-core/mikaela
router() { # <mode> → additionalContext
  printf '{"Agentory-AI/eval-core":{"mode":"%s"}}' "$1" > "$OPSX_STATE_DIR/dispatch.json"
  python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],tool_name="",tool_input={},prompt="下一步",hook_event_name="UserPromptSubmit")))' "$R" \
    | bash "$OPSX_ROOT/hooks/openspec-router.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext'
}
ctx_auto="$(router autopilot)"
case "$ctx_auto" in *" · $(rule_autopilot)") ;; *) fail "router autopilot 要以 ' · ' 接 rule_autopilot: $ctx_auto" ;; esac
case "$(rule_autopilot)" in *'不用 AskUserQuestion'*'一個 Bash 呼叫做一件事'*) ;; *) fail "rule_autopilot 內容不對: $(rule_autopilot)" ;; esac
ctx_int="$(router interactive)"
case "$ctx_int" in *" · $(rule_interactive)") ;; *) fail "router interactive 要以 ' · ' 接 rule_interactive: $ctx_int" ;; esac

# --- 2.1 render_agents_md ---
source "$OPSX_ROOT/bin/lib/agents-md.sh"
has() { case "$1" in *"$2"*) ;; *) fail "${3:-內容}缺 [$2]" ;; esac; }
gone() { case "$1" in *"$2"*) fail "${3:-內容}不該有 [$2]" ;; esac; }
a="$(render_agents_md autopilot)"
# 規則的每一段（以 ' · ' 切開）都在檔裡：同源
while IFS= read -r seg; do has "$a" "$seg" "autopilot 規則段"; done < <(rule_autopilot | awk -F' · ' '{ for (i = 1; i <= NF; i++) print $i }')
for s in '主 checkout' 'bash tests/run.sh' 'gates.md' '一個 Bash 呼叫做一件事' 'waiting for merge' '直接做' '要授權' '永遠要人' 'merge' "$OPSX_ROOT/skills" '`/opsx-workflow:<stage> <slug>`'; do has "$a" "$s" autopilot; done
i="$(render_agents_md interactive)"
has "$i" "$(rule_interactive)" interactive
gone "$i" '要問人的事寫 gates.md' interactive
gone "$i" '不用 AskUserQuestion' interactive
gone "$a" 'interactive：要授權就直接問' autopilot
rc=0; render_agents_md yolo >/dev/null 2>&1 || rc=$?; assert_eq "$rc" 1 "不認得的模式要失敗"
render_agents_md yolo 2>&1 | grep -q 'yolo' || fail "錯誤訊息要點名模式 yolo"
for s in '直接做' '要授權' '永遠要人'; do has "$(cat "$OPSX_ROOT/references/grants.md")" "$s" grants.md; done
# 把 main 合進自己的分支是直接做；合 MR 才是永遠要人
has "$a" '不自己合 MR' autopilot
gone "$a" '不自己 merge，' autopilot
has "$(grep '^| \*\*直接做\*\*' "$OPSX_ROOT/references/grants.md")" 'git merge' "grants.md 直接做列"
has "$(grep '^| \*\*永遠要人\*\*' "$OPSX_ROOT/references/grants.md")" 'MR' "grants.md 永遠要人列"
# grant-outbound-speech：授權段寫明對外發話閘門不判，要自己先寫 gate
for s in '對客戶或外部人發話' '閘門不判' '沒被擋不代表可以做' '發話前自己寫 `type: approval` 的 gate'; do has "$a" "$s" "autopilot 的授權段"; done

# --- 3.1 / 3.2 / 4.1 dispatch codex ---
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
printf '#!/usr/bin/env bash\nexec bash "%s/herdr" "$@"\n' "$FAKES" > "$FX/fakebin/herdr"; chmod +x "$FX/fakebin/herdr"
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela
export OPSX_DRIVE_MAX=0
wait_drive() { # <repo> <slug>
  local f="$OPSX_STATE_DIR/drive-$1-$2.log" n=0
  until grep -q '跑滿 [01] 輪' "$f" 2>/dev/null; do n=$((n+1)); [ $n -lt 50 ] || fail "drive 沒在背景起來：$f"; sleep 0.1; done
}
D="$(mk_repo Agentory-CS git@gitlab.tsg-navigator.com:agentory/Agentory-CS.git)"
for c in cx cl; do
  mkdir -p "$D/openspec/changes/$c"; printf 'schema: opsx\ncreated: 2026-11-10\nkind: chore\n' > "$D/openspec/changes/$c/.openspec.yaml"
done
printf '[repos]\n"Agentory-CS" = "agnetory-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"
EXCL="$(git -C "$D" rev-parse --path-format=absolute --git-path info/exclude)"
cd "$D"

out="$(opsx dispatch cx --agent codex --mode autopilot --kind chore 2>&1)" || fail "dispatch codex autopilot: $out"
wait_drive Agentory-CS cx
WT="$D/.claude/worktrees/cx"
assert_file "$WT/AGENTS.md"
has "$(cat "$WT/AGENTS.md")" "$(rule_autopilot | awk -F' · ' '{ print $1 }')" "worktree 的 AGENTS.md"
assert_eq "$(git -C "$WT" status --porcelain)" "" "AGENTS.md 不進 git"
assert_grep "^agent start cx --kind codex --pane w1:pE -- -a never -s workspace-write --add-dir $D/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"

opsx stop cx >/dev/null 2>&1 || fail "stop cx"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch cx --agent codex --mode interactive 2>&1)" || fail "redispatch codex interactive: $out"
has "$(cat "$WT/AGENTS.md")" "$(rule_interactive)" "重派後的 AGENTS.md"
gone "$(cat "$WT/AGENTS.md")" '要問人的事寫 gates.md' "重派後的 AGENTS.md"
assert_eq "$(grep -cx '/AGENTS.md' "$EXCL")" 1 "info/exclude 的 /AGENTS.md 只該有一行"
assert_grep "^agent start cx --kind codex --pane w1:pE -- -a on-request -s workspace-write --add-dir $D/openspec --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"

out="$(opsx dispatch cl --agent claude --mode interactive 2>&1)" || fail "dispatch claude: $out"
assert_no_file "$D/.claude/worktrees/cl/AGENTS.md"

# repo 已有 tracked 的 AGENTS.md：原檔不動，寫 AGENTS.override.md
E="$(mk_repo Agentory-AI git@gitlab.tsg-navigator.com:agentory/Agentory-AI.git)"
printf 'repo-rule-xyz\n' > "$E/AGENTS.md"; git -C "$E" add AGENTS.md; git -C "$E" commit -q -m "add AGENTS.md"
mkdir -p "$E/openspec/changes/tr"; printf 'schema: opsx\ncreated: 2026-11-10\nkind: chore\n' > "$E/openspec/changes/tr/.openspec.yaml"
printf '[repos]\n"Agentory-CS" = "agnetory-ai"\n"Agentory-AI" = "agnetory-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"
cd "$E"
out="$(opsx dispatch tr --agent codex --mode interactive --kind chore 2>&1)" || fail "dispatch codex tracked AGENTS.md: $out"
TW="$E/.claude/worktrees/tr"
assert_eq "$(cat "$TW/AGENTS.md")" "repo-rule-xyz" "tracked 的 AGENTS.md 不能動"
has "$(cat "$TW/AGENTS.override.md")" 'repo-rule-xyz' override
has "$(cat "$TW/AGENTS.override.md")" "$(rule_interactive)" override
assert_eq "$(git -C "$TW" status --porcelain)" "" "override 不進 git"

# git dir 沒有 info/（自訂 template 的 repo）：exclude 要建得起來，AGENTS.md 不能留成會進 git 的檔
G="$(mk_repo NoInfo)"
rm -rf "$G/.git/info"
assert_rc 0 place_agents_md "$G" autopilot
assert_eq "$(git -C "$G" status --porcelain)" "" "沒有 info/ 時 AGENTS.md 也不進 git"
echo ok
