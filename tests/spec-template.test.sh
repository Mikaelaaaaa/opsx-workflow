#!/usr/bin/env bash
# 插件的 Gherkin spec 範本、specs artifact 區塊、Gherkin reference。
# 驗收：openspec/changes/gherkin-template/subs/spec-template/specs/spec-format/spec.md 的每個 Scenario
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
T="$OPSX_ROOT/schemas/opsx/templates/spec.md"
B="$OPSX_ROOT/schemas/opsx/artifacts-specs.yaml"
G="$OPSX_ROOT/skills/propose/references/gherkin.md"
assert_file "$T"; assert_file "$B"; assert_file "$G"
# specs 區塊一律用 init 安裝時的同一個 specs_block 讀寫：只給 schema.yaml 印出區塊，多給一個檔就換成它
block_of() { ( OPSX_PY=python3; source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/init.sh"; specs_block "$@" ); }

# 測試不另寫 specs 區塊的 regex（樣式拆成兩段，免得這行自己命中）
copy_pat='id: specs''\n('
! grep -lF -- "$copy_pat" "$OPSX_ROOT"/tests/*.test.sh || fail "測試裡有 specs 區塊 regex 的副本，改呼叫 specs_block：$(grep -lF -- "$copy_pat" "$OPSX_ROOT"/tests/*.test.sh)"

# 每個 Examples: 之後的第二行是 markdown 表的分隔列
examples_have_delimiter() { # <檔>
  awk '/^Examples:/{n=NR} n && NR==n+2 && !/^\|( *-+ *\|)+$/{print FILENAME ":" NR ": " $0; bad=1} END{exit bad}' "$1"
}
# Scenario Outline 的標題一律是 #### Scenario: <名>（Scenario Outline，正例|反例）
outline_headings_ok() { # <檔>
  awk '/^#### Scenario.*Scenario Outline/ && !/^#### Scenario: .+（Scenario Outline，(正例|反例)）$/{print FILENAME ":" NR ": " $0; bad=1} END{exit bad}' "$1"
}

# 一張 change，specs/demo/spec.md 放指定內容，跑真的 openspec validate --strict
validate_spec() { # <repo> <change> <spec 檔>
  mkdir -p "$1/openspec/changes/$2/specs/demo"
  printf '## Why\n\n示範一張 change 的 spec 寫法，驗證範本本身合法。\n\n## What Changes\n\n- 新增 demo\n' > "$1/openspec/changes/$2/proposal.md"
  cp "$3" "$1/openspec/changes/$2/specs/demo/spec.md"
  local out rc
  out="$(cd "$1" && openspec validate "$2" --strict 2>&1)"; rc=$?
  assert_eq "$rc" 0 "validate $2: $out"
  case "$out" in *"is valid"*) ;; *) fail "validate $2 沒說 is valid：$out" ;; esac
}
R="$(mk_repo demo)"
( cd "$R" && openspec init --tools none "$R" >/dev/null 2>&1 ) || fail "openspec init 失敗"

# --- Scenario：範本骨架通過 openspec validate（正例）---
validate_spec "$R" tmpl "$T"

# --- Scenario：範本帶齊骨架的每一塊（正例）---
grep -q '^## ADDED Requirements$' "$T" || fail "範本少 ## ADDED Requirements"
grep -q '^### Requirement: ' "$T" || fail "範本少 ### Requirement:"
grep -q '^#### Scenario: .*（正例）$' "$T" || fail "範本要有正例骨架"
grep -q '^#### Scenario: .*（反例）$' "$T" || fail "範本要有反例骨架"
grep -q '^#### Scenario: .*（Scenario Outline，' "$T" || fail "範本要有 Scenario Outline 骨架（#### Scenario: <行為>（Scenario Outline，…））"
! grep -q '^#### Scenario Outline:' "$T" || fail "Outline 標題照定案用 #### Scenario:，不用 #### Scenario Outline:"
outline_headings_ok "$T" || fail "範本的 Outline 標題不是（Scenario Outline，正例|反例）"
examples_have_delimiter "$T" || fail "範本的 Examples 表少分隔列"
grep -qx 'Examples: 一般場景' "$T" || fail "範本少 Examples: 一般場景"
grep -qx 'Examples: 邊界場景' "$T" || fail "範本少 Examples: 邊界場景"
awk '/^Examples: 邊界場景$/{on=1;next} on && /^\|/{print;exit}' "$T" | grep -qF '備註' || fail "邊界場景表頭要多一欄 備註"
grep -q '^Background:' "$T" || fail "範本要有選用的 Background 骨架"
grep -q '^<!--.*references/gherkin.md.*-->$' "$T" || fail "範本要有一行註解指向 references/gherkin.md"
firsts="$(awk '/^### Requirement:/{want=1;next} want && NF{print;want=0}' "$T")"
while IFS= read -r l; do
  case "$l" in Background:*) fail "Requirement 下第一行是 Background：$l" ;; esac
  case "$l" in *SHALL*|*MUST*) ;; *) fail "Requirement 下第一行沒有 SHALL/MUST：$l" ;; esac
done <<< "$firsts"
awk '/^Background:/{on=1;next} on && /^(####|###|##) /{on=0} on && /^- \*\*/ && !/^- \*\*(GIVEN|AND)\*\*/{print; bad=1} END{exit bad}' "$T" || fail "Background 只能有 GIVEN / AND"

# --- Scenario：範本不放真範例與寫法規則（反例）---
for w in 可樂 小明 會員 不可分割的業務邏輯單元 禁用模糊詞 撰寫原則; do
  ! grep -qF -- "$w" "$T" || fail "範本不該有 '$w'"
done

# --- specs 區塊：接進 fork 的 schema.yaml 能過 openspec schema validate，instructions 拿得到 ---
grep -q '^  - id: specs$' "$B" || fail "artifacts-specs.yaml 要是 '  - id: specs' 區塊"
( cd "$R" && openspec schema fork spec-driven opsx >/dev/null 2>&1 ) || fail "schema fork 失敗"
S="$R/openspec/schemas/opsx/schema.yaml"
block_of "$S" "$B" || fail "specs 區塊換不進 schema.yaml"
cp "$T" "$R/openspec/schemas/opsx/templates/spec.md"
out="$(cd "$R" && openspec schema validate opsx 2>&1)" || fail "schema validate: $out"
I="$FX/instruction.txt"
( cd "$R" && openspec instructions specs --change tmpl --schema opsx --json ) > "$FX/instr.json" 2>&1 \
  || fail "openspec instructions specs 失敗：$(cat "$FX/instr.json")"
python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["instruction"])' "$FX/instr.json" > "$I" || fail "instructions 沒有 instruction 欄：$(cat "$FX/instr.json")"

# --- Scenario：instruction 帶齊寫 spec 的規則（正例）---
# 每一句只會出現在它那一條規則裡：刪掉那條規則，這裡就紅
while IFS= read -r w; do
  grep -qF -- "$w" "$I" || fail "instruction 少 '$w'：$(cat "$I")"
done <<'RULES'
結構層次：Feature → Rule → Scenario / Example → Given / When / Then / And
| Feature | 功能特性 |
| Rule | 業務規則 |
| Scenario | 具體場景 |
| Scenario Outline | 參數化場景 |
| Given | 前置條件 |
| When | 執行動作 |
| Then | 預期結果 |
| And / But | 連接步驟 |
| Background | 共用前置 |
| Examples | 測試數據表 |
Rule 是 `### Requirement: <名>`
標題下第一個非空行是規則句，必須含 SHALL 或 MUST
（Scenario Outline，正例）
Examples 表放在 Scenario Outline 之下
Background 放在規則句之後、第一個 Scenario 之前
參數用雙引號標記
數字直接寫，不加引號
反例沒有前置條件時，GIVEN 可省略
每個 Requirement 都要有正例與反例
每條 Rule 是一個不可分割的業務邏輯單元
每個 Feature 對應開發中要實作的一個邏輯模組
用 Rule 把複雜功能拆成獨立規則
這個功能有多條業務規則需要處理嗎
同一條規則需要驗證多組測資嗎
多個場景有相同的前置步驟嗎
需要批次資料嗎？是：用 Data Table
需要傳遞複雜結構（JSON / XML）嗎？是：用 Docstring
只放共用的前置條件，不放測試邏輯
保持原始格式（縮排和換行）
Data Table 在單一步驟中傳遞多筆資料
Examples 定義多組完整的場景參數
`*` 用在多個連續的 And 步驟
使用業務語言，避免技術細節
每個 Scenario 保持獨立
一個 Scenario 只驗證一件事
善用參數化
保持 Step 的原子性
過度技術化：
步驟耦合：
缺乏具體性：
過度使用 Background：
「驗收：」指到 Scenario 名稱
Examples 表的每一列都要有測試
**ADDED Requirements**
**MODIFIED Requirements**
**REMOVED Requirements**
**RENAMED Requirements**
skills/propose/references/gherkin.md
RULES
grep -qx '禁用模糊詞：正確的、適當的、合理的、正常、良好、妥善、等等、相關的、appropriate、properly、correctly、reasonable、etc.' "$I" \
  || fail "instruction 要有單獨一行的禁用模糊詞清單"

# --- Scenario：instruction 不放範例（反例）---
for w in 可樂 小明 會員下訂單 批次新增商品 完成購物 ❌ "Three Amigos"; do ! grep -qF "$w" "$I" || fail "instruction 不該有範例 '$w'"; done

# --- Scenario：instruction 不再要求只寫 WHEN/THEN（反例）---
! grep -qF 'with WHEN/THEN format' "$I" || fail "instruction 還有 'with WHEN/THEN format'"
! grep -qF 'with WHEN/THEN format' "$B" || fail "artifacts-specs.yaml 還有 'with WHEN/THEN format'"

# --- Scenario：reference 帶原文三層與進階技巧範例（正例）---
for w in 查詢商品價格 計算訂單折扣 會員等級折扣計算 優勢 會員下訂單 建立會員資料 批次新增商品 完成購物 ❌ ✅ "Step Definitions" 總結; do
  grep -qF -- "$w" "$G" || fail "reference 少 '$w'"
done
grep -q '^## .*對應到 openspec' "$G" || fail "reference 少「對應到 openspec」一節"

# --- Scenario：reference 不重抄寫法規則（反例）---
for w in "## 核心關鍵字" "## 如何選擇架構" "## 常見陷阱" 禁用模糊詞 "每條 Rule 是一個不可分割的業務邏輯單元"; do
  ! grep -qF -- "$w" "$G" || fail "reference 不該有寫法規則 '$w'"
done

# --- Scenario：reference 的 opsx 範例通過 openspec validate（正例）---
EX="$FX/ref-example.md"
awk '/^## .*對應到 openspec/{sec=1;next} sec && /^```markdown$/{on=1;next} on && /^```$/{exit} on' "$G" > "$EX"
[ -s "$EX" ] || fail "「對應到 openspec」一節沒有 \`\`\`markdown 範例"
validate_spec "$R" refex "$EX"
# 範例本身照 instruction 的規則：Outline 標題、Examples 分組與分隔列
outline_headings_ok "$EX" || fail "reference 範例的 Outline 標題不是（Scenario Outline，正例|反例）"
examples_have_delimiter "$EX" || fail "reference 範例的 Examples 表少分隔列"
grep -qx 'Examples: 一般場景' "$EX" || fail "reference 範例少 Examples: 一般場景"
grep -qx 'Examples: 邊界場景' "$EX" || fail "reference 範例少 Examples: 邊界場景"
! grep -qx 'Examples:' "$EX" || fail "reference 範例有沒分組名的 Examples:"
# 範例斷言的 opsx 輸出字句，init.sh 真的會印
grep -o '輸出含 "[^"]*"\( 與 "[^"]*"\)*' "$EX" | grep -o '"[^"]*"' | tr -d '"' > "$FX/ref-outputs"
[ -s "$FX/ref-outputs" ] || fail "reference 範例沒有斷言輸出字句"
while IFS= read -r o; do
  grep -qF -- "$o" "$OPSX_ROOT/bin/lib/init.sh" || fail "reference 範例斷言的輸出 '$o' 在 bin/lib/init.sh 裡找不到"
done < "$FX/ref-outputs"

# 重跑 init 不是 no-op，說明不能再這樣寫
! grep -qF '重跑一律 no-op' "$OPSX_ROOT/bin/lib/init.sh" || fail "init.sh 還說重跑一律 no-op"
! grep -qF 'no-op when rerun' "$OPSX_ROOT/skills/opsx-init/SKILL.md" || fail "opsx-init SKILL.md 還說 no-op when rerun"

# --- Scenario：reference 不自編原文以外的範例（反例）---
# 原文（openspec/changes/spec-gherkin/attachments/bdd-gherkin-source.md）裡全部 Feature / Rule / Scenario / Example 名稱
ALLOWED='查詢商品價格
查詢已上架商品的價格（正例）
查詢不存在的商品（反例）
計算訂單折扣
滿額折價
訂單金額達到折扣門檻
訂單金額未達折扣門檻
會員等級折扣計算
不同會員等級享有不同折扣率
查詢商品價格並套用會員折扣
會員下訂單
會員下訂單包含單一商品
會員下訂單包含多項商品
建立會員資料
批次新增商品
完成購物'
names="$(awk '/^## .*對應到 openspec/{exit} /^```gherkin$/{on=1;next} on && /^```$/{on=0} on' "$G" \
  | sed -nE 's/^[[:space:]]*(Feature|Rule|Scenario Outline|Scenario|Example):[[:space:]]*(.+)$/\2/p')"
[ -n "$names" ] || fail "reference 原文章節沒有 \`\`\`gherkin 區塊"
while IFS= read -r n; do
  printf '%s\n' "$ALLOWED" | grep -qxF -- "$n" || fail "reference 有原文以外的範例名稱：$n"
done <<< "$names"

# --- Scenario：evals fixtures 的 schema 快照是插件版（正例）---
# --- Scenario：fixtures 裡沒有 fork 來的 WHEN/THEN 範本（反例）---
n=0
for d in "$OPSX_ROOT"/skills/*/evals/fixtures/*/repo/openspec/schemas/opsx; do
  [ -d "$d" ] || continue
  n=$((n + 1))
  cmp -s "$T" "$d/templates/spec.md" || fail "fixture 範本不是插件版：$d/templates/spec.md"
  [ "$(block_of "$d/schema.yaml")" = "$(cat "$B")" ] || fail "fixture 的 specs 區塊不是插件版：$d/schema.yaml"
  ! grep -qF 'with WHEN/THEN format' "$d/schema.yaml" || fail "fixture 還有 'with WHEN/THEN format'：$d/schema.yaml"
done
[ "$n" -gt 0 ] || fail "找不到任何 evals fixture 的 schema 快照"
echo ok
