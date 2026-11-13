#!/usr/bin/env bash
# skills/logic-map 的結構：禁讀清單、四段範本、純文字圖、標題只用分支名、technical-writing 指向既有 skill。
# 只證明規則寫在對的段落；agent 守不守由 eval 驗。對應 openspec/changes/logic-map-skill/subs/skill-files/specs/logic-map。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
DIR="$OPSX_ROOT/skills/logic-map"
SK="$DIR/SKILL.md"
EX="$DIR/references/examples.md"
assert_file "$SK"; assert_file "$EX"; assert_file "$DIR/references/feel.md"; assert_file "$DIR/evals/evals.json"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
assert_not_fixed() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }

section() { awk -v h="## $1" 'index($0,h)==1{on=1;print;next} /^## /{on=0} on' "$SK"; }
INPUTS="$FX/inputs"; STEPS="$FX/steps"; TPL="$FX/template"
section "Inputs" > "$INPUTS"; section "Steps" > "$STEPS"
# 範本段裡有 markdown 的 `## 功能 1`，不能在下一個 `## ` 切斷：一路取到檔尾
awk 'index($0,"## Output template")==1{on=1} on' "$SK" > "$TPL"
for f in "$INPUTS" "$STEPS" "$TPL"; do [ -s "$f" ] || fail "section missing: $f"; done

# --- 輸入只有三樣，少一樣就停並說哪一樣 ---
assert_fixed 'If any of the three is missing, stop and say which one' "$INPUTS"

# --- 禁讀清單四項與理由（只讀程式碼）---
for k in '`openspec/`' '`report.md`' 'PR descriptions' 'commit messages'; do assert_fixed "$k" "$INPUTS"; done
assert_fixed 'Reading intent first makes you describe the intent' "$INPUTS"

# --- 四段範本與分支名標題 ---
for k in '### 做了什麼' '### 流程圖' '### 條件表' '### ⚠ 要看的地方' '# 邏輯表：<分支名>'; do assert_fixed "$k" "$TPL"; done

# --- 標題不用 PR 標題（D1）：範本與範例都沒有 `<PR 標題`，Steps 寫明分支名怎麼取、不讀訊息 ---
assert_not_fixed '<PR 標題' "$SK"
assert_not_fixed '<PR 標題' "$EX"
assert_fixed 'rev-parse --abbrev-ref' "$STEPS"
grep -F '# 邏輯表：' "$EX" > "$FX/titles"
[ "$(grep -c . "$FX/titles")" -eq 3 ] || fail "examples.md 應有三個邏輯表標題：$(cat "$FX/titles")"
! grep -qE '^# 邏輯表：[a-z]+(\([^)]*\))?!?: ' "$FX/titles" || fail "範例標題是 conventional-commit 句子：$(cat "$FX/titles")"
! grep -qvE '^# 邏輯表：[a-z]+/[a-z0-9-]+/[a-z0-9-]+$' "$FX/titles" || fail "範例標題不是 <type>/<slug>/<user> 分支名：$(cat "$FX/titles")"

# --- git 指令先切到 <repo> 再跑：`git -C <repo> …` 對不到 autopilot allow 的 git diff / git rev-parse 前綴 ---
assert_fixed 'cd <repo>' "$STEPS"
assert_fixed 'git diff --name-only' "$STEPS"
assert_not_fixed 'git -C <repo>' "$STEPS"

# --- 純文字圖：沒有 mermaid，只留「不用 Mermaid」的說明句 ---
grep -rniF mermaid "$SK" "$DIR/references" > "$FX/mermaid" || true
! grep -vF 'not Mermaid' "$FX/mermaid" | grep -q . || fail "mermaid 出現在說明句以外：$(cat "$FX/mermaid")"
! grep -rqF '```mermaid' "$DIR" || fail "skills/logic-map 有 mermaid 區塊"

# --- 寫法指向既有 technical-writing，不帶副本 ---
assert_fixed '../technical-writing/SKILL.md' "$SK"
assert_not_fixed 'references/technical-writing.md' "$SK"
assert_no_file "$DIR/references/technical-writing.md"
assert_file "$DIR/../technical-writing/SKILL.md"

# --- 既有判斷的範圍：入口到新程式碼路上的每個判斷都要畫，含提前 return 的（第一輪 eval 1 漏了子殼齊的檢查）---
assert_fixed 'every existing decision on the path from the entry of the enclosing function' "$SK"
assert_fixed 'including checks that return early' "$SK"

# --- frontmatter name 對得上目錄 ---
assert_eq "$(sed -n '2p' "$SK")" 'name: logic-map'

# --- 回答對既有邏輯表的提問：四部分、不代決、出處、跟產表模式分界 ---
ANS="$FX/answer"
section "Answering questions about a map" > "$ANS"
[ -s "$ANS" ] || fail "section missing: Answering questions about a map"
# 段落緊接在 Output template 前面（範本裡有 `## 功能 1`，所以不能看最後一個 `## `）
assert_eq "$(grep '^## ' "$SK" | grep -B1 -x '## Output template' | head -1)" '## Answering questions about a map'
# 第一個非標題的行寫分界：拿到三樣輸入時不用這一段
sed -n '2,$p' "$ANS" | grep -m1 . > "$FX/answer-first"
assert_fixed 'repo, a diff range, and an output path' "$FX/answer-first"
assert_fixed 'Steps' "$FX/answer-first"
for k in '| 程式名 | 誰設定 | 業務上是什麼 | 被擋時記成 |' '| 你是誰 | 結果 |' \
  'every gate' 'product decision' '2 to 4 options' 'never decide' \
  'Do not read the code' '沒寫' 'outside the table, on its own line' \
  'explore.md' 'grill.md' 'design.md' 'path:line' '繁體中文'; do
  assert_fixed "$k" "$ANS"
done
# 產表模式的禁讀句與理由句原文還在，Inputs 段首說它只管產表
assert_fixed 'This section is for producing a map' "$INPUTS"
# description 有回答模式的觸發
sed -n '3p' "$SK" > "$FX/description"
assert_fixed 'asks what a line' "$FX/description"
