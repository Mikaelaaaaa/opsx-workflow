#!/usr/bin/env bash
# skills/apply/references/playbooks/eval.md：候選者在獨立 session 跑、從那一個 session 的 transcript 驗證。只證明文字寫在對的步驟；agent 守不守由 eval 驗。
# 驗收：openspec/changes/eval-playbook-runner/specs/apply-eval-playbook/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PB="$OPSX_ROOT/skills/apply/references/playbooks/eval.md"
assert_file "$PB"
has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
hasnt() { ! grep -qiF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }
step() { awk -v n="$1" 'index($0, n ". ")==1{on=1;print;next} /^[0-9]+\. /{on=0} /^\*\*Reply/{on=0} on' "$PB"; }
for n in 4 5 6; do step "$n" > "$FX/step$n"; [ -s "$FX/step$n" ] || fail "step $n missing"; done

# --- Scenario：候選者步驟不再用 subagent ---
for k in '--setting-sources project,local' '--session-id'; do has "$k" "$FX/step4"; done
hasnt 'general-purpose' "$FX/step4"
hasnt 'subagent' "$FX/step4"

# --- Scenario：情境題指向存在的 runner ---
runner="$(grep -oE 'evals/[A-Za-z0-9_-]+\.sh' "$FX/step4" | head -1)"
[ -n "$runner" ] || fail "step 4 names no evals/*.sh runner"
assert_file "$OPSX_ROOT/$runner"

# --- Scenario：沒有 runner 時有可照抄的指令 ---
grep -E 'claude .*-p' "$FX/step4" | grep -qF -- '--setting-sources project,local' || fail "no claude -p command line with --setting-sources in step 4"
grep -E 'claude .*-p' "$FX/step4" | grep -qF -- '--session-id' || fail "no claude -p command line with --session-id in step 4"
has '.claude/skills/' "$FX/step4"

# --- Scenario：autopilot 停在 gate ---
for k in 'sandbox' 'autopilot' 'gates.md' 'authorization' 'type: approval' 'needs: run'; do has "$k" "$FX/step4"; done

# --- Scenario：transcript 步驟不讀 subagents ---
for k in 'CLAUDE_CONFIG_DIR' '<session id>' 'glob'; do has "$k" "$FX/step6"; done
hasnt 'subagents/' "$FX/step6"

# --- Scenario：judge 照舊 ---
has 'general-purpose' "$FX/step5"
assert_eq "$(grep -c 'general-purpose' "$PB")" 1 "general-purpose only in the judge step"
echo ok
