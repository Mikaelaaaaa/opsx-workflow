#!/usr/bin/env bash
# opsx sync：來源撈進收件匣。驗收：specs/board-sync（board-inbox 7.1 debt、8.1 gitlab、9.1 github）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes glab gh
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
mkdir -p "$OPSX_STATE_DIR"
ROOT="$FX/code"; mkdir -p "$ROOT"
A="$(mk_opsx_repo a)"; mv "$A" "$ROOT/a"; A="$(cd "$ROOT/a" && pwd -P)"
CH="$A/openspec/changes"
LOG="$OPSX_STATE_DIR/sync.log"
sync_debt() { opsx sync --root "$ROOT" --source debt; }
cards() { find "$CH" -mindepth 1 -maxdepth 1 -type d ! -name archive | sort; }
# sync.log 是 opsx log --sync 的格式（ts · source · 新卡數 · 文字）；opsx sync 每次跑完寫一列 source = sync，
# debt.sh 自己也會寫 source = debt 的掃描列。logcols 取最後一列 sync，拆成 新建 · 更新 · 沒變 · 錯誤 · 第一個錯誤
lastsync() { awk -F'\t' '$2=="sync"' "$LOG" | tail -1; }
logcols() { lastsync | python3 -I -c 'import re,sys
ts,src,new,text=sys.stdin.read().rstrip("\n").split("\t")
m=re.fullmatch(r"新建 (\d+) · 更新 (\d+) · 沒變 (\d+) · 錯誤 (\d+)(?:：(.*))?",text)
assert m and m[1]==new, (new,text)
print("\t".join([m[1],m[2],m[3],m[4],m[5] or ""]))'; }

# ========== debt ==========
COMMENT='單 worker, 跑第二個 instance 時改 redis'
H="$(printf '%s' "$COMMENT" | shasum -a 1 | cut -c1-8)"
{ for i in 1 2 3 4 5 6 7 8 9; do echo "x = $i"; done; echo "# shortcut: $COMMENT"; } > "$A/x.py"

# --- 新的 shortcut 註解 · 只跑一個來源 ---
out="$(sync_debt 2>&1)"; assert_eq "$?" 0 "sync: $out"
D="$CH/debt-$H"; I="$D/inbox.md"
assert_file "$I"; assert_grep '^schema: opsx$' "$D/.openspec.yaml"
assert_grep "^source: shortcut:a:x.py:$H\$" "$I"; assert_grep '^type: 技術債$' "$I"; assert_grep '^line: 10$' "$I"
assert_grep '^limit: 單 worker$' "$I"; assert_grep '^trigger: 跑第二個 instance 時改 redis$' "$I"
assert_grep "^$COMMENT\$" "$I"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "--source debt 不呼叫 glab、gh"

# --- 一次同步一行：at、created、updated、unchanged、errors、first_error ---
assert_eq "$(awk -F'\t' '$2=="sync"' "$LOG" | wc -l | tr -d ' ')" 1 "一次同步一列 sync"
assert_eq "$(awk -F'\t' '$2=="debt"' "$LOG" | wc -l | tr -d ' ')" 1 "debt.sh 自己的掃描列照舊"
assert_eq "$(logcols)" "$(printf '1\t0\t0\t0\t')"
lastsync | cut -f1 | grep -qE '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9]{2}:[0-9]{2}$' || fail "ts 要 ISO 8601 含時區：$(lastsync)"

# --- 重跑不長新卡 ---
before="$(cards)"; sync_debt >/dev/null 2>&1
assert_eq "$(cards)" "$before"; assert_eq "$(logcols)" "$(printf '0\t0\t1\t0\t')"

# --- 行號漂移：同一張卡，line 改了 ---
{ printf 'a\nb\nc\nd\n'; cat "$A/x.py"; } > "$FX/x.py"; mv "$FX/x.py" "$A/x.py"
sync_debt >/dev/null 2>&1
assert_eq "$(cards)" "$before"; assert_grep '^line: 14$' "$I"; assert_not_grep '^line: 10$' "$I"
assert_eq "$(logcols)" "$(printf '0\t1\t0\t0\t')"

# --- 註解被刪：stale: true，卡還在；再出現就拿掉 ---
grep -v shortcut "$A/x.py" > "$FX/x.py"; mv "$FX/x.py" "$A/x.py"
sync_debt >/dev/null 2>&1
assert_dir "$D"; assert_grep '^stale: true$' "$I"; assert_eq "$(logcols)" "$(printf '0\t1\t0\t0\t')"
sync_debt >/dev/null 2>&1; assert_eq "$(logcols)" "$(printf '0\t0\t0\t0\t')" "已標 stale 的不重複算更新"
echo "# shortcut: $COMMENT" >> "$A/x.py"
sync_debt >/dev/null 2>&1
assert_not_grep '^stale:' "$I"; assert_grep '^line: 14$' "$I"

# --- 已歸檔的卡也算：不新建，也不改歸檔的卡 ---
mkdir -p "$CH/archive"; mv "$D" "$CH/archive/2026-11-01-debt-$H"
cp "$CH/archive/2026-11-01-debt-$H/inbox.md" "$FX/archived.md"
grep -v shortcut "$A/x.py" > "$FX/x.py"; { cat "$FX/x.py"; echo "# shortcut: $COMMENT"; } > "$A/x.py"
sync_debt >/dev/null 2>&1
assert_eq "$(cards)" "" "已歸檔的 source 不能再建殼"
assert_eq "$(cat "$CH/archive/2026-11-01-debt-$H/inbox.md")" "$(cat "$FX/archived.md")" "歸檔的卡不動"

# --- 不合格的來源 ---
assert_rc 2 opsx sync --root "$ROOT" --source customer

# --- launchd 與按鈕同時觸發：拿不到鎖就退出 3，sync.log 不多行 ---
n="$(wc -l < "$LOG" | tr -d ' ')"
python3 -I -c 'import fcntl,sys,time
f=open(sys.argv[1],"w"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(5)' "$OPSX_STATE_DIR/sync.lock" "$FX/locked" &
holder=$!
for _ in $(seq 50); do [ -f "$FX/locked" ] && break; sleep 0.1; done
err="$(sync_debt 2>&1)"; rc=$?
wait "$holder"
assert_eq "$rc" 3 "拿不到鎖要退出 3：$err"
case "$err" in *同步進行中*) ;; *) fail "要印同步進行中：$err" ;; esac
assert_eq "$(wc -l < "$LOG" | tr -d ' ')" "$n"

# --- sync.lock 是 symlink（symlink-safe-writes）：拒絕、不是 0 也不是 3、目標不變 ---
printf 'keep me\n' > "$FX/victim"; rm -f "$OPSX_STATE_DIR/sync.lock"; ln -s "$FX/victim" "$OPSX_STATE_DIR/sync.lock"
err="$(sync_debt 2>&1)"; rc=$?
{ [ $rc -ne 0 ] && [ $rc -ne 3 ]; } || fail "sync.lock 是 symlink 要拒絕（rc ${rc}）：$err"
case "$err" in *sync.lock*) ;; *) fail "訊息要含 sync.lock：$err" ;; esac
assert_eq "$(cat "$FX/victim")" "keep me" "sync.lock 不能被改"
rm -f "$OPSX_STATE_DIR/sync.lock"

# --- inbox.md 改寫（update_debt、mark_stale）：inbox.md 是 symlink → 換成一般檔，目標不變 ---
printf -- '---\nsource: shortcut:x:1\nline: 1\n---\n\n## 一句話\n\nx\n' > "$FX/victim-inbox.md"
cp "$FX/victim-inbox.md" "$FX/victim-inbox.before"
ln -s "$FX/victim-inbox.md" "$FX/inbox-link.md"
python3 -I -c '
import pathlib, sys
sys.path.insert(0, sys.argv[1]); import sync
p = pathlib.Path(sys.argv[2])
assert sync.update_debt({"path": p}, {"extra": {"line": "9"}})
' "$OPSX_ROOT/bin/lib" "$FX/inbox-link.md" || fail "update_debt rc"
cmp -s "$FX/victim-inbox.md" "$FX/victim-inbox.before" || fail "update_debt 不能寫到 symlink 的目標：$(cat "$FX/victim-inbox.md")"
[ ! -L "$FX/inbox-link.md" ] || fail "update_debt 要把 symlink 換成一般檔"
assert_grep '^line: 9$' "$FX/inbox-link.md"
rm -f "$FX/inbox-link.md"; ln -s "$FX/victim-inbox.md" "$FX/inbox-link.md"
python3 -I -c '
import pathlib, sys
sys.path.insert(0, sys.argv[1]); import sync
p = pathlib.Path(sys.argv[2])
sync.mark_stale({"shortcut:x:1": {"frozen": False, "path": p}}, set(), {"x"}, sync.Tally())
' "$OPSX_ROOT/bin/lib" "$FX/inbox-link.md" || fail "mark_stale rc"
cmp -s "$FX/victim-inbox.md" "$FX/victim-inbox.before" || fail "mark_stale 不能寫到 symlink 的目標"
assert_grep '^stale: true$' "$FX/inbox-link.md"
rm -f "$FX/inbox-link.md"
# ========== gitlab / github ==========
CS="$(mk_opsx_repo Acmecorp-CS)"; mv "$CS" "$ROOT/Acmecorp-CS"; CS="$(cd "$ROOT/Acmecorp-CS" && pwd -P)"
B="$(mk_opsx_repo b)"; mv "$B" "$ROOT/b"; B="$(cd "$ROOT/b" && pwd -P)"
mkdir -p "$FX/elsewhere"; Z="$(mk_opsx_repo z)"; mv "$Z" "$FX/elsewhere/z"; Z="$(cd "$FX/elsewhere/z" && pwd -P)"
cat > "$OPSX_STATE_DIR/sources.toml" <<EOF
[[source]]
kind = "gitlab"
repo = "a"
project = "g/a"
path = "$A"

[[source]]
kind = "gitlab"
repo = "Acmecorp-CS"
project = "acmecorp/acmecorp-cs"
path = "$CS"

[[source]]
kind = "github"
repo = "z"
project = "me/z"
path = "$Z"
EOF
export OPSX_TEST_ISSUES="$FX/issues"; mkdir -p "$OPSX_TEST_ISSUES"
gl() { # <iid> <title> <updated_at> [labels json]
  printf '{"iid":%s,"title":"%s","description":"%s 的內文","state":"opened","updated_at":"%s","web_url":"https://gitlab.example/g/x/-/issues/%s","labels":%s}' "$1" "$2" "$2" "$3" "$1" "${4:-[]}"; }
printf '[%s,%s]' "$(gl 412 聊天視窗被鍵盤蓋住 2026-11-05T10:00:00Z '["bug"]')" "$(gl 500 撞名的 2026-11-05T10:00:00Z)" > "$OPSX_TEST_ISSUES/a.json"
printf '[%s]' "$(gl 9 大寫的 2026-11-05T10:00:00Z)" > "$OPSX_TEST_ISSUES/Acmecorp-CS.json"
printf '[%s]' "$(gl 1 不該撈 2026-11-05T10:00:00Z)" > "$OPSX_TEST_ISSUES/b.json"
printf '[{"number":3,"title":"README 錯字","body":"第三行","state":"OPEN","updatedAt":"2026-11-05T10:00:00Z","url":"https://github.com/me/z/issues/3","labels":[{"name":"docs"}]}]' > "$OPSX_TEST_ISSUES/gh-z.json"
# slug 撞名但來源不同：先有一張 source: me 的 gl-a-500
printf -- '---\ntype: 功能\nsource: me\n---\n\n## 一句話\n\n手動建的\n' > "$FX/me.md"
( source "$OPSX_ROOT/bin/lib/common.sh"; new_shell "$A" gl-a-500 "$FX/me.md" >/dev/null )
: > "$OPSX_FAKE_LOG"

# --- 新的 GitLab issue · repo 名有大寫 · github · 沒登記的 repo 不撈 ---
out="$(opsx sync --root "$ROOT" 2>&1)"; assert_eq "$?" 0 "sync all: $out"
I="$CH/gl-a-412/inbox.md"
assert_grep '^source: gitlab:a#412$' "$I"; assert_grep '^type: 錯誤修正$' "$I"
assert_grep '^upstream_url: https://gitlab.example/g/x/-/issues/412$' "$I"; assert_grep '^upstream_updated: 2026-11-05T10:00:00Z$' "$I"
assert_eq "$(awk '/^## 一句話/{f=1;next} f&&NF{print;exit}' "$I")" 聊天視窗被鍵盤蓋住
assert_grep '^聊天視窗被鍵盤蓋住 的內文$' "$I"
assert_grep '^source: gitlab:a#500$' "$CH/gl-a-500-2/inbox.md"; assert_grep '^手動建的$' "$CH/gl-a-500/inbox.md"
assert_grep '^source: gitlab:Acmecorp-CS#9$' "$CS/openspec/changes/gl-acmecorp-cs-9/inbox.md"
GI="$Z/openspec/changes/gh-z-3/inbox.md"
assert_grep '^source: github:z#3$' "$GI"; assert_grep '^type: 功能$' "$GI"; assert_grep '^upstream_url: https://github.com/me/z/issues/3$' "$GI"
assert_eq "$(find "$B/openspec/changes" -mindepth 1 -maxdepth 1 ! -name archive | wc -l | tr -d ' ')" 0 "沒登記在 sources.toml 的 repo 不撈"
assert_eq "$(grep -c '^issue list' "$OPSX_FAKE_LOG")" 3 "兩個 gitlab、一個 github 各 list 一次：$(cat "$OPSX_FAKE_LOG")"

# --- 重跑不長新卡 ---
snap_all() { find "$A/openspec/changes" "$CS/openspec/changes" "$Z/openspec/changes" -mindepth 1 -maxdepth 1 | sort; }
before="$(snap_all)"; opsx sync --root "$ROOT" >/dev/null 2>&1
assert_eq "$(snap_all)" "$before"; assert_eq "$(logcols | cut -f1)" 0

# --- 還沒 explore 的卡內容更新：一句話換新、upstream_updated 換新 ---
printf '[%s,%s]' "$(gl 412 鍵盤蓋住輸入框 2026-11-06T08:00:00Z '["bug"]')" "$(gl 500 撞名的 2026-11-05T10:00:00Z)" > "$OPSX_TEST_ISSUES/a.json"
# --- explore 過的卡內容更新：一句話不變，證據多一行 ---
printf '## 已知\n' > "$CS/openspec/changes/gl-acmecorp-cs-9/explore.md"
printf '[%s]' "$(gl 9 改過的標題 2026-11-06T08:00:00Z)" > "$OPSX_TEST_ISSUES/Acmecorp-CS.json"
opsx sync --root "$ROOT" >/dev/null 2>&1
assert_eq "$(awk '/^## 一句話/{f=1;next} f&&NF{print;exit}' "$I")" 鍵盤蓋住輸入框
assert_grep '^鍵盤蓋住輸入框 的內文$' "$I"; assert_not_grep '^聊天視窗被鍵盤蓋住 的內文$' "$I"
assert_grep '^upstream_updated: 2026-11-06T08:00:00Z$' "$I"
CI="$CS/openspec/changes/gl-acmecorp-cs-9/inbox.md"
assert_eq "$(awk '/^## 一句話/{f=1;next} f&&NF{print;exit}' "$CI")" 大寫的
awk '/^## 證據/{f=1;next} /^## /{f=0} f' "$CI" | grep -q 'gitlab:Acmecorp-CS#9.*2026-11-06' || fail "證據要多一行更新：$(cat "$CI")"
assert_eq "$(logcols | cut -f2)" 2
opsx sync --root "$ROOT" >/dev/null 2>&1
assert_eq "$(grep -c 'gitlab:Acmecorp-CS#9' "$CI")" 2 "同一次更新不重複追加（source 那行加一行證據）"

# --- issue 關閉 · 改指派給別人 · github 關閉 ---
printf '[]' > "$OPSX_TEST_ISSUES/a.json"; printf '[]' > "$OPSX_TEST_ISSUES/gh-z.json"
printf '{"iid":412,"state":"closed"}' > "$OPSX_TEST_ISSUES/view-412.json"
printf '{"iid":500,"state":"opened"}' > "$OPSX_TEST_ISSUES/view-500.json"
printf '{"state":"CLOSED"}' > "$OPSX_TEST_ISSUES/gh-view-3.json"
cp "$CH/gl-a-500-2/inbox.md" "$FX/500.md"
opsx sync --root "$ROOT" >/dev/null 2>&1
assert_grep '^upstream: closed$' "$I"; assert_dir "$CH/gl-a-412"
assert_eq "$(cat "$CH/gl-a-500-2/inbox.md")" "$(cat "$FX/500.md")" "改指派不動卡"
assert_grep '^upstream: closed$' "$GI"
grep -q '^issue view 412 -R g/a' "$OPSX_FAKE_LOG" || fail "關閉要用 issue view -R 查：$(cat "$OPSX_FAKE_LOG")"

# --- 重開的 issue 又出現在 list：拿掉 upstream: closed ---
printf '[%s]' "$(gl 412 鍵盤蓋住輸入框 2026-11-06T08:00:00Z '["bug"]')" > "$OPSX_TEST_ISSUES/a.json"
opsx sync --root "$ROOT" >/dev/null 2>&1
assert_not_grep '^upstream:' "$I"

# --- 一個來源失敗：其他照建，sync.log 記錯，退出 0 ---
touch "$OPSX_TEST_ISSUES/a.fail"
NEW_DEBT='第二個 worker, 量大再拆'; echo "# shortcut: $NEW_DEBT" > "$A/y.py"
ND="$CH/debt-$(printf '%s' "$NEW_DEBT" | shasum -a 1 | cut -c1-8)"
printf '[{"number":4,"title":"新的","body":"","state":"OPEN","updatedAt":"2026-11-06T08:00:00Z","url":"https://github.com/me/z/issues/4","labels":[]}]' > "$OPSX_TEST_ISSUES/gh-z.json"
out="$(opsx sync --root "$ROOT" 2>&1)"; assert_eq "$?" 0 "一個來源失敗仍退出 0：$out"
assert_file "$Z/openspec/changes/gh-z-4/inbox.md"
assert_file "$ND/inbox.md"
rm "$OPSX_TEST_ISSUES/a.fail"
[ "$(logcols | cut -f4)" -ge 1 ] || fail "errors 要 >= 1：$(lastsync)"
logcols | cut -f5 | grep -q '401' || fail "first_error 要含 glab 的 stderr：$(lastsync)"

# ========== review 修正 ==========
# --- slug：repo 名的底線、連續符號換成單一 -，截斷不留 --；openspec 收得下 ---
python3 -I -c 'import re,sys;sys.path.insert(0,sys.argv[1]);import sources as s
ok=re.compile(r"^[a-z][a-z0-9-]{0,31}$")
for got in (s.slug_for("gl","tg_spam",3), s.slug_for("gh","my.-repo",1), s.slug_for("gl","a"*20+"-"+"b"*20,12345)):
    assert ok.match(got) and "--" not in got and "_" not in got, got
assert s.slug_for("gl","tg_spam",3)=="gl-tg-spam-3"' "$OPSX_ROOT/herdr-board/sync" || fail "slug_for 產出 openspec 不收的 slug"

# --- 撞名加 -N 不能超過 32 字 ---
LONG="gl-$(printf 'x%.0s' $(seq 26))-9"   # 32 字
printf -- '---\nsource: me\n---\n\n## 一句話\n\nx\n' > "$FX/long.md"
s1="$( source "$OPSX_ROOT/bin/lib/common.sh"; new_shell "$A" "$LONG" "$FX/long.md" )"
s2="$( source "$OPSX_ROOT/bin/lib/common.sh"; new_shell "$A" "$LONG" "$FX/long.md" )"
assert_eq "$s1" "$LONG"
[[ "$s2" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] && [ "$s2" != "$s1" ] || fail "撞名後的 slug 超過 32 字或沒換：$s2"
assert_dir "$CH/$s2"
case "$s2" in *-9-2) ;; *) fail "截斷要保留原 slug 的結尾（issue 編號）：$s2" ;; esac
# 31 字的 …-1 撞名：不能變成 …-2（那是 issue #2 原本的 slug）
MID="gh-abcdefghijklmnopqrstuvwxyz-1"
m1="$( source "$OPSX_ROOT/bin/lib/common.sh"; new_shell "$A" "$MID" "$FX/long.md" )"
m2="$( source "$OPSX_ROOT/bin/lib/common.sh"; new_shell "$A" "$MID" "$FX/long.md" )"
assert_eq "$m1" "$MID"; [ "$m2" != "gh-abcdefghijklmnopqrstuvwxyz-2" ] || fail "撞名吃掉了 issue 編號：$m2"
[[ "$m2" =~ ^[a-z][a-z0-9-]{0,31}$ ]] && case "$m2" in *-1-2) true ;; *) false ;; esac || fail "要是 …-1-2 而且不超過 32 字：$m2"

# --- issue 內文有 ## 標題：更新後不殘留舊段，證據段不被擾亂 ---
python3 -I -c 'import json,sys;print(json.dumps([{"iid":600,"title":"有標題的","description":"intro\n\n## Steps\n1. old","state":"opened","updated_at":"2026-11-06T08:00:00Z","web_url":"u600","labels":[]}]))' > "$OPSX_TEST_ISSUES/a.json"
opsx sync --root "$ROOT" --source gitlab >/dev/null 2>&1
H600="$CH/gl-a-600/inbox.md"; assert_file "$H600"
python3 -I -c 'import json,sys;print(json.dumps([{"iid":600,"title":"有標題的","description":"intro2\n\n## Steps\n1. new","state":"opened","updated_at":"2026-11-06T09:00:00Z","web_url":"u600","labels":[]}]))' > "$OPSX_TEST_ISSUES/a.json"
opsx sync --root "$ROOT" --source gitlab >/dev/null 2>&1
assert_grep '^1. new$' "$H600"; assert_not_grep '^1. old$' "$H600"
assert_eq "$(grep -c '^## ' "$H600")" 3 "只有 一句話 / 內文 / 證據 三個二級標題：$(cat "$H600")"
assert_grep '^- u600$' "$H600"

# --- repo 範圍跟 collect 一樣：~/code/* 加上 sources.toml 的 path 本身，不掃 path 的兄弟 ---
SIB="$(mk_opsx_repo sib)"; mv "$SIB" "$FX/elsewhere/sib"; SIB="$(cd "$FX/elsewhere/sib" && pwd -P)"
echo "# shortcut: 兄弟 repo 的, 不該建" > "$SIB/s.py"
echo "# shortcut: z 自己的, 要建" > "$Z/z.py"
opsx sync --root "$ROOT" --source debt >/dev/null 2>&1
assert_eq "$(find "$SIB/openspec/changes" -mindepth 1 -maxdepth 1 ! -name archive | wc -l | tr -d ' ')" 0 "沒登記的兄弟 repo 不建卡"
assert_file "$Z/openspec/changes/debt-$(printf '%s' 'z 自己的, 要建' | shasum -a 1 | cut -c1-8)/inbox.md"

# --- symlink 進 root 的 repo：debt 照樣撈得到，既有的卡不會被標 stale ---
REAL="$(mk_opsx_repo linked-real)"; ln -s "$REAL" "$ROOT/linked"
echo "# shortcut: 連結進來的, 要建" > "$REAL/l.py"
opsx sync --root "$ROOT" --source debt >/dev/null 2>&1
LD="$REAL/openspec/changes/debt-$(printf '%s' '連結進來的, 要建' | shasum -a 1 | cut -c1-8)/inbox.md"
assert_file "$LD"
opsx sync --root "$ROOT" --source debt >/dev/null 2>&1
assert_not_grep '^stale:' "$LD"

# --- 撞名截斷的邊界：沒有 -、最後一段很長（opsx file 收得進來的 slug）也要 ≤32 字、字母開頭 ---
for odd in abcdefghijklmnopqrstuvwxyzabcdef x-abcdefghijklmnopqrstuvwxyzabcd; do
  o1="$( source "$OPSX_ROOT/bin/lib/common.sh"; new_shell "$A" "$odd" "$FX/long.md" )"
  o2="$( source "$OPSX_ROOT/bin/lib/common.sh"; new_shell "$A" "$odd" "$FX/long.md" )"
  assert_eq "$o1" "$odd"
  [[ "$o2" =~ ^[a-z][a-z0-9-]{0,31}$ ]] && [ "$o2" != "$odd" ] || fail "$odd 撞名後不合格：$o2"
done

# --- sources.toml 的 path 本身是 symlink：一樣用實體名，debt 撈得到 ---
mkdir -p "$FX/links"; RS="$(mk_opsx_repo source-real)"; ln -s "$RS" "$FX/links/source-link"
printf '\n[[source]]\nkind = "github"\nrepo = "source-link"\nproject = "me/source-link"\npath = "%s"\n' "$FX/links/source-link" >> "$OPSX_STATE_DIR/sources.toml"
echo "# shortcut: 登記的 symlink, 要建" > "$RS/r.py"
opsx sync --root "$ROOT" --source debt >/dev/null 2>&1
assert_file "$RS/openspec/changes/debt-$(printf '%s' '登記的 symlink, 要建' | shasum -a 1 | cut -c1-8)/inbox.md"

# --- 少了 upstream_updated 的卡（手動改過）：記錯，不默默改寫 ---
python3 -I -c 'import json,sys;print(json.dumps([{"iid":600,"title":"又改了","description":"x","state":"opened","updated_at":"2026-11-07T08:00:00Z","web_url":"u600","labels":[]}]))' > "$OPSX_TEST_ISSUES/a.json"
grep -v '^upstream_updated:' "$H600" > "$FX/h600"; cp "$FX/h600" "$H600"
opsx sync --root "$ROOT" --source gitlab >/dev/null 2>&1
assert_eq "$(cat "$H600")" "$(cat "$FX/h600")" "沒有 upstream_updated 不能改寫"
logcols | cut -f5 | grep -q 'upstream_updated' || fail "要記錯：$(lastsync)"

# --- sources.toml 的 path 不是 repo 根（linked worktree）：不建殼、記錯，不會每次多一張 ---
WT="$FX/elsewhere/wt"; mkdir -p "$WT/openspec/changes"; printf 'gitdir: /nowhere\n' > "$WT/.git"
printf '\n[[source]]\nkind = "gitlab"\nrepo = "wt"\nproject = "g/wt"\npath = "%s"\n' "$WT" >> "$OPSX_STATE_DIR/sources.toml"
printf '[%s]' "$(gl 7 worktree 2026-11-06T08:00:00Z)" > "$OPSX_TEST_ISSUES/wt.json"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert isinstance(d,list) and len(d)==1,d' "$OPSX_TEST_ISSUES/wt.json" || fail "wt.json 要是含一個 issue 的合法 JSON list"
opsx sync --root "$ROOT" --source gitlab >/dev/null 2>&1
assert_eq "$(find "$WT/openspec/changes" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" 0 "worktree 不建殼"
[ "$(logcols | cut -f4)" -ge 1 ] || fail "要記錯：$(lastsync)"
lastsync | grep -qF "$WT 不是 opsx repo 的根目錄" || fail "錯誤要來自 path 不是 repo 根，不是 JSON 解析失敗：$(lastsync)"
rm -f "$OPSX_TEST_ISSUES/wt.json"

# ========== 真實樣本（board-inbox 1.1，tests/fakes/gh-samples/，cli/cli 公開 issue 2026-11-06 實抓）==========
GS="$OPSX_ROOT/tests/fakes/gh-samples"
cp "$GS/issue-list.json" "$OPSX_TEST_ISSUES/gh-z.json"
N="$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))[0]["number"])' "$GS/issue-list.json")"
opsx sync --root "$ROOT" --source github >/dev/null 2>&1
SI="$Z/openspec/changes/gh-z-$N/inbox.md"
assert_file "$SI"; assert_grep "^source: github:z#$N\$" "$SI"; assert_grep "^upstream_url: https://github.com/cli/cli/issues/$N\$" "$SI"
grep -qE '^upstream_updated: 20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$SI" || fail "upstream_updated 要是 updatedAt：$(cat "$SI")"
# list 裡少了它、真樣本的 view 回 CLOSED：標 upstream: closed
printf '[]' > "$OPSX_TEST_ISSUES/gh-z.json"; cp "$GS/issue-view-closed.json" "$OPSX_TEST_ISSUES/gh-view-$N.json"
opsx sync --root "$ROOT" --source github >/dev/null 2>&1
assert_grep '^upstream: closed$' "$SI"

# ========== 沒有 repo 的來源寫進待分類（sync-obsidian / sync-unfiled-sink）==========
# 正式來源都還綁 repo：把 debt 的收集換成固定的、沒有 repo 的 item，再跑 sync.main
sync_unrepo() { # <items json：[{source, slug, title}]>
  python3 -I -c 'import json,sys
sys.path.insert(0, sys.argv[1] + "/bin/lib")
import sync
items = [dict(i, repo=None, path=None, type="功能", body=None, evidence="- 測試來源", extra={}) for i in json.loads(sys.argv[2])]
sync.debt_items = lambda *_: (items, set())
sys.argv = ["opsx sync", "--state", sys.argv[3], "--opsx-root", sys.argv[1], "--root", sys.argv[4], "--source", "debt"]
sys.exit(sync.main())' "$OPSX_ROOT" "$1" "$OPSX_STATE_DIR" "$ROOT"; }
UF="$OPSX_STATE_DIR/unfiled"
repo_changes() { find "$FX" -path "$OPSX_STATE_DIR" -prune -o -path '*/openspec/changes/*' -print | sort; }
unfiled_files() { find "$UF" -maxdepth 1 -name '*.md' | sort; }

# --- 沒有 repo 的新項目：寫進待分類，不在任何 repo 建殼，計入新建 ---
before="$(repo_changes)"
out="$(sync_unrepo '[{"source":"x:1","slug":"ob-1234abcd","title":"收件夾的筆記"}]' 2>&1)"; assert_eq "$?" 0 "sync unrepo: $out"
assert_file "$UF/ob-1234abcd.md"; assert_grep '^source: x:1$' "$UF/ob-1234abcd.md"; assert_grep '^收件夾的筆記$' "$UF/ob-1234abcd.md"
assert_eq "$(repo_changes)" "$before" "沒有 repo 的 item 不能在 repo 建殼"
assert_eq "$(logcols)" "$(printf '1\t0\t0\t0\t')"

# --- 待分類撞名：依序 -2、-3，原檔不動；同一次同步裡重複的 source 只寫一份 ---
printf -- '---\ntype: 功能\nsource: me\n---\n\n## 一句話\n\n手動的\n' > "$UF/ob-5678abcd.md"; cp "$UF/ob-5678abcd.md" "$FX/me-unfiled.md"
sync_unrepo '[{"source":"x:2","slug":"ob-5678abcd","title":"二"},{"source":"x:3","slug":"ob-5678abcd","title":"三"},{"source":"x:2","slug":"ob-5678abcd","title":"二"}]' >/dev/null 2>&1
assert_eq "$(cat "$UF/ob-5678abcd.md")" "$(cat "$FX/me-unfiled.md")" "撞名的原檔不動"
assert_grep '^source: x:2$' "$UF/ob-5678abcd-2.md"; assert_grep '^source: x:3$' "$UF/ob-5678abcd-3.md"
assert_no_file "$UF/ob-5678abcd-4.md"
assert_eq "$(logcols)" "$(printf '2\t0\t0\t0\t')"

# --- 重跑不重複 ---
files="$(unfiled_files)"
sync_unrepo '[{"source":"x:1","slug":"ob-1234abcd","title":"收件夾的筆記"},{"source":"x:2","slug":"ob-5678abcd","title":"二"}]' >/dev/null 2>&1
assert_eq "$(unfiled_files)" "$files"; assert_eq "$(logcols)" "$(printf '0\t0\t2\t0\t')"

# --- 已捨棄的不再進來 ---
mkdir -p "$UF/dropped"; mv "$UF/ob-1234abcd.md" "$UF/dropped/"
files="$(unfiled_files)"
sync_unrepo '[{"source":"x:1","slug":"ob-1234abcd","title":"收件夾的筆記"}]' >/dev/null 2>&1
assert_eq "$(unfiled_files)" "$files" "dropped 裡有同 source 就不再寫"
assert_eq "$(logcols | cut -f1)" 0

# ========== obsidian 收件夾（sync-obsidian / obsidian-source）==========
sync_ob() { opsx sync --root "$ROOT" --source obsidian; }
firstline() { awk -v h="## $1" '$0==h{f=1;next} f&&NF{print;exit}' "$2"; }
sect() { awk -v h="## $1" '$0==h{f=1;next} /^## /{f=0} f' "$2"; }
ob() { printf '%s/ob-%s.md' "$UF" "$(printf '%s' "$1" | shasum -a 1 | cut -c1-8)"; }

# --- 沒設定就不啟用 ---
files="$(unfiled_files)"
out="$(sync_ob 2>&1)"; assert_eq "$?" 0 "沒有 [obsidian]: $out"
assert_eq "$(logcols)" "$(printf '0\t0\t0\t0\t')"; assert_eq "$(unfiled_files)" "$files"

# --- 收件夾不存在：記一筆錯誤，含拼好的路徑 ---
V="$FX/vault"
printf '\n[obsidian]\nvault = "%s"\nfolder = "inbox"\n' "$V" >> "$OPSX_STATE_DIR/sources.toml"
out="$(sync_ob 2>&1)"; assert_eq "$?" 0 "收件夾不存在仍退出 0: $out"
assert_eq "$(logcols | cut -f4)" 1; logcols | cut -f5 | grep -qF "$V/inbox" || fail "錯誤要含拼好的路徑：$(lastsync)"

# --- 新筆記 · 子資料夾 · 隱藏的不收 · 沒有標題用檔名 · frontmatter 不進內文 · 只跑 obsidian ---
mkdir -p "$V/inbox/a" "$V/inbox/.trash"
printf '# 看板要能貼圖\n\n細節\n' > "$V/inbox/想法.md"
printf '子資料夾的\n' > "$V/inbox/a/b.md"
printf '# x\n' > "$V/inbox/.trash/x.md"; printf '# y\n' > "$V/inbox/.y.md"
printf '只有內文\n' > "$V/inbox/待辦.md"
printf -- '---\ntags: [x]\n---\n# 標題\n' > "$V/inbox/n.md"
printf 'x\n' > "$V/inbox/c.txt"
: > "$OPSX_FAKE_LOG"
out="$(sync_ob 2>&1)"; assert_eq "$?" 0 "sync obsidian: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "--source obsidian 不呼叫 glab、gh"
OI="$(ob inbox/想法.md)"
assert_file "$OI"; assert_grep '^source: obsidian:inbox/想法.md$' "$OI"; assert_grep '^type: 功能$' "$OI"
assert_eq "$(firstline 一句話 "$OI")" 看板要能貼圖
sect 內文 "$OI" | grep -q '^細節$' || fail "內文要含細節：$(cat "$OI")"
sect 證據 "$OI" | grep -qF "$V/inbox/想法.md" || fail "證據要有筆記的絕對路徑：$(cat "$OI")"
assert_grep '^source: obsidian:inbox/a/b.md$' "$(ob inbox/a/b.md)"
! grep -l -e '^source: .*\.trash' -e '^source: .*\.y\.md' -e '^source: .*c\.txt' "$UF"/*.md || fail "隱藏的與非 .md 不收"
assert_eq "$(firstline 一句話 "$(ob inbox/待辦.md)")" 待辦
NI="$(ob inbox/n.md)"; assert_not_grep 'tags' "$NI"; assert_eq "$(firstline 一句話 "$NI")" 標題
assert_eq "$(logcols)" "$(printf '4\t0\t0\t0\t')"

# --- 筆記改了不更新 ---
cp "$OI" "$FX/oi.md"; printf '# 改過了\n' > "$V/inbox/想法.md"
sync_ob >/dev/null 2>&1
assert_eq "$(cat "$OI")" "$(cat "$FX/oi.md")" "待分類不依筆記改寫"; assert_eq "$(logcols | cut -f2)" 0

# --- 搬進 repo 後不更新也不記錯 ---
OS="$(basename "$OI" .md)"
out="$(opsx file "$OS" --repo "$A" 2>&1)" || fail "opsx file: $out"
FI="$CH/$OS/inbox.md"; assert_file "$FI"; cp "$FI" "$FX/fi.md"
printf '# 又改了\n' > "$V/inbox/想法.md"
sync_ob >/dev/null 2>&1
assert_eq "$(cat "$FI")" "$(cat "$FX/fi.md")" "搬進 repo 後不依筆記改寫"
assert_eq "$(logcols | cut -f2,4)" "$(printf '0\t0')"

# --- 一篇不是 UTF-8 的筆記只記一筆錯誤，其他照建；U+2028 不會切斷 JSON ---
printf '\xa4\xa4\xa4\xe5\n' > "$V/inbox/big5.md"
printf '# 正常\n' > "$V/inbox/ok.md"
printf '# 分隔\nline\342\200\250two\n' > "$V/inbox/sep.md"
out="$(sync_ob 2>&1)"; assert_eq "$?" 0 "壞筆記不拖垮來源: $out"
assert_file "$(ob inbox/ok.md)"; assert_file "$(ob inbox/sep.md)"
assert_eq "$(logcols | cut -f1,4)" "$(printf '2\t1')"
logcols | cut -f5 | grep -qF "$V/inbox/big5.md" || fail "錯誤要含壞檔路徑：$(lastsync)"
rm "$V/inbox/big5.md"

# --- 讀不了的筆記（權限、iCloud 下載中）只記一筆錯誤，其他照建 ---
printf '# 鎖住的\n' > "$V/inbox/locked.md"; chmod 000 "$V/inbox/locked.md"
printf '# 也正常\n' > "$V/inbox/ok2.md"
out="$(sync_ob 2>&1)"; assert_eq "$?" 0 "讀不了的筆記不拖垮來源: $out"
assert_file "$(ob inbox/ok2.md)"
assert_eq "$(logcols | cut -f1,4)" "$(printf '1\t1')"
logcols | cut -f5 | grep -qF "$V/inbox/locked.md" || fail "錯誤要含讀不了的檔案路徑：$(lastsync)"
rm -f "$V/inbox/locked.md"

# --- folder 空或絕對路徑：記錯，不把整個 vault 當收件夾 ---
printf '# 根目錄的\n' > "$V/root.md"
cp "$OPSX_STATE_DIR/sources.toml" "$FX/sources.bak"
sed -i '' 's|^folder = "inbox"$|folder = ""|' "$OPSX_STATE_DIR/sources.toml"
sync_ob >/dev/null 2>&1
assert_eq "$(logcols | cut -f1,4)" "$(printf '0\t1')"; assert_no_file "$(ob root.md)"
sed -i '' "s|^folder = \"\"\$|folder = \"$V\"|" "$OPSX_STATE_DIR/sources.toml"
sync_ob >/dev/null 2>&1
assert_eq "$(logcols | cut -f1,4)" "$(printf '0\t1')"; assert_no_file "$(ob root.md)"
# . 等於整個 vault，.. 跑到 vault 外
sed -i '' "s|^folder = \".*\"\$|folder = \".\"|" "$OPSX_STATE_DIR/sources.toml"
sync_ob >/dev/null 2>&1
assert_eq "$(logcols | cut -f1,4)" "$(printf '0\t1')"; assert_no_file "$(ob root.md)"
mkdir -p "$FX/outside"; printf '# vault 外的\n' > "$FX/outside/o.md"
sed -i '' "s|^folder = \".*\"\$|folder = \"../outside\"|" "$OPSX_STATE_DIR/sources.toml"
sync_ob >/dev/null 2>&1
assert_eq "$(logcols | cut -f1,4)" "$(printf '0\t1')"; assert_no_file "$(ob ../outside/o.md)"
cp "$FX/sources.bak" "$OPSX_STATE_DIR/sources.toml"

# --- [customer] 還沒有同步：要說出來，不能靜默（specs/board-sync「customer 來源尚未支援時明說」）---
NOTICE='customer 來源尚未支援（on-hold），不會同步'
customer_rows() { awk -F'\t' '$2=="customer"' "$LOG"; }
out="$(sync_debt 2>&1)"; assert_eq "$?" 0 "沒有 [customer]: $out"
case "$out" in *customer*) fail "沒有 [customer] 不該提 customer：$out" ;; esac
assert_eq "$(customer_rows)" "" "沒有 [customer] 不寫 customer 列"
printf '\n[customer]\nbase_url = "https://x.example"\ntoken_env = "T"\nlist_endpoint = "/api/reports"\n' >> "$OPSX_STATE_DIR/sources.toml"
out="$(sync_debt 2>&1)"; assert_eq "$?" 0 "有 [customer] 退出碼照舊: $out"
case "$out" in *"$NOTICE"*) ;; *) fail "有 [customer] 要印提示（--source debt 也要）：$out" ;; esac
assert_eq "$(customer_rows | wc -l | tr -d ' ')" 1 "customer 一列"
assert_eq "$(customer_rows | cut -f3,4)" "$(printf '0\t%s' "$NOTICE")" "customer 列：新卡數 0、文字是提示"
assert_eq "$(logcols | cut -f4)" 0 "提示不算錯誤"
assert_eq "$(awk -F'\t' '$2=="sync"' "$LOG" | tail -1 | cut -f4 | grep -c customer)" 0 "sync 列文字不含 customer"
assert_rc 2 opsx sync --root "$ROOT" --source customer
cp "$FX/sources.bak" "$OPSX_STATE_DIR/sources.toml"

# --- 卡在同步中途被歸檔 ---
# 去重索引建好之後、處理那張卡之前，卡目錄被搬進 archive/（specs/board-sync「卡在同步中途被搬走不中斷同步」）。
# 在隔離的 state / repo 目錄裡跑 sync.main，build_index 換成「回手造的索引，再搬走指定的卡」，不靠 sleep
python3 -I -c '
import os, pathlib, shlex, shutil, sys, threading, time

sys.path.insert(0, sys.argv[1] + "/bin/lib")
import sync

OPSX_ROOT, WORK, STATE = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
CARDS, ARCHIVE = WORK / "changes", WORK / "changes" / "archive"
for d in (CARDS, ARCHIVE, WORK / "root"):
    d.mkdir(parents=True)
PLAN = {"index": {}, "items": [], "listed": {}, "scanned": set(), "move": None}
real_build_index = sync.build_index
CARD = "---\ntype: 功能\nsource: %s\nline: 1\nupstream_updated: 2026-11-05T10:00:00Z\n---\n\n## 一句話\n\n舊\n\n## 內文\n\n舊內文\n\n## 證據\n\n- x\n"


def make_card(slug, source):
    d = CARDS / slug
    d.mkdir()
    (d / "inbox.md").write_text(CARD % source, encoding="utf-8")
    return {"path": d / "inbox.md", "frozen": False}


def index_then_move(repos, state):
    if PLAN["move"]:
        shutil.move(str(CARDS / PLAN["move"]), str(ARCHIVE / PLAN["move"]))
    return PLAN["index"]


def items_of_plan(*_):
    return PLAN["items"], PLAN["scanned"]


def issues_of_plan(*_):
    return PLAN["items"], PLAN["listed"]


def run_sync(source, index, items, move, listed=None, scanned=None):
    PLAN.update(index=index, items=items, move=move, listed=listed or {}, scanned=scanned or set())
    sys.argv = ["opsx sync", "--state", str(STATE), "--opsx-root", OPSX_ROOT, "--root", str(WORK / "root"), "--source", source]
    rc = sync.main()
    rows = [l.split("\t") for l in (STATE / "sync.log").read_text(encoding="utf-8").splitlines() if l.split("\t")[1] == "sync"]
    return rc, rows[-1][3]


sync.build_index = index_then_move
sync.debt_items = items_of_plan
sync.issue_items = issues_of_plan

# 更新 shortcut 卡時卡已被歸檔：計沒變，其餘照常
a, b = make_card("debt-a", "shortcut:r:f.py:aaaa1111"), make_card("debt-b", "shortcut:r:g.py:bbbb2222")
before = a["path"].read_text(encoding="utf-8")
items = [{"source": "shortcut:r:f.py:aaaa1111", "path": WORK, "extra": {"line": "5"}},
         {"source": "shortcut:r:g.py:bbbb2222", "path": WORK, "extra": {"line": "1"}}]
rc, row = run_sync("debt", {"shortcut:r:f.py:aaaa1111": a, "shortcut:r:g.py:bbbb2222": b}, items, "debt-a")
assert rc == 0 and row == "新建 0 · 更新 0 · 沒變 2 · 錯誤 0", (rc, row)
assert (ARCHIVE / "debt-a" / "inbox.md").read_text(encoding="utf-8") == before

# 更新 issue 時卡已被歸檔：計沒變，歸檔的卡內容不變
c = make_card("gl-a-1", "gitlab:a#1")
before = c["path"].read_text(encoding="utf-8")
items = [{"source": "gitlab:a#1", "path": WORK, "updated_at": "2026-11-06T08:00:00Z", "title": "新", "body": "新內文"}]
rc, row = run_sync("gitlab", {"gitlab:a#1": c}, items, "gl-a-1")
assert rc == 0 and row == "新建 0 · 更新 0 · 沒變 1 · 錯誤 0", (rc, row)
assert (ARCHIVE / "gl-a-1" / "inbox.md").read_text(encoding="utf-8") == before

# 標 issue 關閉時卡已被歸檔：其他 issue 卡的 closed 標記照寫
d, e = make_card("gl-a-2", "gitlab:a#2"), make_card("gl-a-3", "gitlab:a#3")
views = pathlib.Path(os.environ["OPSX_TEST_ISSUES"])
for n in (2, 3):
    (views / ("view-%d.json" % n)).write_text("{\"iid\":%d,\"state\":\"closed\"}" % n, encoding="utf-8")
rc, row = run_sync("gitlab", {"gitlab:a#2": d, "gitlab:a#3": e}, [], "gl-a-2", listed={"a": "g/a"})
assert rc == 0 and row == "新建 0 · 更新 1 · 沒變 0 · 錯誤 0", (rc, row)
assert "\nupstream: closed\n" in e["path"].read_text(encoding="utf-8")

# 標 stale 時卡已被歸檔：其他 shortcut 卡的 stale 標記照寫
f, g = make_card("debt-c", "shortcut:r:h.py:cccc3333"), make_card("debt-d", "shortcut:r:i.py:dddd4444")
rc, row = run_sync("debt", {"shortcut:r:h.py:cccc3333": f, "shortcut:r:i.py:dddd4444": g}, [], "debt-c", scanned={"r"})
assert rc == 0 and row == "新建 0 · 更新 1 · 沒變 0 · 錯誤 0", (rc, row)
assert "\nstale: true\n" in g["path"].read_text(encoding="utf-8")

# 建索引時檔案讀不到（待分類裡指向已不存在的檔）：略過，其餘照進索引
unfiled = WORK / "state5" / "unfiled"
unfiled.mkdir(parents=True)
(unfiled / "gone.md").symlink_to(WORK / "nowhere.md")
(unfiled / "ok.md").write_text(CARD % "x:1", encoding="utf-8")
index = real_build_index({}, WORK / "state5")
assert list(index) == ["x:1"], index

# 寫入在卡目錄鎖內重讀再寫（specs/board-sync「既有卡的寫入在卡目錄鎖內重讀再寫」）
def run_into(out, *args):
    out.append(run_sync(*args))


def set_closed_hook(card):
    return shlex.join(["perl", "-0pi", "-e", "s/line: 1\\n/line: 1\\nupstream: closed\\n/", str(card)])


def view_closed(n):
    (views / ("view-%d.json" % n)).write_text("{\"iid\":%d,\"state\":\"closed\"}" % n, encoding="utf-8")


MERGED = "\n## 併入：2026-11-11T15:00:00+08:00 me\n\n- id: m1\n- kind_of_work: planned\n- area: x\n\n併入的一句\n"
UPDATE = {"updated_at": "2026-11-06T08:00:00Z", "title": "新", "body": "新內文"}

# 標 issue 關閉期間（查上游狀態時）併入新段：closed 與併入的段都在
h = make_card("gl-a-4", "gitlab:a#4")
view_closed(4)
os.environ["OPSX_TEST_GLAB_VIEW_HOOK"] = shlex.join(
    ["python3", "-I", OPSX_ROOT + "/bin/lib/inboxmerge.py", "append", str(h["path"].parent), "m1", "2026-11-11T15:00:00+08:00", "me", "planned", "", "x", "併入的一句"])
rc, row = run_sync("gitlab", {"gitlab:a#4": h}, [], None, listed={"a": "g/a"})
text = h["path"].read_text(encoding="utf-8")
assert rc == 0 and "\nupstream: closed\n" in text and "## 併入：" in text, (rc, row, text)

# 鎖內重讀發現已經是 closed：不寫、不計更新
i = make_card("gl-a-5", "gitlab:a#5")
view_closed(5)
os.environ["OPSX_TEST_GLAB_VIEW_HOOK"] = set_closed_hook(i["path"])
rc, row = run_sync("gitlab", {"gitlab:a#5": i}, [], None, listed={"a": "g/a"})
assert rc == 0 and row == "新建 0 · 更新 0 · 沒變 0 · 錯誤 0", (rc, row)
del os.environ["OPSX_TEST_GLAB_VIEW_HOOK"]

# 別人持著卡鎖時，更新 issue 要等；放鎖後 sync 的更新與併入的段都在
j = make_card("gl-a-6", "gitlab:a#6")
out = []
with sync.safefile.CardLock(str(j["path"].parent)):
    t = threading.Thread(target=run_into, args=(out, "gitlab", {"gitlab:a#6": j}, [dict(UPDATE, source="gitlab:a#6", path=WORK)], None))
    t.start()
    time.sleep(0.3)
    assert t.is_alive(), "sync 沒有等卡鎖"
    j["path"].write_text(j["path"].read_text(encoding="utf-8") + MERGED, encoding="utf-8")
t.join(10)
text = j["path"].read_text(encoding="utf-8")
assert out[0][0] == 0 and "新內文" in text and "## 併入：" in text, (out, text)

# 等鎖期間卡被歸檔：計沒變，不是錯誤
k = make_card("gl-a-7", "gitlab:a#7")
out = []
with sync.safefile.CardLock(str(k["path"].parent)):
    t = threading.Thread(target=run_into, args=(out, "gitlab", {"gitlab:a#7": k}, [dict(UPDATE, source="gitlab:a#7", path=WORK)], None))
    t.start()
    time.sleep(0.3)
    shutil.move(str(CARDS / "gl-a-7"), str(ARCHIVE / "gl-a-7"))
t.join(10)
assert out[0] == (0, "新建 0 · 更新 0 · 沒變 1 · 錯誤 0"), out
' "$OPSX_ROOT" "$FX/mid" "$OPSX_STATE_DIR" || fail "卡在同步中途被歸檔"

# --- issue 內文含 U+2028：只按換行切 JSON 行，sync 不崩潰（me-20261111-1824 G1）---
printf '[{"iid":777,"title":"含行分隔符","description":"前\xe2\x80\xa8後","state":"opened","updated_at":"2026-11-07T10:00:00Z","web_url":"https://gitlab.example/g/x/-/issues/777","labels":[]}]' > "$OPSX_TEST_ISSUES/a.json"
printf '[]' > "$OPSX_TEST_ISSUES/Acmecorp-CS.json"; rm -f "$OPSX_TEST_ISSUES/wt.json"   # wt.json 是上面 worktree 那段留下的壞 JSON（gl 的第 4 個參數被當成 labels）
out="$(opsx sync --root "$ROOT" --source gitlab 2>&1)"; assert_eq "$?" 0 "U+2028 的 issue 不該讓 sync 崩潰：$out"
[ -f "$CH/gl-a-777/inbox.md" ] || fail "U+2028 的 issue 要建殼：${out}"
assert_eq "$(awk -F'\t' '$2=="sync"' "$LOG" | tail -1 | cut -f1 | wc -l | tr -d ' ')" 1 "sync.log 要有這次的列"

echo ok
