#!/usr/bin/env bash
# Stop hook 與合併 base 分支後的確認 pass：report.md 的 確認: <sha> 之後只多了合併 base 分支的 merge commit，不用再跑 review。
# 驗收：openspec/changes/agent-20261111-2326/specs/skill-step-guards/spec.md「合併 base 分支後的確認 pass」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Agentory-AI git@gitlab.tsg-navigator.com:agentory/Agentory-AI.git)"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$C/explore.md"
printf '## 1. x\n\n- [x] 1.1 a\n  - 驗收：R\n  - 測試：tests/a.test.sh\n' > "$C/tasks.md"
printf '{"phase":"apply","step":2,"total":2,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
STOP_STATE="$OPSX_STATE_DIR/stop-chain"
sg() { printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
decision() { [ -z "$1" ] && { echo allow; return; }; printf '%s' "$1" | jq -r '.decision // "allow"'; }
reason() { printf '%s' "$1" | jq -r '.reason // ""'; }

SHA0="$(git -C "$R" rev-parse HEAD)"; BR="$(git -C "$R" rev-parse --abbrev-ref HEAD)"
printf '# report\n### 待修（範圍內）\n確認: %s\n' "$SHA0" > "$C/report.md"; touch -t 200001010000 "$C/report.md"

# 確認之後只合併了 base 分支（merge commit，帶進別人的 commit）：不用再 review
git -C "$R" checkout -q -b base-side
git -C "$R" commit -q --allow-empty -m "main: someone else's work"
git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse base-side)"   # base 分支在遠端
git -C "$R" checkout -q -
git -C "$R" merge -q --no-ff base-side -m "Merge remote-tracking branch 'origin/main'"
rm -rf "$STOP_STATE"
out="$(sg)"
case "$(reason "$out")" in *review*) fail "確認之後只合併 base 分支不能再要求 review：$(reason "$out")" ;; esac

# 確認之後合進來的是本地側枝（那支的 commit 沒在任何 remote-tracking 分支）：沒審查過，要擋
git -C "$R" checkout -q -b local-side
git -C "$R" commit -q --allow-empty -m "unreviewed work on a local side branch"
git -C "$R" checkout -q -
git -C "$R" merge -q --no-ff local-side -m "Merge branch 'local-side'"
rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "合併本地側枝要擋"
case "$(reason "$out")" in */opsx-workflow:review*) ;; *) fail "要叫跑 review：$out" ;; esac

# 章魚合併：第二父在 remote-tracking 分支、第三父是本地側枝，每個非第一父都要查
NEWSHA="$(git -C "$R" rev-parse HEAD)"
printf '# report\n### 待修（範圍內）\n確認: %s\n' "$NEWSHA" > "$C/report.md"; touch -t 200001010000 "$C/report.md"
git -C "$R" checkout -q -b oct-remote "$NEWSHA"
git -C "$R" commit -q --allow-empty -m "octopus: remote side"
git -C "$R" update-ref refs/remotes/origin/oct "$(git -C "$R" rev-parse oct-remote)"
git -C "$R" checkout -q -b oct-local "$NEWSHA"
git -C "$R" commit -q --allow-empty -m "octopus: unreviewed local side"
git -C "$R" checkout -q "$BR"
git -C "$R" merge -q --no-ff -m "Merge branches 'oct-remote' and 'oct-local'" oct-remote oct-local
rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "章魚合併帶本地側枝要擋"
case "$(reason "$out")" in */opsx-workflow:review*) ;; *) fail "要叫跑 review：$out" ;; esac

# 確認之後這個 branch 自己又多一個一般 commit：要再 review
git -C "$R" commit -q --allow-empty -m "fix: one more change after the confirm"
rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "確認之後有自己的新 commit 要擋"
case "$(reason "$out")" in */opsx-workflow:review*) ;; *) fail "要叫跑 review：$out" ;; esac

# 沒有確認行：合併後仍要 review
printf '# report\n### 待修（範圍內）\n' > "$C/report.md"; touch -t 200001010000 "$C/report.md"
rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "沒有確認行要擋"
echo "stop-gate-base-merge ok"
