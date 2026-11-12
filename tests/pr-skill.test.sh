#!/usr/bin/env bash
# skills/pr/SKILL.md 步 5c：派 logic-map subagent 產表，只寫檔，report.md 記路徑與 head sha，不發留言。
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
if lines[2].strip() != "output: <map path>":
    sys.exit("輸出路徑：%r" % lines[2])
if "../logic-map/SKILL.md" not in lines[3]:
    sys.exit("skill 路徑：%r" % lines[3])
PY
for k in 'spec' 'proposal' 'design' 'report' 'conversation' 'PR title or description'; do
  grep -F 'Nothing else goes into the prompt' "$STEP" | grep -qF -- "$k" || fail "禁止清單缺 $k"
done

# --- 只產檔：不發留言、不改留言、不查字數上限 ---
for k in 'comment' '留言' 'gh pr' 'glab api' '--edit-last' 'viewerDidAuthor' '65,536' '1,000,000'; do
  assert_not_fixed "$k" "$STEP"
done

# --- R1.2 路徑用絕對路徑：dispatch worktree 的 cwd 沒有 openspec/ ---
assert_fixed '`<map path>` is the absolute path of `openspec/changes/<slug>/logic-map.md` in the checkout that holds `openspec/`' "$STEP"

# --- report.md 的 ## 邏輯表 一行：路徑加 head sha，重產時整行覆寫 ---
assert_fixed '## 邏輯表' "$STEP"
assert_fixed 'openspec/changes/<slug>/logic-map.md · <head sha 前 7 碼>' "$STEP"
assert_fixed 'overwrite the whole line' "$STEP"

# --- 失敗不擋 /pr；失敗行只記原因 ---
assert_fixed '產表失敗：<' "$STEP"
assert_fixed 'does not stop /pr' "$STEP"
assert_fixed '`產表失敗：<reason>`' "$STEP"
assert_fixed 'never build the map in this session' "$STEP"
assert_fixed '產表失敗：無 Agent 工具' "$STEP"
assert_not_fixed 'go on to step 6' "$STEP"
assert_fixed "go on to the caller's next step" "$STEP"

# --- R2.1 派之前刪掉上一輪的表，產表失敗才看得出來；fetch 失敗也是產表失敗 ---
assert_fixed 'Delete `<map path>` before spawning' "$STEP"
python3 -I - "$STEP" <<'PY' || fail "刪檔不在派 subagent 之前"
import sys
text = open(sys.argv[1], encoding="utf-8").read()
if not text.index("Delete `<map path>`") < text.index("Spawn one fresh subagent"):
    sys.exit("刪檔在派之後")
PY
assert_fixed '產表失敗：fetch 失敗' "$STEP"

# --- R2.2 失敗行整行取代 ## 邏輯表 那一行；交叉引用寫子步編號 ---
assert_fixed 'replaces the one line under `## 邏輯表`' "$STEP"
assert_not_fixed 'as in step 3' "$STEP"

# --- pr 與 babysit 用同一個段名與輸出路徑（Scenario「段名與路徑一致」）---
BS="$OPSX_ROOT/skills/babysit/SKILL.md"
for f in "$SK" "$BS"; do
  assert_fixed '## 邏輯表' "$f"
  assert_fixed 'openspec/changes/<slug>/logic-map.md' "$f"
done
