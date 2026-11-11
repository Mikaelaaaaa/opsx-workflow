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

# --- Scenario：範本也帶寫 spec 的規則（正例）---
for w in 多條業務規則 多組測資 不可分割的業務邏輯單元 正例 反例 SHALL references/gherkin.md; do
  grep -qF -- "$w" "$T" || fail "範本少 '$w'"
done

# --- Scenario：範本範例通過 openspec validate（正例）---
validate_spec "$R" tmpl "$T"

# --- Scenario：範本的 Background 放在規則句之後（反例）---
firsts="$(awk '/^### Requirement:/{want=1;next} want && NF{print;want=0}' "$T")"
[ -n "$firsts" ] || fail "範本沒有 ### Requirement:"
[ "$(printf '%s\n' "$firsts" | wc -l | tr -d ' ')" -ge 2 ] || fail "範本要兩個以上 Requirement"
while IFS= read -r l; do
  case "$l" in Background:*) fail "Requirement 下第一行是 Background：$l" ;; esac
  case "$l" in *SHALL*|*MUST*) ;; *) fail "Requirement 下第一行沒有 SHALL/MUST：$l" ;; esac
done <<< "$firsts"
grep -q '^Background:' "$T" || fail "範本要示範 Background"
grep -q '^#### Scenario Outline:' "$T" || fail "範本要示範 Scenario Outline"
grep -q '^Examples:' "$T" || fail "範本要示範 Examples 表"
grep -q '^#### Scenario: .*（正例）$' "$T" || fail "範本要有正例"
grep -q '^#### Scenario: .*（反例）$' "$T" || fail "範本要有反例"
grep -qF 'references/gherkin.md' "$T" || fail "範本要指向 reference"
# Background 只放 GIVEN
awk '/^Background:/{on=1;next} on && /^(####|###|##) /{on=0} on && /^- \*\*/ && !/^- \*\*(GIVEN|AND)\*\*/{print; bad=1} END{exit bad}' "$T" || fail "Background 只能有 GIVEN / AND"

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

# --- Scenario：instruction 帶選層決策樹、原子化與撰寫原則（正例）---
for w in 多條業務規則 多組測資 前置步驟 "Data Table" Docstring "Scenario Outline" Examples Background \
         不可分割的業務邏輯單元 邏輯模組 \
         業務語言 保持獨立 只驗證一件事 參數化 原子性 正例 反例 \
         SHALL MUST references/gherkin.md ADDED MODIFIED REMOVED RENAMED; do
  grep -qF -- "$w" "$I" || fail "instruction 少 '$w'：$(cat "$I")"
done
grep -qx '禁用模糊詞：正確的、適當的、合理的、正常、良好、妥善、等等、相關的、appropriate、properly、correctly、reasonable、etc.' "$I" \
  || fail "instruction 要有單獨一行的禁用模糊詞清單"

# --- Scenario：instruction 不重抄 reference 的完整內容（反例）---
for w in 會員下訂單 批次新增商品 完成購物 ❌ "Three Amigos"; do ! grep -qF "$w" "$I" || fail "instruction 不該有 reference 範例 '$w'"; done

# --- Scenario：instruction 不再要求只寫 WHEN/THEN（反例）---
! grep -qF 'with WHEN/THEN format' "$I" || fail "instruction 還有 'with WHEN/THEN format'"
! grep -qF 'with WHEN/THEN format' "$B" || fail "artifacts-specs.yaml 還有 'with WHEN/THEN format'"

# --- Scenario：reference 帶原文三層範例與對應一節（正例）---
for w in 查詢商品價格 計算訂單折扣 會員等級折扣計算 會員下訂單 建立會員資料 批次新增商品 完成購物 \
         "Data Table：在單一步驟中傳遞多筆資料" "Examples：定義多組完整的場景參數" \
         "問題一" "問題二" "問題三" 過度技術化 步驟耦合 缺乏具體性 "過度使用 Background"; do
  grep -qF -- "$w" "$G" || fail "reference 少 '$w'"
done
grep -q '^## .*對應到 openspec' "$G" || fail "reference 少「對應到 openspec」一節"

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
echo ok
