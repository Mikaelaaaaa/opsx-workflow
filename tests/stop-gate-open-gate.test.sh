#!/usr/bin/env bash
# 有等人答的 blocking gate 時 Stop hook 每一站都放行，不累計 MAX_BLOCKS、不開「卡在接」。
# 驗收：openspec/changes/me-20261111-1824/specs/stop-gate-open-gate/spec.md、
#       openspec/changes/agent-20261113-1355/specs/stop-gate-open-gate/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI git@gitlab.example.com:acmecorp/Acmecorp-AI.git)"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$C/explore.md"
printf '## 1. x\n\n- [x] 1.1 a\n  - 驗收：R\n  - 測試：tests/a.test.sh\n' > "$C/tasks.md"
printf '{"phase":"apply","step":2,"total":2,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
STOP_STATE="$OPSX_STATE_DIR/stop-chain"
sg() { printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
decision() { [ -z "$1" ] && { echo allow; return; }; printf '%s' "$1" | jq -r '.decision // "allow"'; }
tests_is() { printf '{"phase":"apply","step":2,"total":2,"label":"x","tests":"%s","at":"2026-11-05T15:00:00+08:00"}' "$1" > "$C/status.json"; }
APPROVAL='## docs-api-regen\ntype: approval\nstatus: open\nneeds: run\naction: docs-api\n問題: 能請你跑 pnpm docs:api 嗎？\n'
DECISION='## 等協調者的全套結果\ntype: decision\nstatus: open\n問題: 全套結果出來前先停嗎\n選項: 等 (Recommended) | 不等\n建議: 等\n預設: 不等\n'
ASK_APPROVAL='## grant-apply\ntype: approval\nstatus: open\naction: push\n問題: 要不要接 /apply？\n'
ASK_DECISION='## next\ntype: decision\nstatus: open\n問題: 要不要接 /apply？\n'
# 連停五次都放行、沒有「卡在接」、沒有計數檔
five_allowed() { # <這一列的名字>
  local i out
  rm -rf "$STOP_STATE"
  for i in 1 2 3 4 5; do
    out="$(sg)"; assert_eq "$(decision "$out")" allow "$1：第 ${i} 次要放行: $out"
  done
  assert_not_grep '卡在接' "$C/gates.md"
  assert_no_file "$STOP_STATE/Acmecorp-AI-eval-core"
}

# 沒有 gate：擋，要求跑 review
rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "沒有 gate 時要擋"
printf '%s' "$out" | jq -r '.reason' | grep -q '/opsx-workflow:review' || fail "要叫跑 review: $out"

# 為等協調者寫了 decision gate：放行，stop-chain 計數不增加
printf "$DECISION" > "$C/gates.md"
five_allowed "review 站 decision gate"

# gate 答完之後恢復原行為
printf '## 等協調者的全套結果\ntype: decision\nstatus: answered\nanswer: 等\n' > "$C/gates.md"
rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "gate answered 後要擋"

# 一般場景：tests 是 red
tests_is red
printf "$APPROVAL" > "$C/gates.md"; five_allowed "tests red + approval needs: run"
printf "$DECISION" > "$C/gates.md"; five_allowed "tests red + decision"

# 邊界場景：沒有 status.json（tests unknown）
rm -f "$C/status.json"
printf "$APPROVAL" > "$C/gates.md"; five_allowed "沒有 status.json + approval"
# 邊界場景：核准的問法是「要不要接」也算等人
tests_is red
printf "$ASK_APPROVAL" > "$C/gates.md"; five_allowed "tests red + approval 問要不要接"

# 反例：只問要不要接的 decision 不算等人
printf "$ASK_DECISION" > "$C/gates.md"; rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "只問要不要接的 gate 要擋"
printf '%s' "$out" | jq -r '.reason' | grep -q 'tests 不是 green' || fail "要叫把測試跑綠: $out"
# 反例：gate 答完後照擋
printf '## docs-api-regen\ntype: approval\nstatus: answered\nanswer: 跑完了\n' > "$C/gates.md"; rm -rf "$STOP_STATE"
out="$(sg)"; assert_eq "$(decision "$out")" block "tests red、gate 答完要擋"
printf '%s' "$out" | jq -r '.reason' | grep -q 'tests 不是 green' || fail "要叫把測試跑綠: $out"

# 一般場景：report.md 之後有新 commit
tests_is green
printf '# report\n### 待修（範圍內）\n' > "$C/report.md"; touch -t 200001010000 "$C/report.md"
git -C "$R" commit -q --allow-empty -m "fix: after review"
rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
out="$(sg)"; printf '%s' "$out" | jq -r '.reason' | grep -q '再跑一次 /opsx-workflow:review' || fail "沒 gate 時 report 後新 commit 要求重審: $out"
printf "$APPROVAL" > "$C/gates.md"; five_allowed "report 後新 commit + approval needs: run"

# 一般場景：report.md 的待修（範圍內）有一項
printf '# report\n### 待修（範圍內）\n- a.sh:1 x\n' > "$C/report.md"
rm -f "$C/gates.md"; rm -rf "$STOP_STATE"
out="$(sg)"; printf '%s' "$out" | jq -r '.reason' | grep -q '待修（範圍內）' || fail "沒 gate 時待修要擋: $out"
printf "$DECISION" > "$C/gates.md"; five_allowed "待修一項 + decision"

# 「卡在接」開著時再開一個等人的 gate：照樣放行，不寫第二個「卡在接」
rm -f "$C/report.md"; tests_is red
printf '## 卡在接 /apply #1\ntype: decision\nstatus: open\n問題: opsx：eval-core 連續 3 次停在 /opsx-workflow:apply 之前沒有 invoke，卡在哪？\n\n' > "$C/gates.md"
printf "$APPROVAL" >> "$C/gates.md"
rm -rf "$STOP_STATE"
for i in 1 2 3 4 5; do
  out="$(sg)"; assert_eq "$(decision "$out")" allow "卡在接 + approval：第 ${i} 次要放行: $out"
done
assert_eq "$(grep -c '^## 卡在接' "$C/gates.md")" 1 "卡在接 + approval：不寫第二個「卡在接」"
assert_no_file "$STOP_STATE/Acmecorp-AI-eval-core"
echo "stop-gate-open-gate ok"
