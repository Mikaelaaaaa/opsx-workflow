#!/usr/bin/env bash
# opsx split-out：把目標卡 inbox.md 裡的一段 ## 併入 拆回一張獨立的殼，再刪掉那一段。
# 驗收：specs/card-auto-merge「拆出來」每個 Scenario。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-11 10:40"
cd "$FX"

E="$(mk_opsx_repo e)"
C="$E/openspec/changes"
mkdir -p "$E/bin" "$E/.claude/worktrees"; printf 'x\n' > "$E/bin/x.sh"
git -C "$E" worktree add -q -b fix/foo/mikaela "$E/.claude/worktrees/foo" || fail "worktree foo 建不起來"
W="$(cd "$E/.claude/worktrees/foo" && pwd -P)"
OUT="$FX/out"; ERR="$FX/err"
ID=agent-20261111-1040

reset() { chmod -R u+w "$C" 2>/dev/null; rm -rf "$C"/*; }
card() { # card <slug> [frontmatter 行…]：只有 inbox.md、證據提到 bin/x.sh 的卡（stage explore）
  local s="$1"; shift
  mkdir -p "$C/$s"; printf 'schema: opsx\n' > "$C/$s/.openspec.yaml"
  { printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-10\nrelated:\nkind_of_work: planned\n'; [ $# -eq 0 ] || printf '%s\n' "$@"; printf -- '---\n\n## 一句話\n\n%s\n\n## 證據\n\n- 原本的證據 bin/x.sh\n' "$s"; } > "$C/$s/inbox.md"
}
# 併入靠共同檔案：預設帶 --evidence bin/x.sh，呼叫端再帶一次 --evidence 會蓋掉它
merge() { (cd "$W" && opsx new --repo "$E" --evidence bin/x.sh "$@") > /dev/null 2> "$ERR" || fail "併入失敗：$(cat "$ERR")"; }
split() { opsx split-out --repo "$E" "$@" > "$OUT" 2> "$ERR"; }
dirs() { find "$C" -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | LC_ALL=C sort | tr '\n' ' '; }

# --- 拆回獨立的卡 ---
# 併入時在段前補的空行不屬於那一段，拆完留著：x 是併入前的內容加一個空行
reset; card x; cp "$C/x/inbox.md" "$FX/orig.md"; printf '\n' >> "$FX/orig.md"
merge --kind-of-work planned --evidence "bin/x.sh 紅" -- 鉤子漏擋
assert_grep "^- id: $ID\$" "$C/x/inbox.md"
split x "$ID"; assert_eq "$?" 0 "拆出要退出 0：$(cat "$ERR")"
assert_eq "$(cat "$OUT")" "$ID" "stdout 是新 slug"
assert_eq "$(dirs)" "$ID x "
printf -- '---\ntype: bug\nsource: agent:foo\nfound: 2026-11-11\nrelated:\nkind_of_work: planned\nevidence: bin/x.sh 紅\n---\n\n## 一句話\n\n鉤子漏擋\n\n## 證據\n\n' > "$FX/want.md"
cmp -s "$C/$ID/inbox.md" "$FX/want.md" || fail "新殼 inbox.md 形狀不對：$(diff "$FX/want.md" "$C/$ID/inbox.md")"
assert_file "$C/$ID/.openspec.yaml"
assert_not_grep "$ID" "$C/x/inbox.md"
cmp -s "$C/x/inbox.md" "$FX/orig.md" || fail "刪段後 x/inbox.md 要回到併入前：$(diff "$FX/orig.md" "$C/x/inbox.md")"
assert_eq "$(find "$E/openspec" -maxdepth 1 -name '.reserve-*' | wc -l | tr -d ' ')" 0 "不留保留目錄"

# planned、沒有 impact/evidence 的段：新殼也不寫這兩行；段內 type 寫回去
reset; card x
(cd "$W" && opsx new --type 技術債 --kind-of-work planned --repo "$E" -- "bin/x.sh 沒有事實") > /dev/null 2> "$ERR" || fail "併入失敗：$(cat "$ERR")"
assert_grep "^- id: $ID\$" "$C/x/inbox.md"
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_grep '^source: agent:foo$' "$C/$ID/inbox.md"; assert_grep '^type: 技術債$' "$C/$ID/inbox.md"
assert_grep '^kind_of_work: planned$' "$C/$ID/inbox.md"; assert_grep '^bin/x.sh 沒有事實$' "$C/$ID/inbox.md"
assert_not_grep '^impact:' "$C/$ID/inbox.md"; assert_not_grep '^evidence:' "$C/$ID/inbox.md"; assert_not_grep '^area:' "$C/$ID/inbox.md"
assert_grep '^## 證據$' "$C/$ID/inbox.md"

# --- 拆出舊格式的段（只有 - area:）：type 寫待定，不寫 area ---
reset; card x
printf '\n## 併入：2026-11-11T10:40:00+08:00 agent:foo\n\n- id: %s\n- kind_of_work: planned\n- area: hooks\n\n舊段\n' "$ID" >> "$C/x/inbox.md"
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_grep '^type: 待定$' "$C/$ID/inbox.md"; assert_not_grep '^area:' "$C/$ID/inbox.md"; assert_grep '^舊段$' "$C/$ID/inbox.md"

# --- type 與 area 都沒有：退出 1，什麼都不改 ---
reset; card x
printf '\n## 併入：2026-11-11T10:40:00+08:00 agent:foo\n\n- id: %s\n- kind_of_work: planned\n\n沒有 type\n' "$ID" >> "$C/x/inbox.md"
cp "$C/x/inbox.md" "$FX/keep.md"
split x "$ID"; assert_eq "$?" 1 "type 與 area 都沒有要退出 1：$(cat "$ERR")"
assert_grep 'type' "$ERR"
cmp -s "$C/x/inbox.md" "$FX/keep.md" || fail "x/inbox.md 不該變"
assert_eq "$(dirs)" "x " "沒有新殼"

# --- 拆出整份縮排的段（opsx merge-card 寫的形狀，照抄磁碟上實際的段）---
IND=agent-20261118-1910
indented() { # indented <id> <縮排兩格的內文>：在 x/inbox.md 尾端加一段 merge-card 形狀的併入
  printf '\n## 併入：2026-11-20T17:35:20+08:00 agent:personal-skill\n\n- id: %s\n- kind_of_work: planned\n- type: bug\n\n%s\n' "$1" "$2" >> "$C/x/inbox.md"
}
reset; card x; cp "$C/x/inbox.md" "$FX/orig.md"; printf '\n' >> "$FX/orig.md"
indented "$IND" '  ## 一句話

  skill-retrieval 的 packages/db/drizzle/0351_skill_embeddings.sql 沒有 USING hnsw 索引（決策 A）

  ## 證據'
split x "$IND"; assert_eq "$?" 0 "拆縮排段要退出 0：$(cat "$ERR")"
assert_eq "$(cat "$OUT")" "$IND"
printf -- '---\ntype: bug\nsource: agent:personal-skill\nfound: 2026-11-20\nrelated:\nkind_of_work: planned\n---\n\n## 一句話\n\nskill-retrieval 的 packages/db/drizzle/0351_skill_embeddings.sql 沒有 USING hnsw 索引（決策 A）\n\n## 證據\n' > "$FX/want.md"
cmp -s "$C/$IND/inbox.md" "$FX/want.md" || fail "縮排段還原的 inbox.md 不對：$(diff "$FX/want.md" "$C/$IND/inbox.md")"
cmp -s "$C/x/inbox.md" "$FX/orig.md" || fail "刪段後 x/inbox.md 要回到併入前：$(diff "$FX/orig.md" "$C/x/inbox.md")"

# --- 拆出帶派工指示的縮排段：來源的其他段照順序整份保留 ---
reset; card x
indented "$IND" '  ## 一句話

  帶派工指示的來源

  ## 證據

  - bin/x.sh:3 紅

  ## 派工指示

  - 2026-11-20T10:00:00+08:00 P1：做到可合併'
split x "$IND"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$(grep -n -e '^## 一句話$' -e '^帶派工指示的來源$' -e '^## 證據$' -e '^- bin/x.sh:3 紅$' -e '^## 派工指示$' -e '^- 2026-11-20T10:00:00+08:00 P1：做到可合併$' "$C/$IND/inbox.md" | cut -d: -f1 | tr '\n' ' ')" "9 11 13 15 17 19 " "各段沒有縮排、照原順序：$(cat "$C/$IND/inbox.md")"
assert_not_grep '^  ' "$C/$IND/inbox.md"

# --- 縮排段格式不對（Scenario Outline m1–m3）：退出 1、x 不變、沒有新殼；m4 三格空白只去掉兩格 ---
badind() { # badind <id> <內文> <stderr 要含的字>
  reset; card x; indented "$1" "$2"; cp "$C/x/inbox.md" "$FX/keep.md"
  split x "$1"; assert_eq "$?" 1 "$1 要退出 1：$(cat "$ERR")"
  assert_grep "$3" "$ERR"
  cmp -s "$C/x/inbox.md" "$FX/keep.md" || fail "$1：x/inbox.md 不該變"
  assert_eq "$(dirs)" "x " "$1：沒有新殼"
}
badind m1 '  ## 一句話

  一句
沒縮排的行' 沒縮排的行
badind m2 '  ## 證據

  - 某證據' '沒有 ## 一句話（id m2）'
badind m3 '  ## 一句話

  ## 證據' '是空的（id m3）'
reset; card x
indented m4 '  ## 一句話

   多一格的一句'
split x m4; assert_eq "$?" 0 "m4 三格空白要拆得出：$(cat "$ERR")"
assert_grep '^ 多一格的一句$' "$C/m4/inbox.md"
# m5：標題尾端有空白仍算 ## 一句話
reset; card x
indented m5 $'  ## 一句話 \n\n  標題尾端有空白'
split x m5; assert_eq "$?" 0 "m5 標題尾端有空白要拆得出：$(cat "$ERR")"
assert_grep '^標題尾端有空白$' "$C/m5/inbox.md"

# --- 縮排段帶附件：附件隨來源卡歸檔，拆不出、指名歸檔位置、什麼都不改 ---
reset; card x
indented att1 '  ## 一句話

  帶附件的來源

  ## 附件

  - attachments/shot.png'
cp "$C/x/inbox.md" "$FX/keep.md"
split x att1; assert_eq "$?" 1 "帶附件要退出 1：$(cat "$ERR")"
assert_grep '## 附件' "$ERR"; assert_grep 'archive/\*-att1/attachments/' "$ERR"
cmp -s "$C/x/inbox.md" "$FX/keep.md" || fail "帶附件：x/inbox.md 不該變"
assert_eq "$(dirs)" "x " "帶附件：沒有新殼"

# --- merge-card 寫入再 split-out 讀回：新殼 frontmatter 之後的內容跟來源一模一樣 ---
reset; card x; card src
printf '\n## 派工指示\n\n- 2026-11-20T10:00:00+08:00 先跑 lint\n' >> "$C/src/inbox.md"
body() { awk 'n >= 2; /^---$/ { n++ }' "$1"; }
body "$C/src/inbox.md" > "$FX/src-body.md"
opsx merge-card src --into x --repo "$E" > /dev/null 2> "$ERR" || fail "merge-card 失敗：$(cat "$ERR")"
split x src; assert_eq "$?" 0 "往返拆回要退出 0：$(cat "$ERR")"
assert_eq "$(cat "$OUT")" src
body "$C/src/inbox.md" > "$FX/back-body.md"
cmp -s "$FX/src-body.md" "$FX/back-body.md" || fail "往返後內文要跟來源一樣：$(diff "$FX/src-body.md" "$FX/back-body.md")"

# --- 只刪那一段 ---
reset; card x; cp "$C/x/inbox.md" "$FX/orig.md"; printf '\n' >> "$FX/orig.md"
merge --kind-of-work planned -- 第一段
merge --kind-of-work planned -- 第二段
assert_eq "$(grep -c '^## 併入：' "$C/x/inbox.md")" 2 "fixture 要有兩段"
# 期望：第一段（標題到第二段標題前）整段不見，其他每個位元組都在
awk 'BEGIN { skip = 0 } /^## / { skip = ($0 ~ /^## 併入：/ && ++n == 1) } !skip' "$C/x/inbox.md" > "$FX/want.md"
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
cmp -s "$C/x/inbox.md" "$FX/want.md" || fail "只該刪第一段：$(diff "$FX/want.md" "$C/x/inbox.md")"
assert_grep "^- id: $ID-2\$" "$C/x/inbox.md"; assert_grep '^第二段$' "$C/x/inbox.md"
assert_grep '^- 原本的證據 bin/x.sh$' "$C/x/inbox.md"
assert_grep '^第一段$' "$C/$ID/inbox.md"
# 再拆最後一段（到檔尾）：x 回到沒有併入的樣子
split x "$ID-2"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$(cat "$OUT")" "$ID-2"
cmp -s "$C/x/inbox.md" "$FX/orig.md" || fail "拆完兩段要回到原樣：$(diff "$FX/orig.md" "$C/x/inbox.md")"

# --- 併入後 note 在檔尾長出 ## 派工指示：拆出併入段，派工指示一字不變 ---
reset; card x
merge --kind-of-work planned -- 先併入
opsx note x --repo "$E" 先跑 lint > /dev/null 2> "$ERR" || fail "note 失敗：$(cat "$ERR")"
assert_grep '^## 派工指示$' "$C/x/inbox.md"
awk '/^## / { skip = ($0 ~ /^## 併入：/) } !skip' "$C/x/inbox.md" > "$FX/want.md"
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
cmp -s "$C/x/inbox.md" "$FX/want.md" || fail "派工指示要一字不變：$(diff "$FX/want.md" "$C/x/inbox.md")"
assert_grep '先跑 lint$' "$C/x/inbox.md"

# --- 不會被併回去 ---
reset; card x
merge --kind-of-work planned -- 不併回
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$(dirs)" "$ID x " "建了新殼"
assert_not_grep '^## 併入：' "$C/x/inbox.md"

# --- 目標已進 apply 也能拆 ---
reset; card x
merge --kind-of-work planned -- 已有 tasks
printf '## 已知\n\n- a\n\n## 待決\n\n## 不做\n\n- c\n' > "$C/x/explore.md"
printf 'D1 a\n' > "$C/x/grill.md"; printf '## Why\n\na\n' > "$C/x/proposal.md"; printf -- '- [ ] 1.1 a\n' > "$C/x/tasks.md"
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$(cat "$OUT")" "$ID"; assert_not_grep "$ID" "$C/x/inbox.md"

# --- id 已被占用 ---
reset; card x
merge --kind-of-work planned -- 撞名
card "$ID"
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$(cat "$OUT")" "$ID-2" "被占用時加 -2"
assert_grep '^撞名$' "$C/$ID-2/inbox.md"
assert_grep "^$ID\$" "$C/$ID/inbox.md"

# --- 找不到那段 ---
reset; card x
merge --kind-of-work planned -- 留著
cp "$C/x/inbox.md" "$FX/keep.md"; cp "$C/x/decisions.tsv" "$FX/keep.tsv"
split x nope; assert_eq "$?" 2 "找不到要退出 2"
assert_grep nope "$ERR"; assert_eq "$(cat "$OUT")" "" "stdout 不印"
cmp -s "$C/x/inbox.md" "$FX/keep.md" || fail "x/inbox.md 不該變"
cmp -s "$C/x/decisions.tsv" "$FX/keep.tsv" || fail "x/decisions.tsv 不該多列"
assert_eq "$(dirs)" "x " "沒有新殼"
assert_eq "$(find "$E/openspec" -maxdepth 1 -name '.reserve-*' | wc -l | tr -d ' ')" 0 "不留保留目錄"
# 不在併入段裡的 - id: 不算（例如寫在 ## 證據）
card z; printf -- '- id: fake-1\n' >> "$C/z/inbox.md"
split z fake-1; assert_eq "$?" 2 "## 證據 裡的 - id: 不是併入段"
# 目標卡不存在
split nosuch "$ID"; assert_eq "$?" 2 "$(cat "$ERR")"; assert_grep nosuch "$ERR"

# --- 刪段失敗：新殼留著，stderr 說要手動刪哪一段 ---
reset; card x
merge --kind-of-work planned -- 刪不掉
chmod a-w "$C/x"
split x "$ID"; rc=$?
chmod u+w "$C/x"
[ "$rc" -ne 0 ] || fail "刪段失敗要退出非零"
assert_dir "$C/$ID"; assert_grep '^刪不掉$' "$C/$ID/inbox.md"
assert_grep "$ID" "$ERR"; assert_grep '手動' "$ERR"
assert_grep "^- id: $ID\$" "$C/x/inbox.md"

# --- 兩邊都有紀錄 ---
reset; card x
merge --kind-of-work planned -- 記兩邊
split x "$ID"; assert_eq "$?" 0 "$(cat "$ERR")"
case "$(tail -1 "$C/x/decisions.tsv")" in *拆出*"$ID"*) ;; *) fail "x/decisions.tsv 最後一列要含拆出與新 slug：$(cat "$C/x/decisions.tsv")" ;; esac
case "$(tail -1 "$C/$ID/decisions.tsv")" in *x*) ;; *) fail "新殼 decisions.tsv 要有一列含 x：$(cat "$C/$ID/decisions.tsv" 2>&1)" ;; esac

# --- 用法錯 ---
opsx split-out --repo "$E" x > "$OUT" 2> "$ERR"; assert_eq "$?" 2 "少參數要退出 2"

# ========== split-out-card-lock：讀段、建殼、刪段在目標卡同一個鎖內 ==========
PYBIN="$(cat "$OPSX_STATE_DIR/python")"; LIBDIR="$OPSX_ROOT/bin/lib"
hold_lock() { # hold_lock <卡目錄> [要在放鎖前刪掉的併入段 id]：持卡鎖，等 $FX/go 出現才（刪段後）放鎖
  rm -f "$FX/held" "$FX/go"
  "$PYBIN" -I -c '
import os, sys, time
sys.path.insert(0, sys.argv[1]); import safefile, inboxmerge
card = sys.argv[2]
with safefile.CardLock(card):
    open(sys.argv[3], "w").close()
    while not os.path.exists(sys.argv[4]):
        time.sleep(0.02)
    if len(sys.argv) > 5:
        p = os.path.join(card, "inbox.md")
        with open(p, encoding="utf-8") as f:
            cur = f.read()
        a, b = inboxmerge.find(cur, sys.argv[5])
        lines = cur.splitlines(keepends=True)
        safefile.write_atomic(p, "".join(lines[:a] + lines[b:]))
' "$LIBDIR" "$1" "$FX/held" "$FX/go" ${2:+"$2"} &
  HOLDER=$!
  for _ in $(seq 100); do [ -e "$FX/held" ] && break; sleep 0.05; done
  [ -e "$FX/held" ] || fail "持鎖的 process 沒有拿到鎖"
}

# --- 兩處同時拆同一個 id：恰好一個成功，只多一張殼 ---
reset; card x hooks
merge --kind-of-work planned -- 同時拆
hold_lock "$C/x"
opsx split-out --repo "$E" x "$ID" > "$FX/s1.out" 2> "$FX/s1.err" &
S1=$!
opsx split-out --repo "$E" x "$ID" > "$FX/s2.out" 2> "$FX/s2.err" &
S2=$!
sleep 1; : > "$FX/go"
wait "$HOLDER"; wait "$S1"; rc1=$?; wait "$S2"; rc2=$?
assert_eq "$(( (rc1 == 0) + (rc2 == 0) ))" 1 "恰好一個成功：rc $rc1 $rc2"
assert_eq "$(dirs)" "$ID x " "只多一張殼：$(cat "$FX/s1.err" "$FX/s2.err")"
if [ "$rc1" -eq 0 ]; then bad="$FX/s2.err"; else bad="$FX/s1.err"; fi
assert_grep "$ID" "$bad"

# --- 取得鎖時那一段已被刪：非 0 退出、沒有建殼、目標卡不變 ---
reset; card x hooks
merge --kind-of-work planned -- 被先刪掉
hold_lock "$C/x" "$ID"
opsx split-out --repo "$E" x "$ID" > "$OUT" 2> "$ERR" &
S1=$!
sleep 1; : > "$FX/go"
wait "$HOLDER"; wait "$S1"; rc=$?
assert_eq "$rc" 2 "段被刪掉要退出 2：$(cat "$ERR")"
assert_grep "$ID" "$ERR"; assert_eq "$(dirs)" "x " "沒有新殼"
assert_not_grep "$ID" "$C/x/inbox.md"

# --- 鎖內建殼失敗：非 0 退出，併入段仍在，沒有殼 ---
reset; card x hooks
merge --kind-of-work planned -- 建不起來
mkdir -p "$FX/failopenspec"; printf '#!/usr/bin/env bash\necho "openspec: 壞了" >&2\nexit 1\n' > "$FX/failopenspec/openspec"; chmod +x "$FX/failopenspec/openspec"
cp "$C/x/inbox.md" "$FX/keep.md"
PATH="$FX/failopenspec:$PATH" split x "$ID"; rc=$?
[ "$rc" -ne 0 ] || fail "建殼失敗要退出非零"
cmp -s "$C/x/inbox.md" "$FX/keep.md" || fail "建殼失敗不能刪段：$(diff "$FX/keep.md" "$C/x/inbox.md")"
assert_eq "$(dirs)" "x " "沒有新殼"
assert_eq "$(find "$E/openspec" -maxdepth 1 -name '.reserve-*' | wc -l | tr -d ' ')" 0 "不留保留目錄"
echo ok
