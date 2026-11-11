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
  '| # | 功能 | PR | 卡 | 測試 | 邏輯表 | PR 連結 |' \
  '進度 HH:MM · <current_milestone>：剩 N 張 · 可合併 a · 測試中 b · 開發中 c · 等你 d · 還沒派 e' \
  '| 功能（session） | 卡 | 優先度 | 階段 | 卡在 |' \
  '| 卡 | 發生什麼 | 我怎麼處理 | 開卡 |' \
  '絕對路徑' 'path:line' '絕不合併' 'me-20261111-1315' 'logic-map.md' 'report.md'; do
  grep -qF -- "$s" "$F" || fail "skill 缺：$s"
done

# 可合併只看 agent 的回報（review 完、相關測試綠、跟 main 無衝突）；多張一起合時只用 git merge-tree 查依序疊起來無衝突，不重跑全套
# 只看職責 4 那一段（從「4. 」到「5. 」），表格註解裡的字不算
D4="$(sed -n '/^4\. /,/^5\. /p' "$F")"
[ -n "$D4" ] || fail "找不到職責 4"
for s in 'reports review done' 'Do not rerun the suite yourself' 'git merge-tree --write-tree' 'git commit-tree'; do
  case "$D4" in *"$s"*) ;; *) fail "職責 4 缺：$s" ;; esac
done
case "$D4" in *"run the full suite"*|*"rerun the suite against"*) fail "職責 4 不能叫協調者自己重跑全套：$D4" ;; esac

# 去重是協調者的職責（specs/card-auto-merge「協調者 skill 寫明去重」）：Duties 裡有一條含 opsx merge-card 與同一件事，不受只併小事限制
DUTIES="$(sed -n '/^## Duties/,/^## Report format/p' "$F")"
DEDUP="$(printf '%s\n' "$DUTIES" | grep -F 'opsx merge-card')"
[ -n "$DEDUP" ] || fail "Duties 缺 opsx merge-card 的去重職責"
for s in '同一件事' '只併小事' 'decisions.tsv' '④'; do
  case "$DEDUP" in *"$s"*) ;; *) fail "去重職責缺：$s — $DEDUP" ;; esac
done

# frontmatter 的 name 是 lead（/opsx-workflow:lead）
assert_eq "$(sed -n 2p "$F")" "name: lead" "frontmatter name"
echo ok
