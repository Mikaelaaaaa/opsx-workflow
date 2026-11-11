#!/usr/bin/env bash
# skills/lead/SKILL.md：協調者的職責與五塊回報格式。specs/opsx-lead/spec.md「協調者 skill 寫明職責與五塊回報格式」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
F="$OPSX_ROOT/skills/lead/SKILL.md"
assert_file "$F"

# 五塊依序出現
line_of() { grep -nF -- "$1" "$F" | head -1 | cut -d: -f1; }
prev=0
for h in '① 要你處理' '② 可合併（依序）' '③ 進度' '④ 我處理掉的' '⑤ 最後一行'; do
  n="$(line_of "$h")"; [ -n "$n" ] || fail "缺區塊標題：$h"
  [ "$n" -gt "$prev" ] || fail "區塊順序錯：$h 在第 $n 行，前一塊在第 $prev 行"
  prev="$n"
done

# 每塊的欄名
for s in \
  '| # | 卡 | 問什麼 | 我的建議 | 詳情 |' \
  '→ 回『1 照建議』即可' \
  '| # | 功能 | PR | 卡 | 全套 | 邏輯表 | PR 連結 |' \
  '進度 HH:MM · <current_milestone>：剩 N 張 · 可合併 a · 測試中 b · 開發中 c · 等你 d · 還沒派 e' \
  '| 功能（session） | 卡 | 優先度 | 階段 | 卡在 |' \
  '| 卡 | 發生什麼 | 我怎麼處理 | 開卡 |' \
  '絕對路徑' 'path:line' '絕不合併' 'me-20261111-1315' 'logic-map.md' 'report.md'; do
  grep -qF -- "$s" "$F" || fail "skill 缺：$s"
done

# 可合併只看 agent 的回報（review 完、全套綠、跟 main 無衝突）；多張一起合時只用 git merge-tree 查依序疊起來無衝突，不重跑全套
grep -qF 'git merge-tree' "$F" || fail "skill 要寫多張一起合時用 git merge-tree 查依序疊起來無衝突"
! grep -qiE 'run the full suite yourself|自己.*跑全套' "$F" || fail "協調者列可合併前不自己重跑全套（使用者 2026-11-11 更正）"

# frontmatter 的 name 是 lead（/opsx-workflow:lead）
assert_eq "$(sed -n 2p "$F")" "name: lead" "frontmatter name"
echo ok
