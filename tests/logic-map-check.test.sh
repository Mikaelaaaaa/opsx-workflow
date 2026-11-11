#!/usr/bin/env bash
# skills/logic-map/evals/check_map.py：位置的行存在且是判斷行、D 節點流程圖與條件表一一對應、不收 mermaid。
# 對應 openspec/changes/logic-map-skill/subs/eval-fixtures/specs/logic-map「離線檢查邏輯表」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CHECK="$OPSX_ROOT/skills/logic-map/evals/check_map.py"
assert_file "$CHECK"

repo="$(mk_repo hookrepo)"
printf '#!/usr/bin/env bash\nx="$1"\nif [ -z "$x" ]; then\n  exit 0\nfi\n' > "$repo/hook.sh"
git -C "$repo" add hook.sh
git -C "$repo" commit -q -m add

write_map() { # write_map <file> <位置> <流程圖額外一行> <圍欄語言>
  printf '# 邏輯表：fix/x/dev\n\n## 功能 1：空參數放行\n\n### 做了什麼\n1. 沒參數就結束。\n\n### 流程圖\n```%s\n參數 → D1 是空的? ─是→ 結束\n%s\n```\n\n### 條件表\n| 節點 | 決策 | 條件（FEEL） | 結果 | 位置 |\n|---|---|---|---|---|\n| D1 | 是空的? | `x = ""` | 是 → 結束 | %s |\n\n### ⚠ 要看的地方\n- 無\n' "$4" "$3" "$2" > "$1"
}
run_check() { python3 -I "$CHECK" "$repo" HEAD "$1" 2> "$FX/err"; }

# --- 合格的邏輯表通過（正例）---
write_map "$FX/good.md" hook.sh:3 "" ""
run_check "$FX/good.md" || fail "合格的邏輯表被拒：$(cat "$FX/err")"

# --- 不合格的邏輯表失敗（Scenario Outline，反例）---
expect_bad() { # expect_bad <map> <訊息>
  if run_check "$1"; then fail "$(basename "$1") 應該失敗"; fi
  grep -qF -- "$2" "$FX/err" || fail "stderr 沒有 '$2'：$(cat "$FX/err")"
}
write_map "$FX/missing.md" hook.sh:99 "" ""
expect_bad "$FX/missing.md" "hook.sh:99 不存在"
write_map "$FX/shebang.md" hook.sh:1 "" ""
expect_bad "$FX/shebang.md" "hook.sh:1 不是判斷行"
write_map "$FX/extra-node.md" hook.sh:3 "        └否→ D2 有值? ─是→ 跑" ""
expect_bad "$FX/extra-node.md" "D2"
write_map "$FX/mermaid.md" hook.sh:3 "" "mermaid"
expect_bad "$FX/mermaid.md" "mermaid"
# 條件表多一列、流程圖沒有：也要點名
awk '{print} /^\| D1 \|/{print "| D3 | 多的 | `y` | 是 → 跑 | hook.sh:3 |"}' "$FX/good.md" > "$FX/extra-row.md"
expect_bad "$FX/extra-row.md" "D3"
# 檔案在 head 不存在
write_map "$FX/nofile.md" nope.sh:3 "" ""
expect_bad "$FX/nofile.md" "nope.sh:3 不存在"
# 位置欄空著：不能悄悄當作通過
write_map "$FX/nopos.md" "" "" ""
expect_bad "$FX/nopos.md" "D1"

# --- 校正：examples.md 的範例 1、2 對它們的 commit 要通過 ---
EX="$OPSX_ROOT/skills/logic-map/references/examples.md"
awk '/^## Example 1:/{on=1;next} /^## Example 2:/{on=0} on' "$EX" > "$FX/ex1.md"
awk '/^## Example 2:/{on=1;next} /^## Example 3:/{on=0} on' "$EX" > "$FX/ex2.md"
python3 -I "$CHECK" "$OPSX_ROOT" 7b30eef "$FX/ex1.md" 2> "$FX/err" || fail "範例 1 對 7b30eef 被拒：$(cat "$FX/err")"
python3 -I "$CHECK" "$OPSX_ROOT" 6312881 "$FX/ex2.md" 2> "$FX/err" || fail "範例 2 對 6312881 被拒：$(cat "$FX/err")"

# --- 參數錯：退出碼 2 ---
assert_rc 2 python3 -I "$CHECK" "$repo" HEAD
assert_rc 2 python3 -I "$CHECK" "$repo" HEAD "$FX/no-such.md"
