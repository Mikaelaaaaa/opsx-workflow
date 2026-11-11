#!/usr/bin/env bash
# skills/apply/SKILL.md 的子 change 一節：分配規則與 subagent 的 brief。只證明規則寫在對的段落；agent 守不守由 eval 驗。
# 驗收：openspec/changes/apply-fanout/specs/subchange-apply/spec.md「apply skill 寫明分配規則」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/apply/SKILL.md"
assert_file "$SK"
has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
section() { awk -v h="## $1" '/^```/{fence=!fence} index($0,h)==1{on=1;print;next} !fence && /^## /{on=0} on' "$SK"; }
SUBS="$FX/subs"
section "When the main change has subs/" > "$SUBS"
[ -s "$SUBS" ] || fail "section missing: When the main change has subs/"

# --- Scenario：apply skill 寫明分配規則 ---
for k in '先 propose 沒有 tasks.md 的子殼' 'depends-on' 'subagent' '<主>--<子>' 'DONE <子> <sha>' 'NEEDS-USER <子>' '子殼的 gates.md' '不 push'; do
  has "$k" "$SUBS"
done

# --- Scenario：apply skill 寫明疊回規則（openspec/changes/apply-fanout/specs/subchange-stack/spec.md）---
for k in 'opsx stack' 'workplan 順序' '退出 3' 'session 自己重做' '/opsx-workflow:review' '/opsx-workflow:pr' '不在衝突標記上手解'; do
  has "$k" "$SUBS"
done

# --- stop-gate-waits-on-subagents：收到 DONE 要把子殼 status 寫成 n/n，Stop hook 才不把等疊當成 subagent 在跑 ---
has 'opsx status apply <total>/<total>' "$SUBS"
has '--sub <子> --worker session' "$SUBS"
has 'anything that is not `NEEDS-USER`' "$SUBS"

# --- grant-action：授權 gate 要寫 action:，值取自 hook 的 deny 訊息 ---
has 'action: <value>' "$SK"
has "grant hook's deny message" "$SK"

# --- grant-outbound-speech：Two modes 寫明對外發話是第三級、hook 不擋、發話前寫 gate；第二級列有 test-path ---
MODES="$FX/modes"
section "Two modes" > "$MODES"
for k in 'customer or anyone outside the team' 'level three' 'the grant hook cannot see it' 'write a `type: approval` gate' 'test file in a directory with no tracked tests'; do
  has "$k" "$MODES"
done

# --- review-fix-in-scope：apply 接 review 退回的 task；pr 在有待修時拒絕 ---
has '## R<N>. review 退回' "$SK"
has '測試先紅再修' "$SK"
has '待修（範圍內）' "$OPSX_ROOT/skills/pr/SKILL.md"
has '/opsx-workflow:apply <slug>' "$OPSX_ROOT/skills/pr/SKILL.md"

# --- card-area-field：範圍外開卡一律走 opsx new，帶 --area，slug 可能是既有的卡（specs/card-auto-merge「apply 的範圍外開卡」）---
grep -F "A problem outside this task's scope" "$SK" > "$FX/row6"
[ "$(wc -l < "$FX/row6" | tr -d ' ')" = 1 ] || fail "skeleton 第 6 列要剛好一行"
for k in 'opsx new' '--kind-of-work' '--area' 'openspec/areas.txt' 'existing card' 'never dispatch'; do has "$k" "$FX/row6"; done
! grep -qF 'openspec new change' "$FX/row6" || fail "第 6 列不能再叫 agent 用 openspec new change 開範圍外卡"
# 開卡前不知道會不會被併：完整證據事前就寫進 --evidence；放不下時 split-out 再寫；priority 只對沒被併的新卡跑
has '併進' "$FX/row6"
has 'before you know whether it merges' "$FX/row6"
has 'opsx split-out' "$FX/row6"
has 'only when it was not merged' "$FX/row6"
! grep -qF "Put longer evidence under \`## 證據\` in that slug's" "$FX/row6" || fail "第 6 列不能叫被併入的 agent 把證據寫進目標卡的 ## 證據"
echo ok
