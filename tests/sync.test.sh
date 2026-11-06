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
logcols() { tail -1 "$LOG" | cut -f2-6; }

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
assert_eq "$(wc -l < "$LOG" | tr -d ' ')" 1
assert_eq "$(logcols)" "$(printf '1\t0\t0\t0\t')"
tail -1 "$LOG" | cut -f1 | grep -qE '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9]{2}:[0-9]{2}$' || fail "at 要 ISO 8601 含時區：$(tail -1 "$LOG")"

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
assert_rc 2 opsx sync --root "$ROOT" --source obsidian

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
# ========== gitlab / github ==========
CS="$(mk_opsx_repo Agentory-CS)"; mv "$CS" "$ROOT/Agentory-CS"; CS="$(cd "$ROOT/Agentory-CS" && pwd -P)"
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
repo = "Agentory-CS"
project = "agentory/agentory-cs"
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
printf '[%s]' "$(gl 9 大寫的 2026-11-05T10:00:00Z)" > "$OPSX_TEST_ISSUES/Agentory-CS.json"
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
assert_grep '^source: gitlab:Agentory-CS#9$' "$CS/openspec/changes/gl-agentory-cs-9/inbox.md"
GI="$Z/openspec/changes/gh-z-3/inbox.md"
assert_grep '^source: github:z#3$' "$GI"; assert_grep '^type: 功能$' "$GI"; assert_grep '^upstream_url: https://github.com/me/z/issues/3$' "$GI"
assert_eq "$(find "$B/openspec/changes" -mindepth 1 -maxdepth 1 ! -name archive | wc -l | tr -d ' ')" 0 "沒登記在 sources.toml 的 repo 不撈"
assert_eq "$(grep -c '^issue list' "$OPSX_FAKE_LOG")" 3 "兩個 gitlab、一個 github 各 list 一次：$(cat "$OPSX_FAKE_LOG")"

# --- 重跑不長新卡 ---
snap_all() { find "$A/openspec/changes" "$CS/openspec/changes" "$Z/openspec/changes" -mindepth 1 -maxdepth 1 | sort; }
before="$(snap_all)"; opsx sync --root "$ROOT" >/dev/null 2>&1
assert_eq "$(snap_all)" "$before"; assert_eq "$(tail -1 "$LOG" | cut -f2)" 0

# --- 還沒 explore 的卡內容更新：一句話換新、upstream_updated 換新 ---
printf '[%s,%s]' "$(gl 412 鍵盤蓋住輸入框 2026-11-06T08:00:00Z '["bug"]')" "$(gl 500 撞名的 2026-11-05T10:00:00Z)" > "$OPSX_TEST_ISSUES/a.json"
# --- explore 過的卡內容更新：一句話不變，證據多一行 ---
printf '## 已知\n' > "$CS/openspec/changes/gl-agentory-cs-9/explore.md"
printf '[%s]' "$(gl 9 改過的標題 2026-11-06T08:00:00Z)" > "$OPSX_TEST_ISSUES/Agentory-CS.json"
opsx sync --root "$ROOT" >/dev/null 2>&1
assert_eq "$(awk '/^## 一句話/{f=1;next} f&&NF{print;exit}' "$I")" 鍵盤蓋住輸入框
assert_grep '^鍵盤蓋住輸入框 的內文$' "$I"; assert_not_grep '^聊天視窗被鍵盤蓋住 的內文$' "$I"
assert_grep '^upstream_updated: 2026-11-06T08:00:00Z$' "$I"
CI="$CS/openspec/changes/gl-agentory-cs-9/inbox.md"
assert_eq "$(awk '/^## 一句話/{f=1;next} f&&NF{print;exit}' "$CI")" 大寫的
awk '/^## 證據/{f=1;next} /^## /{f=0} f' "$CI" | grep -q 'gitlab:Agentory-CS#9.*2026-11-06' || fail "證據要多一行更新：$(cat "$CI")"
assert_eq "$(tail -1 "$LOG" | cut -f3)" 2
opsx sync --root "$ROOT" >/dev/null 2>&1
assert_eq "$(grep -c 'gitlab:Agentory-CS#9' "$CI")" 2 "同一次更新不重複追加（source 那行加一行證據）"

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
[ "$(tail -1 "$LOG" | cut -f5)" -ge 1 ] || fail "errors 要 >= 1：$(tail -1 "$LOG")"
tail -1 "$LOG" | cut -f6 | grep -q '401' || fail "first_error 要含 glab 的 stderr：$(tail -1 "$LOG")"

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

# --- 少了 upstream_updated 的卡（手動改過）：記錯，不默默改寫 ---
python3 -I -c 'import json,sys;print(json.dumps([{"iid":600,"title":"又改了","description":"x","state":"opened","updated_at":"2026-11-07T08:00:00Z","web_url":"u600","labels":[]}]))' > "$OPSX_TEST_ISSUES/a.json"
grep -v '^upstream_updated:' "$H600" > "$FX/h600"; cp "$FX/h600" "$H600"
opsx sync --root "$ROOT" --source gitlab >/dev/null 2>&1
assert_eq "$(cat "$H600")" "$(cat "$FX/h600")" "沒有 upstream_updated 不能改寫"
tail -1 "$LOG" | cut -f6 | grep -q 'upstream_updated' || fail "要記錯：$(tail -1 "$LOG")"

# --- sources.toml 的 path 不是 repo 根（linked worktree）：不建殼、記錯，不會每次多一張 ---
WT="$FX/elsewhere/wt"; mkdir -p "$WT/openspec/changes"; printf 'gitdir: /nowhere\n' > "$WT/.git"
printf '\n[[source]]\nkind = "gitlab"\nrepo = "wt"\nproject = "g/wt"\npath = "%s"\n' "$WT" >> "$OPSX_STATE_DIR/sources.toml"
printf '[%s]' "$(gl 7 worktree 的 2026-11-06T08:00:00Z)" > "$OPSX_TEST_ISSUES/wt.json"
opsx sync --root "$ROOT" --source gitlab >/dev/null 2>&1
assert_eq "$(find "$WT/openspec/changes" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" 0 "worktree 不建殼"
[ "$(tail -1 "$LOG" | cut -f5)" -ge 1 ] || fail "要記錯：$(tail -1 "$LOG")"

echo ok
