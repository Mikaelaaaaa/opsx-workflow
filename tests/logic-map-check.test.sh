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

# --- 校正：第一輪 eval 的真 PR 裡被誤判的判斷寫法（awk 樣式行、推導式的 if、jq -e）---
printf '%s\n' 'awk '"'"'' '/^status:[ \t]*open[ \t]*$/ { open = 1 }' 'named = [i for i in titled if title_of(parts[i]) == gate]' '  jq -e --argjson now "$now" '"'"'' 'cp a b' 'print("if you like")' > "$repo/more.sh"
git -C "$repo" add more.sh
git -C "$repo" commit -q -m more
judged() { # judged <行號> <期望 0|1>
  write_map "$FX/j.md" "more.sh:$1" "" ""
  if run_check "$FX/j.md"; then got=0; else got=1; fi
  assert_eq "$got" "$2" "more.sh:$1 $(sed -n "$1p" "$repo/more.sh") — $(cat "$FX/err")"
}
judged 2 0
judged 3 0
judged 4 0
judged 5 1
judged 6 1

# 收緊：命令串接、註解、字串裡的關鍵字都不算判斷；&& / || 左邊是測試才算
printf '%s\n' 'mkdir -p "$d" && cd "$d"' '# retry later || give up' 'echo "use a && b"' 'msg = "skip if empty else run"' 'log("for x in y if z")' '[ -d "$t" ] && export X="$t"' '! grep -q x f || exit 0' 'test -f a && rm a' 's="${s%/}"; [ -f "$s/status.json" ] || continue' 'is_open "$d" || [ "$g" = gated ] || write "$d"' > "$repo/tight.sh"
git -C "$repo" add tight.sh
git -C "$repo" commit -q -m tight
tight() { # tight <行號> <期望 0|1>
  write_map "$FX/t.md" "tight.sh:$1" "" ""
  if run_check "$FX/t.md"; then got=0; else got=1; fi
  assert_eq "$got" "$2" "tight.sh:$1 $(sed -n "$1p" "$repo/tight.sh") — $(cat "$FX/err")"
}
tight 1 1
tight 2 1
tight 3 1
tight 4 1
tight 5 1
tight 6 0
tight 7 0
tight 8 0
tight 9 0
tight 10 0

# 第 2 輪校正：註解（整行與行尾）不算；skills/ 底下 .md 的標題不算
printf '%s\n' '# skip if empty else run' 'n=3  # grep -q x' > "$repo/comments.sh"
git -C "$repo" add comments.sh
git -C "$repo" commit -q -m comments
write_map "$FX/c1.md" comments.sh:1 "" ""
expect_bad "$FX/c1.md" "comments.sh:1 不是判斷行"
write_map "$FX/c2.md" comments.sh:2 "" ""
expect_bad "$FX/c2.md" "comments.sh:2 不是判斷行"

# 真 PR 裡的判斷寫法：述詞呼叫接控制流程、行中的 case、awk 運算式樣式
real() { # real <commit> <path:line>
  write_map "$FX/real.md" "$2" "" ""
  python3 -I "$CHECK" "$OPSX_ROOT" "$1" "$FX/real.md" 2> "$FX/err" || fail "$1 $2 被拒：$(cat "$FX/err")"
}
real 8389924 hooks/openspec-stop-gate.sh:35
real 7b30eef hooks/openspec-commit-gate.sh:13
real 7b30eef hooks/openspec-commit-gate.sh:25
real 24b2c40 hooks/gate-timestamp.sh:69

# 一個 D 都沒有的功能：流程圖與條件表都空也不能通過
printf '# 邏輯表：fix/x/dev\n\n## 功能 1：空\n\n### 做了什麼\n1. 無。\n\n### 流程圖\n```\n輸入 → 結束\n```\n\n### 條件表\n| 節點 | 決策 | 條件（FEEL） | 結果 | 位置 |\n|---|---|---|---|---|\n\n### ⚠ 要看的地方\n- 無\n' > "$FX/empty.md"
expect_bad "$FX/empty.md" "沒有任何 D 節點"

# .md 例外只限 skills/ 底下的 skill 檔
mkdir -p "$repo/skills/x"
printf '# x\n\n1. When the report is not NEEDS-USER, mark it done.\n' > "$repo/skills/x/SKILL.md"
printf '# Title\n' > "$repo/README.md"
git -C "$repo" add skills/x/SKILL.md README.md
git -C "$repo" commit -q -m docs
write_map "$FX/skillmd.md" skills/x/SKILL.md:3 "" ""
run_check "$FX/skillmd.md" || fail "skills/ 底下的 SKILL.md 指示行被拒：$(cat "$FX/err")"
write_map "$FX/md-heading.md" skills/x/SKILL.md:1 "" ""
expect_bad "$FX/md-heading.md" "skills/x/SKILL.md:1 不是判斷行"
write_map "$FX/md-blank.md" skills/x/SKILL.md:2 "" ""
expect_bad "$FX/md-blank.md" "skills/x/SKILL.md:2 不是判斷行"
write_map "$FX/md-missing.md" skills/x/SKILL.md:30 "" ""
expect_bad "$FX/md-missing.md" "skills/x/SKILL.md:30 不存在"
write_map "$FX/readme.md" README.md:1 "" ""
expect_bad "$FX/readme.md" "README.md:1 不是判斷行"

# --- 校正：examples.md 的範例 1、2 對它們的 commit 要通過 ---
EX="$OPSX_ROOT/skills/logic-map/references/examples.md"
awk '/^## Example 1:/{on=1;next} /^## Example 2:/{on=0} on' "$EX" > "$FX/ex1.md"
awk '/^## Example 2:/{on=1;next} /^## Example 3:/{on=0} on' "$EX" > "$FX/ex2.md"
python3 -I "$CHECK" "$OPSX_ROOT" 7b30eef "$FX/ex1.md" 2> "$FX/err" || fail "範例 1 對 7b30eef 被拒：$(cat "$FX/err")"
python3 -I "$CHECK" "$OPSX_ROOT" 6312881 "$FX/ex2.md" 2> "$FX/err" || fail "範例 2 對 6312881 被拒：$(cat "$FX/err")"

# --- 參數錯：退出碼 2 ---
assert_rc 2 python3 -I "$CHECK" "$repo" HEAD
assert_rc 2 python3 -I "$CHECK" "$repo" HEAD "$FX/no-such.md"
