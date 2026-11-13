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

# --- 兩段業務說明：範本位置 ---
BIZ_TOP='## 這支 PR 在做什麼（業務說明）'; BIZ_FEAT='### 業務上在做什麼'
for k in "$BIZ_TOP" "$BIZ_FEAT"; do assert_fixed "$k" "$TPL"; done
grep -n -e '^範圍：' -e "^$BIZ_TOP" -e '^## 功能 1' -e '^### ' "$TPL" | sed 's/^[0-9]*://' | head -4 > "$FX/tpl-order"
assert_eq "$(cat "$FX/tpl-order")" "範圍：\`<base>...<head>\` · 讀的檔：<n> 個 · 功能：<n> 個
$BIZ_TOP
## 功能 1：<一句話>
$BIZ_FEAT" "範本順序：範圍行、頂端業務說明、功能 1、功能的第一小節是業務段"

# --- 兩段業務說明：寫法規則 ---
BIZ="$FX/business"
section "The business summary" > "$BIZ"
[ -s "$BIZ" ] || fail "section missing: The business summary"
assert_eq "$(grep '^## ' "$SK" | grep -A1 -x '## The business summary' | tail -1)" '## The three parts of a feature'
for k in '3 to 5 sentences' '2 to 4 sentences' 'a concrete example' '誰做什麼' '系統怎麼判斷' '對方看到什麼' \
  'No function names, file paths, or FEEL' 'only from the code in the diff range' '使用者看不到差別'; do
  assert_fixed "$k" "$BIZ"
done
assert_not_fixed '搬移' "$BIZ"

# --- 兩段業務說明：三份範例都有，內文沒有識別字 ---
python3 -I - "$EX" > "$FX/ex-biz" <<'PY' || fail "examples.md 的業務說明：$(cat "$FX/ex-biz")"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
maps = re.split(r"^# 邏輯表：", text, flags=re.M)[1:]
bad = []
if len(maps) != 3:
    bad.append("範例數 %d" % len(maps))
for i, m in enumerate(maps, 1):
    head = re.split(r"^## 功能", m, maxsplit=1, flags=re.M)[0]
    top = re.search(r"^## 這支 PR 在做什麼（業務說明）\n(.*?)(?=^## |\Z)", head, flags=re.M | re.S)
    if not top:
        bad.append("範例 %d 沒有頂端業務說明" % i)
    bodies = [top.group(1)] if top else []
    for f in re.split(r"^## 功能", m, flags=re.M)[1:]:
        subs = re.findall(r"^### (.+)$", f, flags=re.M)
        if not subs or subs[0] != "業務上在做什麼":
            bad.append("範例 %d 的功能第一小節是 %r" % (i, subs[:1]))
            continue
        bodies.append(re.search(r"^### 業務上在做什麼\n(.*?)(?=^### |\Z)", f, flags=re.M | re.S).group(1))
    for b in bodies:
        if "`" in b or re.search(r"[\w./-]+:\d+", b):
            bad.append("範例 %d 的業務段有識別字或路徑：%s" % (i, b.strip()[:60]))
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY

# --- frontmatter name 對得上目錄 ---
assert_eq "$(sed -n '2p' "$SK")" 'name: logic-map'

# --- 回答對既有邏輯表的提問：四部分、不代決、出處、跟產表模式分界 ---
ANS="$FX/answer"
section "Answering questions about a map" > "$ANS"
[ -s "$ANS" ] || fail "section missing: Answering questions about a map"
# 段落緊接在 Output template 前面（範本裡有 `## 功能 1`，所以不能看最後一個 `## `）
assert_eq "$(grep '^## ' "$SK" | grep -B1 -x '## Output template' | head -1)" '## Answering questions about a map'
# 第一個非標題的行寫分界，整句比對：只查關鍵字的話，把規則反寫也會過
sed -n '2,$p' "$ANS" | grep -m1 . > "$FX/answer-first"
assert_fixed 'When the prompt gives you a repo, a diff range, and an output path, you are producing a map: skip this section and follow Steps.' "$FX/answer-first"
# 四條規則各自那一行要帶自己的表頭與整句：表頭也出現在範例裡，只查全段會讓刪掉的規則照樣過
grep -m1 '^1\. ' "$ANS" > "$FX/rule1"; grep -m1 '^2\. ' "$ANS" > "$FX/rule2"
grep -m1 '^3\. ' "$ANS" > "$FX/rule3"; grep -m1 '^4\. ' "$ANS" > "$FX/rule4"
assert_fixed '| 程式名 | 誰設定 | 業務上是什麼 | 被擋時記成 |' "$FX/rule1"
assert_fixed '| 你是誰 | 結果 |' "$FX/rule2"
assert_fixed 'every gate' "$FX/rule2"
assert_fixed 'product decision' "$FX/rule3"
assert_fixed '2 to 4 options' "$FX/rule3"
assert_fixed 'You never decide for the user. Do not mark any option as settled.' "$FX/rule3"
assert_fixed 'path:line' "$FX/rule4"
assert_fixed 'outside the table, on its own line' "$FX/rule4"
assert_fixed '文件都沒寫，只有程式這樣做' "$FX/rule4"
assert_fixed 'design.md mentions it, explore.md and grill.md do not' "$FX/rule4"
# 規則句整句比對：這些字在規則 4 與範例裡也有，只查關鍵字的話刪掉規則句照樣過
for k in 'Read the logic map, then the `design.md`, `explore.md`, and `grill.md` in the same change directory as the map. Do not read the code.' \
  'When a file is missing, or none of them says something, such as who sets a value, write 「沒寫」 in the table cell. Do not guess.' \
  'In this mode, answer in the reply. Do not write or change any file.' \
  'In a dispatch worktree that is the main checkout, not the current directory' \
  'does not find exactly one map, ask which card before reading any map.' \
  'If the map the question is about no longer exists, say so, quote the `## 邏輯表` line of that card'"'"'s `report.md`, and stop' \
  '繁體中文'; do
  assert_fixed "$k" "$ANS"
done
assert_not_fixed 'before reading anything' "$ANS"
assert_not_fixed 'A missing file says nothing' "$ANS"
# 範例的出處有前提可循：說 explore.md 定的，前提就寫 explore.md 說了什麼
assert_fixed 'explore.md says only pro can download' "$ANS"
# 範例照自己的規則：不說讀了程式碼
assert_not_fixed 'The code has' "$ANS"
# 產表模式的禁讀句與理由句原文還在，Inputs 段首與開頭都說只管產表
assert_fixed 'This section is for producing a map' "$INPUTS"
assert_fixed 'When producing a map, you produce one document' "$SK"
# description：產表才只讀程式碼；回答的觸發綁在邏輯表上，不跟 grill/design 的 D 編號撞
sed -n '3p' "$SK" > "$FX/description"
assert_fixed 'asks what a line' "$FX/description"
assert_fixed 'When producing a map, it reads only the code' "$FX/description"
assert_fixed '「邏輯表的 D3 是什麼」' "$FX/description"
assert_not_fixed '「D3 是什麼」' "$FX/description"
