#!/usr/bin/env bash
# skills/pr/SKILL.md 步 5c：派 logic-map subagent 產表、貼成一則留言、更新時編輯同一則。
# skill 是文字，只能檢查 skill 寫了什麼；agent 守不守由 eval 驗。對應 openspec/changes/pr-logic-map/specs/pr-logic-map。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/pr/SKILL.md"
assert_file "$SK"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
assert_not_fixed() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }

# 步 5c 一段：從 `5c.` 那行到 `6.` 那行之前
STEP="$FX/step5c"
awk '/^5c\. /{on=1} /^6\. /{on=0} on' "$SK" > "$STEP"
[ -s "$STEP" ] || fail "skills/pr/SKILL.md 沒有步 5c"

# --- 位置：5b 之後、6 之前；新開與更新都跑 ---
python3 -I - "$SK" <<'PY' || fail "Logic map 不在 Back-link 與 Reply 之間"
import sys
text = open(sys.argv[1], encoding="utf-8").read()
backlink = text.index("**Back-link.**")
logic = text.index("**Logic map.**")
reply = text.index("**Reply.**")
if not backlink < logic < reply:
    sys.exit("順序：backlink=%d logic=%d reply=%d" % (backlink, logic, reply))
PY
assert_fixed 'on a new MR and on an update' "$STEP"
assert_fixed 'step 5c runs on both' "$SK"

# --- 範圍：先 fetch 主要 remote 的 main，三點範圍到 HEAD ---
assert_fixed 'git fetch <remote> main' "$STEP"
assert_fixed '<remote>/main...HEAD' "$STEP"

# --- subagent 的 prompt 只有四行（Scenario「prompt 的輸入清單」）---
assert_fixed 'Agent tool' "$STEP"
python3 -I - "$STEP" <<'PY' || fail "prompt 區塊不是那四行"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"```\n(.*?)```", text, re.S)
prompt = [b for b in blocks if b.lstrip().startswith("repo: ")]
if len(prompt) != 1:
    sys.exit("找不到以 repo: 開頭的 prompt 區塊：%r" % blocks)
lines = prompt[0].strip().splitlines()
want = ["repo: ", "range: <remote>/main...HEAD", "output: ", "Load "]
if len(lines) != 4 or not all(l.strip().startswith(w) for l, w in zip(lines, want)):
    sys.exit("prompt：%r" % lines)
if "openspec/changes/<slug>/logic-map.md" not in lines[2]:
    sys.exit("輸出路徑：%r" % lines[2])
if "../logic-map/SKILL.md" not in lines[3]:
    sys.exit("skill 路徑：%r" % lines[3])
PY
for k in 'spec' 'proposal' 'design' 'report' 'conversation' 'PR title or description'; do
  grep -F 'Nothing else goes into the prompt' "$STEP" | grep -qF -- "$k" || fail "禁止清單缺 $k"
done

# --- 新開：GitHub 用 gh pr comment，GitLab 用 glab api POST，內文都從檔案讀 ---
assert_fixed '`gh pr comment <n> --body-file openspec/changes/<slug>/logic-map.md`' "$STEP"
assert_fixed '`glab api --method POST "projects/:id/merge_requests/<iid>/notes" --field body=@openspec/changes/<slug>/logic-map.md`' "$STEP"
assert_fixed '#issuecomment-<id>' "$STEP"
assert_fixed '#note_<id>' "$STEP"

# --- report.md 的 ## 邏輯表 一行，重產時整行覆寫 ---
assert_fixed '## 邏輯表' "$STEP"
assert_fixed 'openspec/changes/<slug>/logic-map.md · 留言 <comment url> · <head sha 前 7 碼>' "$STEP"
assert_fixed 'overwrite the whole line' "$STEP"

# --- 失敗不擋 /pr ---
assert_fixed '產表失敗：<' "$STEP"
assert_fixed 'does not stop /pr' "$STEP"

# --- 超過上限不截斷（Scenario「表超過留言上限」）---
assert_fixed '65,536' "$STEP"
assert_fixed '1,000,000' "$STEP"
assert_fixed 'never truncate' "$STEP"
assert_fixed '超過留言上限' "$STEP"

# --- 更新：GitHub 讀回比對後才 --edit-last，對不上發新的；GitLab PUT 同一則 ---
assert_fixed '`gh pr view <n> --json comments`' "$STEP"
assert_fixed '`gh pr comment <n> --edit-last --body-file openspec/changes/<slug>/logic-map.md`' "$STEP"
assert_fixed 'post a new comment and replace the URL' "$STEP"
assert_fixed 'never edit any other comment' "$STEP"
assert_fixed '`glab api --method PUT "projects/:id/merge_requests/<iid>/notes/<note_id>" --field body=@openspec/changes/<slug>/logic-map.md`' "$STEP"
assert_not_fixed 'gh api' "$STEP"

# --- 每個 gh 呼叫單獨一個 Bash 指令 ---
assert_fixed 'its own Bash command' "$STEP"
