#!/usr/bin/env bash
# opsx split-out：把目標卡 inbox.md 裡的一段 ## 併入 拆回一張獨立的殼，再刪掉那一段。
# 驗收：openspec/changes/new-auto-merge/subs/card-split-out/specs/card-auto-merge/spec.md 每個 Scenario。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-11 10:40"
cd "$FX"

E="$(mk_opsx_repo e)"
C="$E/openspec/changes"
printf 'hooks\nboard\n' > "$E/openspec/areas.txt"
mkdir -p "$E/.claude/worktrees"
git -C "$E" worktree add -q -b fix/foo/mikaela "$E/.claude/worktrees/foo" || fail "worktree foo 建不起來"
W="$(cd "$E/.claude/worktrees/foo" && pwd -P)"
OUT="$FX/out"; ERR="$FX/err"
ID=agent-20261111-1040

reset() { chmod -R u+w "$C" 2>/dev/null; rm -rf "$C"/*; }
card() { # card <slug> <area> [frontmatter 行…]：只有 inbox.md 的卡（stage explore）
  local s="$1" a="$2"; shift 2
  mkdir -p "$C/$s"; printf 'schema: opsx\n' > "$C/$s/.openspec.yaml"
  { printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-10\nrelated:\nkind_of_work: planned\narea: %s\n' "$a"; [ $# -eq 0 ] || printf '%s\n' "$@"; printf -- '---\n\n## 一句話\n\n%s\n\n## 證據\n\n- 原本的證據\n' "$s"; } > "$C/$s/inbox.md"
}
merge() { (cd "$W" && opsx new --area hooks --repo "$E" "$@") > /dev/null 2> "$ERR" || fail "併入失敗：$(cat "$ERR")"; }
split() { opsx split-out --repo "$E" "$@" > "$OUT" 2> "$ERR"; }
dirs() { find "$C" -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | LC_ALL=C sort | tr '\n' ' '; }

# --- 拆回獨立的卡 ---
# 併入時在段前補的空行不屬於那一段，拆完留著：x 是併入前的內容加一個空行
# P1 incident 只能併進 P1 以上的卡，所以目標用使用者覆寫成 P1
reset; card x hooks "priority: P1" "priority_reason: 測試"; cp "$C/x/inbox.md" "$FX/orig.md"; printf '\n' >> "$FX/orig.md"
merge --kind-of-work incident --impact workaround_exists --evidence "tests/a.test.sh 紅" -- 鉤子漏擋
assert_grep "^- id: $ID\$" "$C/x/inbox.md"
split x "$ID"; assert_eq "$?" 0 "拆出要退出 0：$(cat "$ERR")"
assert_eq "$(cat "$OUT")" "$ID" "stdout 是新 slug"
assert_eq "$(dirs)" "$ID x "
printf -- '---\ntype: 功能\nsource: agent:foo\nfound: 2026-11-11\nrelated:\nkind_of_work: incident\nimpact: workaround_exists\nevidence: tests/a.test.sh 紅\narea: hooks\n---\n\n## 一句話\n\n鉤子漏擋\n\n## 證據\n\n' > "$FX/want.md"
cmp -s "$C/$ID/inbox.md" "$FX/want.md" || fail "新殼 inbox.md 形狀不對：$(diff "$FX/want.md" "$C/$ID/inbox.md")"
assert_file "$C/$ID/.openspec.yaml"
assert_not_grep "$ID" "$C/x/inbox.md"
cmp -s "$C/x/inbox.md" "$FX/orig.md" || fail "刪段後 x/inbox.md 要回到併入前：$(diff "$FX/orig.md" "$C/x/inbox.md")"
assert_eq "$(find "$E/openspec" -maxdepth 1 -name '.reserve-*' | wc -l | tr -d ' ')" 0 "不留保留目錄"

# planned、沒有 impact/evidence 的段：新殼也不寫這兩行
reset; card x hooks
merge --kind-of-work planned -- 沒有事實
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_grep '^source: agent:foo$' "$C/$ID/inbox.md"; assert_grep '^area: hooks$' "$C/$ID/inbox.md"
assert_grep '^kind_of_work: planned$' "$C/$ID/inbox.md"; assert_grep '^沒有事實$' "$C/$ID/inbox.md"
assert_not_grep '^impact:' "$C/$ID/inbox.md"; assert_not_grep '^evidence:' "$C/$ID/inbox.md"
assert_grep '^## 證據$' "$C/$ID/inbox.md"

# --- 只刪那一段 ---
reset; card x hooks; cp "$C/x/inbox.md" "$FX/orig.md"; printf '\n' >> "$FX/orig.md"
merge --kind-of-work planned -- 第一段
merge --kind-of-work planned -- 第二段
assert_eq "$(grep -c '^## 併入：' "$C/x/inbox.md")" 2 "fixture 要有兩段"
# 期望：第一段（標題到第二段標題前）整段不見，其他每個位元組都在
awk 'BEGIN { skip = 0 } /^## / { skip = ($0 ~ /^## 併入：/ && ++n == 1) } !skip' "$C/x/inbox.md" > "$FX/want.md"
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
cmp -s "$C/x/inbox.md" "$FX/want.md" || fail "只該刪第一段：$(diff "$FX/want.md" "$C/x/inbox.md")"
assert_grep "^- id: $ID-2\$" "$C/x/inbox.md"; assert_grep '^第二段$' "$C/x/inbox.md"
assert_grep '^- 原本的證據$' "$C/x/inbox.md"
assert_grep '^第一段$' "$C/$ID/inbox.md"
# 再拆最後一段（到檔尾）：x 回到沒有併入的樣子
split x "$ID-2"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$(cat "$OUT")" "$ID-2"
cmp -s "$C/x/inbox.md" "$FX/orig.md" || fail "拆完兩段要回到原樣：$(diff "$FX/orig.md" "$C/x/inbox.md")"

# --- 併入後 note 在檔尾長出 ## 派工指示：拆出併入段，派工指示一字不變 ---
reset; card x hooks
merge --kind-of-work planned -- 先併入
opsx note x --repo "$E" 先跑 lint > /dev/null 2> "$ERR" || fail "note 失敗：$(cat "$ERR")"
assert_grep '^## 派工指示$' "$C/x/inbox.md"
awk '/^## / { skip = ($0 ~ /^## 併入：/) } !skip' "$C/x/inbox.md" > "$FX/want.md"
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
cmp -s "$C/x/inbox.md" "$FX/want.md" || fail "派工指示要一字不變：$(diff "$FX/want.md" "$C/x/inbox.md")"
assert_grep '先跑 lint$' "$C/x/inbox.md"

# --- 不會被併回去 ---
reset; card x hooks
merge --kind-of-work planned -- 不併回
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$(dirs)" "$ID x " "建了新殼"
assert_not_grep '^## 併入：' "$C/x/inbox.md"

# --- 目標已進 apply 也能拆 ---
reset; card x hooks
merge --kind-of-work planned -- 已有 tasks
printf '## 已知\n\n- a\n\n## 待決\n\n## 不做\n\n- c\n' > "$C/x/explore.md"
printf 'D1 a\n' > "$C/x/grill.md"; printf '## Why\n\na\n' > "$C/x/proposal.md"; printf -- '- [ ] 1.1 a\n' > "$C/x/tasks.md"
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$(cat "$OUT")" "$ID"; assert_not_grep "$ID" "$C/x/inbox.md"

# --- id 已被占用 ---
reset; card x hooks
merge --kind-of-work planned -- 撞名
card "$ID" board
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$(cat "$OUT")" "$ID-2" "被占用時加 -2"
assert_grep '^撞名$' "$C/$ID-2/inbox.md"
assert_grep "^$ID\$" "$C/$ID/inbox.md"

# --- 找不到那段 ---
reset; card x hooks
merge --kind-of-work planned -- 留著
cp "$C/x/inbox.md" "$FX/keep.md"; cp "$C/x/decisions.tsv" "$FX/keep.tsv"
split x nope; assert_eq "$?" 2 "找不到要退出 2"
assert_grep nope "$ERR"; assert_eq "$(cat "$OUT")" "" "stdout 不印"
cmp -s "$C/x/inbox.md" "$FX/keep.md" || fail "x/inbox.md 不該變"
cmp -s "$C/x/decisions.tsv" "$FX/keep.tsv" || fail "x/decisions.tsv 不該多列"
assert_eq "$(dirs)" "x " "沒有新殼"
assert_eq "$(find "$E/openspec" -maxdepth 1 -name '.reserve-*' | wc -l | tr -d ' ')" 0 "不留保留目錄"
# 不在併入段裡的 - id: 不算（例如寫在 ## 證據）
card z board; printf -- '- id: fake-1\n' >> "$C/z/inbox.md"
split z fake-1; assert_eq "$?" 2 "## 證據 裡的 - id: 不是併入段"
# 目標卡不存在
split nosuch "$ID"; assert_eq "$?" 2 "$(cat "$ERR")"; assert_grep nosuch "$ERR"

# --- 刪段失敗：新殼留著，stderr 說要手動刪哪一段 ---
reset; card x hooks
merge --kind-of-work planned -- 刪不掉
chmod a-w "$C/x"
split x "$ID"; rc=$?
chmod u+w "$C/x"
[ "$rc" -ne 0 ] || fail "刪段失敗要退出非零"
assert_dir "$C/$ID"; assert_grep '^刪不掉$' "$C/$ID/inbox.md"
assert_grep "$ID" "$ERR"; assert_grep '手動' "$ERR"
assert_grep "^- id: $ID\$" "$C/x/inbox.md"

# --- 兩邊都有紀錄 ---
reset; card x hooks
merge --kind-of-work planned -- 記兩邊
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
case "$(tail -1 "$C/x/decisions.tsv")" in *拆出*"$ID"*) ;; *) fail "x/decisions.tsv 最後一列要含拆出與新 slug：$(cat "$C/x/decisions.tsv")" ;; esac
case "$(tail -1 "$C/$ID/decisions.tsv")" in *x*) ;; *) fail "新殼 decisions.tsv 要有一列含 x：$(cat "$C/$ID/decisions.tsv" 2>&1)" ;; esac

# --- 用法錯 ---
opsx split-out --repo "$E" x > "$OUT" 2> "$ERR"; assert_eq "$?" 2 "少參數要退出 2"
echo ok
