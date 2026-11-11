#!/usr/bin/env bash
# opsx late：PR 合併後分支又多的 commit。真 git（bare remote + clone），MR 資料走 mr.sh 的快取檔，不叫 gh。
# remote 的 URL 設成 forge 網址，用 url.<bare>.insteadOf 指回本機的 bare repo，host 才對得上 mr.url。
# 驗收：specs/merged-late-commits/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export OPSX_MR_CACHE_TTL=3600
URL="https://github.com/o/r/pull/8"
BARE="$FX/bare.git"; R="$(mk_repo demo)"; W="$FX/w"
git init -q --bare "$BARE"
git -C "$R" config "url.$BARE.insteadOf" "https://github.com/o/r"
git -C "$R" remote add origin "https://github.com/o/r"
git -C "$R" checkout -q -b feat/g/m
git -C "$R" commit -q --allow-empty -m "feat: first"
git -C "$R" push -q origin feat/g/m
S1="$(git -C "$R" rev-parse HEAD)"
git clone -q "$BARE" "$W" && git -C "$W" config user.email t@t && git -C "$W" config user.name t
git -C "$W" checkout -q feat/g/m
git -C "$W" commit -q --allow-empty -m "fix: pushed after merge"
git -C "$W" push -q origin feat/g/m
S2="$(git -C "$W" rev-parse HEAD)"
CARD="$R/openspec/changes/g"; mkdir -p "$CARD"
printf '## MR\n%s\n' "$URL" > "$CARD/report.md"
printf '{"demo/g":{"mode":"stopped","agent":"claude","pane":"w1:p1","branch":"feat/g/m"}}' > "$OPSX_STATE_DIR/dispatch.json"

# mr_cache <head_sha>：把 mr.sh 的快取寫成「已合併，合併當下的分支 head 是 <head_sha>」
mr_cache() {
  mkdir -p "$OPSX_STATE_DIR/cache"
  printf '{"url":"%s","state":"state:MERGED","head_sha":"%s","conditions":{},"blocked_on":null,"error":null,"created_at":null,"merged_at":"2026-11-07T12:00:00Z"}\n' "$URL" "$1" \
    > "$OPSX_STATE_DIR/cache/mr-$(printf '%s' "$URL" | shasum | cut -c1-12).json"
}
late() { bash "$OPSX_ROOT/bin/opsx" late g --repo "$R" "$@" > "$FX/out" 2> "$FX/err"; }

# --- 合併後多出 commit ---
mr_cache "$S1"
late; rc=$?
assert_eq "$rc" 1 "多出 commit 要退出 1：$(cat "$FX/out" "$FX/err")"
assert_eq "$(sed -n 1p "$FX/out")" "late 1 ${S2:0:7} feat/g/m"
sed -n 2p "$FX/out" | grep -q "pushed after merge" || fail "第二行要有 commit 標題：$(cat "$FX/out")"
assert_no_file "$CARD/gates.md"

# --- 沒有多出的 commit ---
mr_cache "$S2"
late; rc=$?
assert_eq "$rc" 0 "$(cat "$FX/err")"
assert_eq "$(cat "$FX/out")" none

# --- 分支在 remote 已刪 ---
mr_cache "$S1"
git -C "$BARE" branch -q -m feat/g/m feat/g/gone
late; rc=$?
assert_eq "$rc" 0 "remote 沒有這個分支：$(cat "$FX/err")"
assert_eq "$(cat "$FX/out")" none
git -C "$BARE" branch -q -m feat/g/gone feat/g/m

# --- --open-gate：開一次，再跑不重複 ---
late --open-gate; rc=$?
assert_eq "$rc" 1
late --open-gate; rc=$?
assert_eq "$rc" 1
assert_eq "$(grep -c "^## late-${S2:0:7}\$" "$CARD/gates.md")" 1 "gate 只能有一段：$(cat "$CARD/gates.md")"
assert_grep '^status: open$' "$CARD/gates.md"
assert_grep '^type: decision$' "$CARD/gates.md"
assert_grep '^opened_at: ' "$CARD/gates.md"

# --- gate 答過就放行 ---
sed -i '' 's/^status: open$/status: answered/' "$CARD/gates.md"
late; rc=$?
assert_eq "$rc" 0 "$(cat "$FX/err")"
assert_eq "$(cat "$FX/out")" "acked ${S2:0:7}"

# --- 答過之後又推了新 commit ---
git -C "$W" commit -q --allow-empty -m "fix: another"
git -C "$W" push -q origin feat/g/m
S3="$(git -C "$W" rev-parse HEAD)"
late; rc=$?
assert_eq "$rc" 1 "新 head 要再抓：$(cat "$FX/out")"
assert_eq "$(sed -n 1p "$FX/out")" "late 2 ${S3:0:7} feat/g/m"
rm -f "$CARD/gates.md"

# --- 查不出來：host 對不到、head_sha 不在本機、沒有分支名 ---
git -C "$R" remote set-url origin "https://gitlab.example.com/o/r"
late; rc=$?
assert_eq "$rc" 2 "host 對不到要退出 2"
assert_grep 'github.com' "$FX/err"
assert_not_grep none "$FX/out"
git -C "$R" remote set-url origin "https://github.com/o/r"

mr_cache "0000000000000000000000000000000000000000"
late; rc=$?
assert_eq "$rc" 2 "head_sha 不在本機要退出 2"
assert_grep '0000000' "$FX/err"
assert_not_grep none "$FX/out"

mr_cache "$S1"
printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
late; rc=$?
assert_eq "$rc" 2 "沒有分支名要退出 2"
assert_grep 'branch' "$FX/err"

# --- 合併後分支被 force-push：fetch 要能覆蓋 tracking ref（R1.1） ---
printf '{"demo/g":{"mode":"stopped","agent":"claude","pane":"w1:p1","branch":"feat/g/m"}}' > "$OPSX_STATE_DIR/dispatch.json"
git -C "$W" reset -q --hard "$S1"
git -C "$W" commit -q --allow-empty -m "fix: rewritten"
git -C "$W" push -q -f origin feat/g/m
S4="$(git -C "$W" rev-parse HEAD)"
late; rc=$?
assert_eq "$rc" 1 "force-push 後要退出 1：$(cat "$FX/out" "$FX/err")"
assert_eq "$(sed -n 1p "$FX/out")" "late 1 ${S4:0:7} feat/g/m"

# --- 另有一個本機路徑的 remote：host 對得上的 origin 照常被選中（R1.2） ---
git -C "$R" remote add backup "$BARE"
late; rc=$?
assert_eq "$rc" 1 "多一個本機路徑 remote 不能讓整個 repo 退出 2：$(cat "$FX/out" "$FX/err")"
assert_eq "$(sed -n 1p "$FX/out")" "late 1 ${S4:0:7} feat/g/m"
git -C "$R" remote remove backup

# --- 空標題的 commit 在最舊的位置（R1.3） ---
git -C "$W" reset -q --hard "$S1"
git -C "$W" commit -q --allow-empty --allow-empty-message -m ""
git -C "$W" commit -q --allow-empty -m "fix: top"
git -C "$W" push -q -f origin feat/g/m
S5="$(git -C "$W" rev-parse HEAD)"
late; rc=$?
assert_eq "$rc" 1 "空標題不能崩潰：$(cat "$FX/out" "$FX/err")"
assert_eq "$(sed -n 1p "$FX/out")" "late 2 ${S5:0:7} feat/g/m"
assert_not_grep Traceback "$FX/err"

# --- git 逾時（R1.4）：ls-remote 睡過時限，退出 2，不是 none ---
STUB="$FX/stub"; mkdir -p "$STUB"
printf '#!/usr/bin/env bash\ncase "$*" in *ls-remote*) exec sleep 5 ;; esac\nexec %s "$@"\n' "$(command -v git)" > "$STUB/git"; chmod +x "$STUB/git"
OPSX_LATE_GIT_TIMEOUT=1 PATH="$STUB:$PATH" late; rc=$?
assert_eq "$rc" 2 "git 逾時要退出 2：$(cat "$FX/out" "$FX/err")"
assert_grep '逾時' "$FX/err"
assert_not_grep none "$FX/out"

# --- head_sha 不是 sha（R1.5） ---
mr_cache "--x"
late; rc=$?
assert_eq "$rc" 2 "head_sha 不是 sha 要退出 2"
assert_grep 'head_sha' "$FX/err"
assert_grep '[-][-]x' "$FX/err"
mr_cache "$S1"

# --- /archive 的 step 0 不先標這個 change 所屬的 PR 為 merged，由 step 6 在 opsx late 通過後才標（R2.1） ---
sed -n '/^### 0\./,/^### 1\./p' "$OPSX_ROOT/skills/archive/SKILL.md" > "$FX/step0"
assert_grep 'step 6' "$FX/step0"
assert_grep 'except' "$FX/step0"

# --- /archive 在搬目錄之前叫 opsx late ---
SK="$OPSX_ROOT/skills/archive/SKILL.md"
late_line="$(grep -n 'opsx late' "$SK" | head -1 | cut -d: -f1)"
mv_line="$(grep -n 'mv openspec/changes/<name>' "$SK" | head -1 | cut -d: -f1)"
[ -n "$late_line" ] || fail "archive SKILL.md 沒有 opsx late"
[ "$late_line" -lt "$mv_line" ] || fail "opsx late($late_line) 要在搬目錄($mv_line)之前"
echo ok
