#!/usr/bin/env bash
# 插件的 Gherkin spec 範本、specs artifact 區塊、Gherkin reference。
# 驗收：openspec/changes/gherkin-template/subs/spec-template/specs/spec-format/spec.md 的每個 Scenario
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
T="$OPSX_ROOT/schemas/opsx/templates/spec.md"
B="$OPSX_ROOT/schemas/opsx/artifacts-specs.yaml"
G="$OPSX_ROOT/skills/propose/references/gherkin.md"
assert_file "$T"; assert_file "$B"; assert_file "$G"

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
python3 -I - "$S" "$B" <<'PY' || fail "specs 區塊換不進 schema.yaml"
import re, sys
p, b = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
m = re.search(r"^  - id: specs\n(?:(?!  - id: ).*\n)*", s, re.M)
if not m: sys.exit("fork 的 schema.yaml 找不到 specs 區塊")
open(p, "w", encoding="utf-8").write(s[:m.start()] + open(b, encoding="utf-8").read() + s[m.end():])
PY
cp "$T" "$R/openspec/schemas/opsx/templates/spec.md"
out="$(cd "$R" && openspec schema validate opsx 2>&1)" || fail "schema validate: $out"
I="$FX/instruction.txt"
( cd "$R" && openspec instructions specs --change tmpl --schema opsx --json ) > "$FX/instr.json" 2>&1 \
  || fail "openspec instructions specs 失敗：$(cat "$FX/instr.json")"
python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["instruction"])' "$FX/instr.json" > "$I" || fail "instructions 沒有 instruction 欄：$(cat "$FX/instr.json")"

# --- Scenario：instruction 帶齊寫 spec 的規則（正例）---
for w in "| Feature |" "| Rule |" "| Scenario |" "| Scenario Outline |" "| Given |" "| When |" "| Then |" "| And / But |" "| Background |" "| Examples |" \
         雙引號 可省略 不可分割的業務邏輯單元 邏輯模組 多條業務規則 多組測資 前置步驟 "Data Table" Docstring 不放測試邏輯 保持原始格式 \
         業務語言 保持獨立 只驗證一件事 參數化 原子性 過度技術化 步驟耦合 缺乏具體性 "過度使用 Background" \
         SHALL MUST ADDED MODIFIED REMOVED RENAMED 驗收： references/gherkin.md; do
  grep -qF -- "$w" "$I" || fail "instruction 少 '$w'：$(cat "$I")"
done
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
# specs 區塊用 init 安裝時的同一個 specs_block 抽出來比
block_of() { ( OPSX_PY=python3; source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/init.sh"; specs_block "$1" ); }
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
