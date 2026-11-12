#!/usr/bin/env bash
# opsx merge-card：併進既有的卡。驗收：specs/board-actions「併進既有的卡」（board-merge-card / merge-card-cli 1.1–1.3）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-10 09:00"
mkdir -p "$OPSX_STATE_DIR"
ROOT="$FX/code"; mkdir -p "$ROOT"
cd "$ROOT"   # 從 dispatch 的 worktree 跑時，cwd 不能讓 opsx new 把 fixture 的卡當成 agent 開的
A="$(mk_opsx_repo a)"; mv "$A" "$ROOT/a"; A="$(cd "$ROOT/a" && pwd -P)"
CH="$A/openspec/changes"
snap() { find "$CH" -type f -exec shasum {} + | sort; }
# 證據段最後一行非空內容
last_evidence() { awk '/^## 證據$/{f=1;next} /^## /{f=0} f && NF{l=$0} END{print l}' "$1"; }
archived() { local a=("$CH"/archive/*-"$1"); [ "${#a[@]}" -eq 1 ] && [ -d "${a[0]}" ] || fail "archive/*-$1：${a[*]}"; printf '%s' "${a[0]}"; }

# ========== 1.1 成功路徑 ==========
# --- 併進既有的卡：來源有 upstream_url；目標證據段後面還有別的段 ---
X="$(opsx new --repo "$A" -- 同步進來的)"; export OPSX_TEST_NOW="2026-11-10 09:01"; Y="$(opsx new --repo "$A" -- 自己記的)"
printf -- '---\ntype: 功能\nsource: github:o/r#12\nupstream_url: https://github.com/o/r/issues/12\nfound: 2026-11-10\n---\n\n## 一句話\n\n同步進來的\n\n## 證據\n\n- 上游 issue\n' > "$CH/$X/inbox.md"
printf '\n- 既有的證據\n\n## 派工指示\n\n- 先做 A\n' >> "$CH/$Y/inbox.md"
yaml_before="$(shasum "$CH/$Y/.openspec.yaml")"
out="$(opsx merge-card "$X" --into "$Y" --repo "$A" 2>&1)"; assert_eq "$?" 0 "merge-card: $out"
assert_no_file "$CH/$X"
D="$(archived "$X")"
assert_grep '^outcome: declined$' "$D/.openspec.yaml"
assert_grep '^## 捨棄理由$' "$D/inbox.md"; assert_grep "^併入 a/$Y\$" "$D/inbox.md"
assert_eq "$(last_evidence "$CH/$Y/inbox.md")" "- 併進：a/$X · source: github:o/r#12 · https://github.com/o/r/issues/12"
assert_grep '^- 既有的證據$' "$CH/$Y/inbox.md"
assert_eq "$(awk '/^## 派工指示$/{f=1;next} /^## /{f=0} f && NF' "$CH/$Y/inbox.md")" "- 先做 A" "派工指示段不動"
assert_eq "$(grep -c '併進：' "$CH/$Y/inbox.md")" 1 "證據行只寫一次"
tail -1 "$CH/$Y/decisions.tsv" | grep -q $'\t你\t已決定\t併進：a/'"$X"$'\t' || fail "目標 decisions.tsv 最後一列：$(tail -1 "$CH/$Y/decisions.tsv")"
assert_eq "$(shasum "$CH/$Y/.openspec.yaml")" "$yaml_before" "目標 .openspec.yaml 不變"
assert_dir "$CH/$Y"

# --- 來源沒有上游連結：opsx new 建的（source: me）---
export OPSX_TEST_NOW="2026-11-10 09:02"; M="$(opsx new --repo "$A" -- 重複的)"
assert_rc 0 opsx merge-card "$M" --into "$Y" --repo "$A"
assert_eq "$(last_evidence "$CH/$Y/inbox.md")" "- 併進：a/$M · source: me"
archived "$M" >/dev/null

# --- 目標證據段是空的（opsx new 剛建）：證據行接在標題後的空行之後 ---
export OPSX_TEST_NOW="2026-11-10 09:05"; E="$(opsx new --repo "$A" -- 空證據的目標)"
export OPSX_TEST_NOW="2026-11-10 09:06"; F="$(opsx new --repo "$A" -- 併進空證據)"
assert_rc 0 opsx merge-card "$F" --into "$E" --repo "$A"
assert_eq "$(awk '/^## 證據$/{f=1} /^## 併入：/{f=0} f' "$CH/$E/inbox.md")" "$(printf '## 證據\n\n- 併進：a/%s · source: me' "$F")"
rm -rf "$CH/$E"

# --- 來源卡全文進併入段（board-actions「merge-card 帶來源卡全文進併入段」）---
export OPSX_TEST_NOW="2026-11-10 09:07"; G="$(opsx new --repo "$A" -- 目標卡)"; export OPSX_TEST_NOW="2026-11-10 09:08"; H="$(opsx new --repo "$A" -- 來源要帶全文)"
printf -- '---\ntype: bug\nsource: me\nkind_of_work: planned\n---\n\n## 一句話\n\nX 壞了\n\n## 證據\n\n- foo.py:3\n- id: 假 id\n' > "$CH/$H/inbox.md"
assert_rc 0 opsx merge-card "$H" --into "$G" --repo "$A"
assert_grep '^## 併入：[^ ]* me$' "$CH/$G/inbox.md"
assert_grep '^- id: ' "$CH/$G/inbox.md"
assert_grep '^- kind_of_work: planned$' "$CH/$G/inbox.md"
assert_grep '^- type: bug$' "$CH/$G/inbox.md"
assert_grep 'X 壞了' "$CH/$G/inbox.md"
assert_grep 'foo.py:3' "$CH/$G/inbox.md"
assert_eq "$(grep -c '^- id: ' "$CH/$G/inbox.md")" 1 "來源證據裡長得像 id 的行不能多出一個假 id"
assert_grep "^- 併進：a/$H · source: me" "$CH/$G/inbox.md"
# 併入段沒有 task 時 opsx check 點名（propose 的檢查認得它）
printf '## 1. x\n\n- [ ] 1.1 a\n  - 驗收：R\n  - 測試：無 · x\n' > "$CH/$G/tasks.md"
out="$(cd "$A" && opsx check "$G" 2>&1)"; case "$out" in *"沒有去處"*) ;; *) fail "opsx check 要點名沒有去處的併入：$out" ;; esac
rm -rf "$CH/$G"

# --- 目標已有 tasks.md 或已拆：捨棄來源之前就拒絕，兩張卡都不動 ---
export OPSX_TEST_NOW="2026-11-10 09:09"; T="$(opsx new --repo "$A" -- 已開工的目標)"; export OPSX_TEST_NOW="2026-11-10 09:10"; U="$(opsx new --repo "$A" -- 要併的來源)"
printf '## 1. x\n' > "$CH/$T/tasks.md"
before="$(snap)"
err="$(opsx merge-card "$U" --into "$T" --repo "$A" 2>&1)" && fail "目標已有 tasks.md 要退出非零"
case "$err" in *tasks.md*) ;; *) fail "訊息要含 tasks.md：$err" ;; esac
assert_eq "$(snap)" "$before" "目標已有 tasks.md：兩張卡都不動"
rm -rf "$CH/$T"
export OPSX_TEST_NOW="2026-11-10 09:11"; T="$(opsx new --repo "$A" -- 已拆的目標)"
printf -- '---\nsource: me\nsplit_into: p1, p2\n---\n\n## 一句話\n\nx\n\n## 證據\n\n' > "$CH/$T/inbox.md"
before="$(snap)"
err="$(opsx merge-card "$U" --into "$T" --repo "$A" 2>&1)" && fail "目標已拆要退出非零"
case "$err" in *split_into*) ;; *) fail "訊息要含 split_into：$err" ;; esac
assert_eq "$(snap)" "$before" "目標已拆：兩張卡都不動"
rm -rf "$CH/$T" "$CH/$U"

# --- 用法說明有 merge-card ---
opsx --help | grep -q '^  merge-card ' || fail "opsx --help 要列 merge-card"

# ========== 1.2 失敗路徑：退出非零，兩張卡都不改 ==========
export OPSX_TEST_NOW="2026-11-10 09:03"; S="$(opsx new --repo "$A" -- 來源)"
before="$(snap)"
err="$(opsx merge-card "$S" --into nope --repo "$A" 2>&1)" && fail "目標不存在要退出非零"
case "$err" in *nope*) ;; *) fail "stderr 要含目標名：$err" ;; esac
err="$(opsx merge-card "$S" --into "$S" --repo "$A" 2>&1)" && fail "目標等於來源要退出非零"
case "$err" in *"$S"*) ;; *) fail "stderr 要含目標名：$err" ;; esac
assert_rc 2 opsx merge-card "$S" --repo "$A"
assert_rc 2 opsx merge-card "$S" --into "$Y"
assert_rc 2 opsx merge-card "$S" --into 'Bad/slug' --repo "$A"
assert_rc 2 opsx merge-card nope --into "$Y" --repo "$A"
assert_eq "$(snap)" "$before"

# --- 目標沒有證據段 ---
export OPSX_TEST_NOW="2026-11-10 09:04"; N="$(opsx new --repo "$A" -- 手寫的卡)"
printf -- '---\ntype: 功能\nsource: me\n---\n\n## 一句話\n\n手寫的卡\n' > "$CH/$N/inbox.md"
before="$(snap)"
err="$(opsx merge-card "$S" --into "$N" --repo "$A" 2>&1)" && fail "目標沒有證據段要退出非零"
case "$err" in *證據*) ;; *) fail "stderr 要含證據：$err" ;; esac
assert_dir "$CH/$S"; assert_eq "$(snap)" "$before"

# --- 來源 frontmatter 沒有 source:（內文有 source: 也不算）---
printf -- '---\ntype: 功能\n---\n\n## 一句話\n\nsource: 寫在內文\n\n## 證據\n\n' > "$CH/$N/inbox.md"
before="$(snap)"
err="$(opsx merge-card "$N" --into "$Y" --repo "$A" 2>&1)" && fail "來源沒有 source 要退出非零"
case "$err" in *source*) ;; *) fail "stderr 要含 source：$err" ;; esac
assert_eq "$(snap)" "$before"

# --- 來源還派著 ---
printf '{"a/%s":{"mode":"autopilot","pane":"p4"}}' "$S" > "$OPSX_STATE_DIR/dispatch.json"
before="$(snap)"
err="$(opsx merge-card "$S" --into "$Y" --repo "$A" 2>&1)" && fail "還派著要退出非零"
case "$err" in *停止*) ;; *) fail "stderr 要提示先停止：$err" ;; esac
assert_dir "$CH/$S"; assert_eq "$(snap)" "$before"
rm "$OPSX_STATE_DIR/dispatch.json"

# ========== 1.3 被併的卡不會被同步重建 ==========
rm -rf "$CH/$S" "$CH/$N"
COMMENT='單 worker, 跑第二個 instance 時改 redis'
H="$(printf '%s' "$COMMENT" | shasum -a 1 | cut -c1-8)"
echo "# shortcut: $COMMENT" > "$A/x.py"
# 之前 sync 開出來的 debt 卡（現在 sync 不再開，這裡手寫一張同樣形狀的）
mkdir -p "$CH/debt-$H"; printf 'schema: opsx\ncreated: 2026-11-10\nkind: dev\n' > "$CH/debt-$H/.openspec.yaml"
printf -- '---\ntype: 技術債\nsource: shortcut:a:x.py:%s\nline: 1\n---\n\n## 一句話\n\n%s\n\n## 證據\n\n- x.py:1\n' "$H" "$COMMENT" > "$CH/debt-$H/inbox.md"
out="$(opsx sync --root "$ROOT" --source debt 2>&1)"; assert_eq "$?" 0 "sync: $out"
assert_file "$CH/debt-$H/inbox.md"
out="$(opsx merge-card "debt-$H" --into "$Y" --repo "$A" 2>&1)"; assert_eq "$?" 0 "merge-card debt: $out"
assert_eq "$(last_evidence "$CH/$Y/inbox.md")" "- 併進：a/debt-$H · source: shortcut:a:x.py:$H"
out="$(opsx sync --root "$ROOT" --source debt 2>&1)"; assert_eq "$?" 0 "sync again: $out"
assert_eq "$(find "$CH" -mindepth 1 -maxdepth 1 -type d ! -name archive | sort)" "$CH/$Y" "只剩目標卡"

# ========== merge-card-card-lock：證據行在目標卡鎖內插入 ==========
PYBIN="$(cat "$OPSX_STATE_DIR/python")"; LIBDIR="$OPSX_ROOT/bin/lib"
# --- 慢的寫入者：鎖內先讀 inbox.md，等 $FX/go 才寫回（多一段併入）。merge-card 不等鎖就會被它蓋掉 ---
export OPSX_TEST_NOW="2026-11-10 09:10"; P="$(opsx new --repo "$A" -- 並行的來源)"
"$PYBIN" -I -c '
import os, sys, time
sys.path.insert(0, sys.argv[1]); import safefile, inboxmerge
card = sys.argv[2]
with safefile.CardLock(card):
    p = os.path.join(card, "inbox.md")
    with open(p, encoding="utf-8") as f:
        cur = f.read()
    open(sys.argv[3], "w").close()
    while not os.path.exists(sys.argv[4]):
        time.sleep(0.02)
    safefile.write_atomic(p, cur + "\n" + inboxmerge.section("late-1", "2026-11-11T10:00:00+08:00", "agent:t", "planned", "", "hooks", "晚到的併入"))
' "$LIBDIR" "$CH/$Y" "$FX/held" "$FX/go" &
HOLDER=$!
for _ in $(seq 100); do [ -e "$FX/held" ] && break; sleep 0.05; done
[ -e "$FX/held" ] || fail "持鎖的 process 沒有拿到鎖"
opsx merge-card "$P" --into "$Y" --repo "$A" > "$FX/mc.out" 2>&1 &
MC=$!
sleep 1; : > "$FX/go"
wait "$HOLDER"; wait "$MC"; assert_eq "$?" 0 "merge-card: $(cat "$FX/mc.out")"
assert_eq "$(last_evidence "$CH/$Y/inbox.md")" "- 併進：a/$P · source: me" "證據行要在"
assert_grep '^- id: late-1$' "$CH/$Y/inbox.md"

# --- helper 在鎖內讀到沒有證據段：非 0 退出、指出檔案路徑、inbox.md 不變 ---
printf -- '---\ntype: 功能\nsource: me\n---\n\n## 一句話\n\n沒有證據段\n' > "$CH/$Y/inbox.md"
before="$(shasum "$CH/$Y/inbox.md")"
err="$("$PYBIN" -I "$LIBDIR/inboxmerge.py" evidence "$CH/$Y" '- 併進：x' 2>&1)" && fail "沒有證據段要退出非零"
case "$err" in *"$CH/$Y/inbox.md"*) ;; *) fail "stderr 要含檔案路徑：$err" ;; esac
assert_eq "$(shasum "$CH/$Y/inbox.md")" "$before"

# ========== 併卡帶事實欄位（merge-card-priority-carry）==========
# mk_card <slug> <kind_of_work> <impact（空字串 = 不寫）> <evidence（空字串 = 不寫）>
mk_card() {
  local d="$CH/$1"; mkdir -p "$d"; printf 'schema: opsx\n' > "$d/.openspec.yaml"
  { printf -- '---\ntype: bug\nsource: agent:t\nfound: 2026-11-10\nrelated:\n'
    [ -z "$2" ] || printf 'kind_of_work: %s\n' "$2"
    [ -z "$3" ] || printf 'impact: %s\n' "$3"
    [ -z "$4" ] || printf 'evidence: %s\n' "$4"
    printf -- '---\n\n## 一句話\n\n%s\n\n## 證據\n\n- 原有\n' "$1"; } > "$d/inbox.md"
}
level_of() { opsx priority "$1" --repo "$A" | cut -f1; }
fm_value() { awk -v k="$2" 'NR>1 && /^---/{exit} index($0,k":")==1{sub(/^[^:]*: */,"");print;exit}' "$CH/$1/inbox.md"; }

# --- P0 incident 併進 P2 planned 卡：目標變 P0 ---
mk_card carry-src incident data "資料遺失的 log"; mk_card carry-dst planned "" ""
assert_eq "$(level_of carry-dst)" P2 "fixture 目標要是 P2"
assert_rc 0 opsx merge-card carry-src --into carry-dst --repo "$A"
assert_eq "$(fm_value carry-dst kind_of_work)" incident
assert_eq "$(fm_value carry-dst impact)" data
assert_eq "$(fm_value carry-dst evidence)" "資料遺失的 log"
assert_eq "$(level_of carry-dst)" P0 "併卡後等級掉了"

# --- planned 來源併進 incident 目標：不降級 ---
mk_card carry-src2 planned "" ""; mk_card carry-dst2 incident security "洩漏的 log"
assert_rc 0 opsx merge-card carry-src2 --into carry-dst2 --repo "$A"
assert_eq "$(fm_value carry-dst2 kind_of_work)" incident
assert_eq "$(fm_value carry-dst2 impact)" security
assert_eq "$(level_of carry-dst2)" P0

# --- impact 取聯集（四列）---
carry_row() { # <名> <來源 impact> <目標 impact> <結果>
  local ev=""; [ -z "$2" ] || ev="來源證據"
  local tev=""; [ -z "$3" ] || tev="目標證據"
  mk_card "$1-s" incident "$2" "$ev"; mk_card "$1-d" incident "$3" "$tev"
  [ -n "$2$3" ] || return 0
  assert_rc 0 opsx merge-card "$1-s" --into "$1-d" --repo "$A"
  assert_eq "$(fm_value "$1-d" impact)" "$4" "$1 的 impact"
}
carry_row u1 data "" data
carry_row u2 "" security security
carry_row u3 data security "security, data"
carry_row u4 data data data

# --- 來源沒有事實欄位：目標 frontmatter 位元組不變 ---
mk_card carry-src5 "" "" ""; mk_card carry-dst5 planned "" ""
fm_before="$(awk 'NR>1 && /^---/{exit} {print}' "$CH/carry-dst5/inbox.md" | shasum)"
assert_rc 0 opsx merge-card carry-src5 --into carry-dst5 --repo "$A"
assert_eq "$(awk 'NR>1 && /^---/{exit} {print}' "$CH/carry-dst5/inbox.md" | shasum)" "$fm_before" "frontmatter 不變"

# --- 捨棄被拒絕（來源還派著）：目標位元組不變，來源還在；停掉後重試成功，證據只一份 ---
mk_card carry-src7 incident data "log7"; mk_card carry-dst7 planned "" ""
printf '{"a/carry-src7":{"mode":"autopilot","pane":"p4"}}' > "$OPSX_STATE_DIR/dispatch.json"
before="$(snap)"
assert_rc 2 opsx merge-card carry-src7 --into carry-dst7 --repo "$A"
assert_eq "$(snap)" "$before" "drop 拒絕時兩張卡都不能動"
rm -f "$OPSX_STATE_DIR/dispatch.json"
assert_rc 0 opsx merge-card carry-src7 --into carry-dst7 --repo "$A"
assert_eq "$(fm_value carry-dst7 evidence)" "log7" "重試後證據只一份"

# --- 來源有 priority 覆寫：目標不能比它低 ---
mk_card carry-src8 planned "" ""; mk_card carry-dst8 planned "" ""
printf -- '---\ntype: bug\nsource: agent:t\nfound: 2026-11-10\nrelated:\nkind_of_work: planned\npriority: P0\npriority_reason: 人判定\n---\n\n## 一句話\n\ncarry-src8\n\n## 證據\n\n- 原有\n' > "$CH/carry-src8/inbox.md"
assert_eq "$(level_of carry-dst8)" P2
assert_rc 0 opsx merge-card carry-src8 --into carry-dst8 --repo "$A"
assert_eq "$(level_of carry-dst8)" P0 "來源的 priority 覆寫要帶過去"

# --- 兩張卡有同一條證據併進同一個目標：證據不重複 ---
mk_card carry-s9a incident data "same"; mk_card carry-s9b incident data "same"; mk_card carry-dst9 planned "" ""
assert_rc 0 opsx merge-card carry-s9a --into carry-dst9 --repo "$A"
assert_rc 0 opsx merge-card carry-s9b --into carry-dst9 --repo "$A"
assert_eq "$(fm_value carry-dst9 evidence)" "same"

# --- 目標用巢狀的 impact 寫法：併完是同一行的寫法、證據保留 ---
mk_card carry-s10 incident security "洩漏"
mkdir -p "$CH/carry-d10"; printf 'schema: opsx\n' > "$CH/carry-d10/.openspec.yaml"
printf -- '---\ntype: bug\nsource: agent:t\nfound: 2026-11-10\nrelated:\nkind_of_work: incident\nimpact:\n  data: true\n  evidence: 原證據\n---\n\n## 一句話\n\nd10\n\n## 證據\n\n- 原有\n' > "$CH/carry-d10/inbox.md"
assert_rc 0 opsx merge-card carry-s10 --into carry-d10 --repo "$A"
assert_eq "$(fm_value carry-d10 impact)" "data, security"
assert_eq "$(fm_value carry-d10 evidence)" "原證據 ; 洩漏"
assert_eq "$(level_of carry-d10)" P0

# --- 目標沒有 frontmatter：退出非零，兩張卡都不動 ---
mk_card carry-s11 incident data "x11"
mkdir -p "$CH/carry-d11"; printf 'schema: opsx\n' > "$CH/carry-d11/.openspec.yaml"
printf '# 沒有 frontmatter\n\n## 證據\n\n- 原有\n' > "$CH/carry-d11/inbox.md"
before="$(snap)"
err="$(opsx merge-card carry-s11 --into carry-d11 --repo "$A" 2>&1)" && fail "目標沒有 frontmatter 要退出非零"
case "$err" in *carry-d11*) ;; *) fail "stderr 要指名目標卡：$err" ;; esac
assert_eq "$(snap)" "$before"

# --- 低的 priority 覆寫不降低算出 P0 的目標 ---
mk_card carry-s12 planned "" ""; mk_card carry-d12 incident data "資料遺失"
printf -- '---\ntype: bug\nsource: agent:t\nfound: 2026-11-10\nrelated:\nkind_of_work: planned\npriority: P2\npriority_reason: 人判定不急\n---\n\n## 一句話\n\ncarry-s12\n\n## 證據\n\n- 原有\n' > "$CH/carry-s12/inbox.md"
assert_eq "$(level_of carry-d12)" P0
assert_rc 0 opsx merge-card carry-s12 --into carry-d12 --repo "$A"
assert_eq "$(level_of carry-d12)" P0 "P2 覆寫不能把 P0 目標降下來"
assert_eq "$(fm_value carry-d12 priority)" "" "目標不該多出比算出來還低的 priority"

# --- 來源沒有任何事實：不解析目標（目標有舊的不合格欄位也併得進去），目標 frontmatter 位元組不變 ---
mk_card carry-s13 "" "" ""; mk_card carry-d13 incident data ""
mk_card carry-s14 "" "" ""; mk_card carry-d14 planned "" "a ; a"
fm_of() { awk 'NR>1 && /^---/{exit} {print}' "$CH/$1/inbox.md" | shasum; }
f13="$(fm_of carry-d13)"; f14="$(fm_of carry-d14)"
assert_rc 0 opsx merge-card carry-s13 --into carry-d13 --repo "$A"
assert_rc 0 opsx merge-card carry-s14 --into carry-d14 --repo "$A"
assert_eq "$(fm_of carry-d13)" "$f13" "來源沒事實時目標不解析、不改"
assert_eq "$(fm_of carry-d14)" "$f14" "evidence a ; a 不能被重新去重"

# --- 目標內文有 --- 水平線但沒有 frontmatter：退出非零，不把欄位寫進內文 ---
mk_card carry-s15 incident data "x15"
mkdir -p "$CH/carry-d15"; printf 'schema: opsx\n' > "$CH/carry-d15/.openspec.yaml"
printf '# 標題\n\n---\n\n## 證據\n\n- 原有\n' > "$CH/carry-d15/inbox.md"
before="$(snap)"
assert_rc 1 opsx merge-card carry-s15 --into carry-d15 --repo "$A"
assert_eq "$(snap)" "$before" "沒有 frontmatter 的目標不能被寫進內文"

# --- 巢狀目標只有 impact 變、evidence 相同：改成同一行後 evidence 還在 ---
mk_card carry-s16 incident security "同一條"
mkdir -p "$CH/carry-d16"; printf 'schema: opsx\n' > "$CH/carry-d16/.openspec.yaml"
printf -- '---\ntype: bug\nsource: agent:t\nfound: 2026-11-10\nrelated:\nkind_of_work: incident\nimpact:\n  data: true\n  evidence: 同一條\n---\n\n## 一句話\n\nd16\n\n## 證據\n\n- 原有\n' > "$CH/carry-d16/inbox.md"
assert_rc 0 opsx merge-card carry-s16 --into carry-d16 --repo "$A"
assert_eq "$(fm_value carry-d16 impact)" "data, security"
assert_eq "$(fm_value carry-d16 evidence)" "同一條" "巢狀的 evidence 不能因為只有 impact 變就掉了"

# --- evidence 依 ' ; ' 分段去重：a ; b 加 b 還是 a ; b ---
mk_card carry-s17 incident data "b"; mk_card carry-d17 incident data "a ; b"
assert_rc 0 opsx merge-card carry-s17 --into carry-d17 --repo "$A"
assert_eq "$(fm_value carry-d17 evidence)" "a ; b"

# --- 來源的事實欄位不合格：退出非零，兩張卡都不動 ---
mk_card carry-src6 incident data ""; mk_card carry-dst6 planned "" ""
before="$(snap)"
err="$(opsx merge-card carry-src6 --into carry-dst6 --repo "$A" 2>&1)" && fail "impact 沒有 evidence 要退出非零"
case "$err" in *evidence*) ;; *) fail "stderr 要指名 evidence：$err" ;; esac
assert_eq "$(snap)" "$before"
echo ok
