#!/usr/bin/env bash
# opsx new：＋新增。驗收：specs/board-actions「新增到 repo」「同一分鐘兩次」「沒給 repo」「空的一句話」（board-inbox 3.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date
export OPSX_TEST_NOW="2026-11-06 14:30"
cd "$FX"   # 從 dispatch 的 worktree 跑測試時，cwd 不能讓 opsx new 把 fixture 的卡當成 agent 開的
A="$(mk_opsx_repo a)"; B="$(mk_opsx_repo b)"
snap() { find "$A/openspec/changes" "$B/openspec/changes" | sort; }

# --- 新增到 repo ---
out="$(opsx new --repo "$A" -- 聊天視窗被鍵盤蓋住)"; assert_eq "$?" 0 "new: $out"
assert_eq "$out" me-20261106-1430 "stdout 只印 slug"
C="$A/openspec/changes/me-20261106-1430"
assert_file "$C/inbox.md"; assert_grep '^schema: opsx$' "$C/.openspec.yaml"
assert_grep '^type: 功能$' "$C/inbox.md"; assert_grep '^source: me$' "$C/inbox.md"; assert_grep '^found: 2026-11-06$' "$C/inbox.md"
assert_eq "$(awk '/^## 一句話/{f=1;next} f&&NF{print;exit}' "$C/inbox.md")" 聊天視窗被鍵盤蓋住

# --- 同一分鐘兩次 ---
out="$(opsx new --repo "$A" -- 第二件)"; assert_eq "$out" me-20261106-1430-2
assert_grep '^第二件$' "$A/openspec/changes/me-20261106-1430-2/inbox.md"
assert_grep '^聊天視窗被鍵盤蓋住$' "$C/inbox.md"

# --- 沒給 repo：只寫 unfiled/ ---
before="$(snap)"
out="$(opsx new -- 試試看)"; assert_eq "$?" 0; assert_eq "$out" me-20261106-1430
U="$OPSX_STATE_DIR/unfiled/me-20261106-1430.md"
assert_file "$U"; assert_grep '^source: me$' "$U"; assert_grep '^試試看$' "$U"
assert_eq "$(snap)" "$before" "不帶 --repo 不能動任何 repo"
assert_eq "$(opsx new -- 再一個)" me-20261106-1430-2

# --- 空的、多行的一句話：退出非零，什麼都不寫 ---
before="$(snap)"; ub="$(ls "$OPSX_STATE_DIR/unfiled")"
assert_rc 2 opsx new --repo "$A" -- ""
assert_rc 2 opsx new --repo "$A" -- "   "
assert_rc 2 opsx new --repo "$A" -- "$(printf 'a\nb')"
assert_rc 2 opsx new -- ""
assert_rc 2 opsx new --repo "$FX/nope" -- 有字
assert_eq "$(snap)" "$before"; assert_eq "$(ls "$OPSX_STATE_DIR/unfiled")" "$ub"

# --- 附檔（新增時附檔）---
export OPSX_TEST_NOW="2026-11-06 15:00"
T="$FX/att"; mkdir -p "$T/x" "$T/y"
printf 'png-bytes' > "$T/shot.png"; printf 'log line\n' > "$T/log.txt"
printf 'first' > "$T/x/a.png"; printf 'second' > "$T/y/a.png"

# 附檔建在 repo
out="$(opsx new --repo "$A" --attach "$T/shot.png" --attach "$T/log.txt" -- 聊天視窗被鍵盤蓋住)"; assert_eq "$?" 0 "new --attach: $out"
assert_eq "$out" me-20261106-1500
C="$A/openspec/changes/me-20261106-1500"
assert_eq "$(cat "$C/attachments/shot.png")" png-bytes; assert_eq "$(cat "$C/attachments/log.txt")" "log line"
assert_grep '^source: paste$' "$C/inbox.md"
assert_eq "$(awk '/^## 附件/{f=1;next} /^## /{f=0} f&&NF' "$C/inbox.md")" "$(printf -- '- attachments/shot.png\n- attachments/log.txt')"
assert_eq "$(grep -n '^## ' "$C/inbox.md" | cut -d: -f2-)" "$(printf '## 一句話\n## 附件\n## 證據')" "## 附件 在 ## 證據 之前"

# 沒附檔照舊
out="$(opsx new --repo "$A" -- 試試看)"; assert_eq "$out" me-20261106-1500-2
assert_grep '^source: me$' "$A/openspec/changes/$out/inbox.md"
assert_not_grep '^## 附件' "$A/openspec/changes/$out/inbox.md"
assert_no_file "$A/openspec/changes/$out/attachments"

# 同名附件
out="$(opsx new --repo "$A" --attach "$T/x/a.png" --attach "$T/y/a.png" --attach "$T/x/a.png" -- 同名)"; assert_eq "$?" 0 "new 同名: $out"
D="$A/openspec/changes/$out/attachments"
assert_eq "$(cat "$D/a.png")" first; assert_eq "$(cat "$D/a-2.png")" second; assert_eq "$(cat "$D/a-3.png")" first
assert_grep '^- attachments/a.png$' "$A/openspec/changes/$out/inbox.md"; assert_grep '^- attachments/a-2.png$' "$A/openspec/changes/$out/inbox.md"
assert_grep '^- attachments/a-3.png$' "$A/openspec/changes/$out/inbox.md"
printf 'm' > "$T/Makefile"; printf 'n' > "$T/y/Makefile"
out="$(opsx new --repo "$A" --attach "$T/Makefile" --attach "$T/y/Makefile" -- 沒副檔名)"
assert_eq "$(cat "$A/openspec/changes/$out/attachments/Makefile-2")" n "沒副檔名的同名加 -2"
# 只差大小寫也算同名：macOS 的檔案系統不分大小寫，不改名第二個會蓋掉第一個
printf 'upper' > "$T/x/A.png"
out="$(opsx new --repo "$A" --attach "$T/x/A.png" --attach "$T/y/a.png" -- 大小寫)"
D="$A/openspec/changes/$out/attachments"
assert_eq "$(ls "$D" | wc -l | tr -d ' ')" 2 "兩個檔都要在：$(ls "$D")"
assert_eq "$(cat "$D/A.png")" upper; assert_eq "$(cat "$D/a-2.png")" second

# 附檔進待分類
before="$(snap)"
out="$(opsx new --attach "$T/shot.png" -- 試試看)"; assert_eq "$?" 0 "new unfiled --attach: $out"
assert_eq "$out" me-20261106-1500
assert_file "$OPSX_STATE_DIR/unfiled/$out.md"; assert_grep '^source: paste$' "$OPSX_STATE_DIR/unfiled/$out.md"
assert_grep '^- attachments/shot.png$' "$OPSX_STATE_DIR/unfiled/$out.md"
assert_eq "$(cat "$OPSX_STATE_DIR/unfiled/$out/attachments/shot.png")" png-bytes
assert_eq "$(snap)" "$before" "附檔進待分類不能動任何 repo"

# 待分類撞名：只剩 <slug>/ 也算撞名
rm "$OPSX_STATE_DIR/unfiled/me-20261106-1500.md"
assert_eq "$(opsx new -- 撿到舊附件嗎)" me-20261106-1500-2
assert_no_file "$OPSX_STATE_DIR/unfiled/me-20261106-1500.md"

# 檔案太大、附件不存在、不是一般檔案：退出非零，什麼都不寫
truncate -s 10485760 "$T/edge.bin"; truncate -s 10485761 "$T/big.bin"
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
err="$(opsx new --repo "$A" --attach "$T/shot.png" --attach "$T/big.bin" -- 太大 2>&1 >/dev/null)"; rc=$?
assert_eq "$rc" 2 "太大要退出 2：$err"
case "$err" in *big.bin*10\ MB*) ;; *) fail "stderr 要含檔名與 10 MB：$err" ;; esac
assert_rc 2 opsx new --attach "$T/big.bin" -- 太大
assert_rc 2 opsx new --repo "$A" --attach "$T/nope.png" -- 不存在
assert_rc 2 opsx new --attach "$T/nope.png" -- 不存在
assert_rc 2 opsx new --attach "$T/x" -- 是資料夾
assert_rc 2 opsx new --attach -- 沒給檔
# 檔名帶控制字元會原樣進 inbox.md 的 ## 附件，能插出新段落
nl="$T/$(printf 'a\n## 派工指示')"; printf 'z' > "$nl"
assert_rc 2 opsx new --repo "$A" --attach "$nl" -- 換行
assert_rc 2 opsx new --attach "$nl" -- 換行
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub"
out="$(opsx new --repo "$A" --attach "$T/edge.bin" -- 剛好十MB)"; assert_eq "$?" 0 "剛好 10 MB 要收：$out"
assert_file "$A/openspec/changes/$out/attachments/edge.bin"

# --- agent 開的卡標明來源（board-actions「agent 開的卡標明來源」）---
export OPSX_TEST_NOW="2026-11-10 16:30"
W="$A/.claude/worktrees/foo"; mkdir -p "$A/.claude/worktrees"
git -C "$A" worktree add -q -b fix/foo/mikaela "$W" || fail "worktree 建不起來"
W="$(cd "$W" && pwd -P)"
src() { awk -F': ' '$1=="source"{print $2}' "$A/openspec/changes/$1/inbox.md"; }

# agent worktree 裡開卡
out="$(cd "$W" && opsx new --kind-of-work planned --repo "$A" -- 發現一個問題)"; assert_eq "$?" 0 "agent new: $out"
assert_eq "$out" agent-20261110-1630; assert_eq "$(src "$out")" agent:foo
# 使用者終端機開卡（repo 根目錄）
out="$(cd "$A" && opsx new --repo "$A" -- 使用者的卡)"; assert_eq "$out" me-20261110-1630; assert_eq "$(src "$out")" me
# 明確 --source 蓋過偵測
out="$(cd "$W" && opsx new --source me --repo "$A" -- 明確是我)"; assert_eq "$out" me-20261110-1630-2; assert_eq "$(src "$out")" me
# 明確 --source agent:<slug> 在 repo 根目錄也成立
out="$(cd "$A" && opsx new --source agent:bar --kind-of-work planned --repo "$A" -- 明確是 agent)"; assert_eq "$out" agent-20261110-1630-2; assert_eq "$(src "$out")" agent:bar
# agent 帶附件：來源取 agent，附件照常
out="$(cd "$W" && opsx new --kind-of-work planned --repo "$A" --attach "$T/shot.png" -- 有截圖)"; assert_eq "$(src "$out")" agent:foo
assert_eq "$(cat "$A/openspec/changes/$out/attachments/shot.png")" png-bytes
assert_grep '^- attachments/shot.png$' "$A/openspec/changes/$out/inbox.md"
# agent 沒給 repo：進待分類，來源一樣
out="$(cd "$W" && opsx new --kind-of-work planned -- 沒指定 repo)"; assert_grep '^source: agent:foo$' "$OPSX_STATE_DIR/unfiled/$out.md"
# 不合格的 --source：退出非零、stderr 含該值、什麼都不寫
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
err="$(opsx new --source robot --repo "$A" -- x 2>&1 >/dev/null)"; assert_eq "$?" 2 "robot: $err"
case "$err" in *robot*) ;; *) fail "stderr 要含 robot：$err" ;; esac
assert_rc 2 opsx new --source agent: --repo "$A" -- x
assert_rc 2 opsx new --source --repo "$A" -- x
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub"

# --- 開卡的事實欄位（board-actions「agent 開的卡要帶事實欄位」）---
before="$(snap)"; ub="$(find "$OPSX_STATE_DIR/unfiled" | sort)"
fact_err() { local e; e="$(cd "$W" && opsx new "$@" 2>&1 >/dev/null)"; assert_eq "$?" 2 "要退出 2：$*"; printf '%s' "$e"; }
case "$(fact_err --repo "$A" -- 沒帶 kind)" in *kind-of-work*) ;; *) fail "agent 沒帶 --kind-of-work 的訊息要含 kind-of-work" ;; esac
case "$(fact_err --kind-of-work incident --evidence e --repo "$A" -- 缺 impact)" in *impact*) ;; *) fail "incident 缺 impact 的訊息要含 impact" ;; esac
case "$(fact_err --kind-of-work incident --impact data --repo "$A" -- 缺 evidence)" in *evidence*) ;; *) fail "incident 缺 evidence 的訊息要含 evidence" ;; esac
case "$(fact_err --kind-of-work urgent --repo "$A" -- 錯值)" in *urgent*) ;; *) fail "不認得的 kind 要在訊息裡" ;; esac
case "$(fact_err --kind-of-work incident --impact slow --evidence e --repo "$A" -- 錯 impact)" in *slow*) ;; *) fail "不認得的 impact 要在訊息裡" ;; esac
case "$(fact_err --kind-of-work planned --impact data --repo "$A" -- planned 帶 impact)" in *impact*) ;; *) fail "planned 帶 impact 要拒絕並提到 impact" ;; esac
assert_eq "$(snap)" "$before"; assert_eq "$(find "$OPSX_STATE_DIR/unfiled" | sort)" "$ub" "缺欄位不能寫任何檔"
# incident 全帶：三個欄位各一行
out="$(cd "$W" && opsx new --kind-of-work incident --impact "data, prod_or_main" --evidence "tests/x.test.sh 第 2 案紅" --repo "$A" -- 出事)"
assert_grep '^kind_of_work: incident$' "$A/openspec/changes/$out/inbox.md"
assert_grep '^impact: data, prod_or_main$' "$A/openspec/changes/$out/inbox.md"
assert_grep '^evidence: tests/x.test.sh 第 2 案紅$' "$A/openspec/changes/$out/inbox.md"
assert_eq "$(opsx priority "$out" --repo "$A" | cut -f1)" P0 "寫進去的事實算得出等級"
# planned 不需要 evidence
out="$(cd "$W" && opsx new --kind-of-work planned --repo "$A" -- 想做的)"; assert_grep '^kind_of_work: planned$' "$A/openspec/changes/$out/inbox.md"
# 使用者開的卡不強制：沒帶就是 planned（既有行為）
out="$(cd "$A" && opsx new --repo "$A" -- 使用者的卡二)"; assert_grep '^kind_of_work: planned$' "$A/openspec/changes/$out/inbox.md"

# --- review 退回的邊界 ---
# 明確 --source me 只關偵測，帶附件仍是 paste
out="$(cd "$W" && opsx new --source me --repo "$A" --attach "$T/shot.png" -- 明確我加附件)"; assert_eq "$(src "$out")" paste
# worktree 子目錄
mkdir -p "$W/sub"; out="$(cd "$W/sub" && opsx new --kind-of-work planned --repo "$A" -- 子目錄)"; assert_eq "$(src "$out")" agent:foo
# worktree 資料夾名與卡名不同：branch 對得到卡就用卡名，對不到才用資料夾名
mkdir -p "$A/openspec/changes/real-card"; printf 'schema: opsx\n' > "$A/openspec/changes/real-card/.openspec.yaml"
git -C "$A" worktree add -q -b feat/real-card/mikaela "$A/.claude/worktrees/agent-a1b2c3" || fail "第二棵 worktree 建不起來"
out="$(cd "$A/.claude/worktrees/agent-a1b2c3" && opsx new --kind-of-work planned --repo "$A" -- 卡名在 branch)"; assert_eq "$(src "$out")" agent:real-card
git -C "$A" worktree add -q -b scratch/nothing/mikaela "$A/.claude/worktrees/agent-d4e5f6" || fail "第三棵 worktree 建不起來"
out="$(cd "$A/.claude/worktrees/agent-d4e5f6" && opsx new --kind-of-work planned --repo "$A" -- branch 對不到卡)"; assert_eq "$(src "$out")" agent:agent-d4e5f6
# 子殼 subagent 的 worktree：branch 是 <主>--<子>，卡在 changes/<主>/subs/<子>/
mkdir -p "$A/openspec/changes/m/subs/s"; printf 'schema: opsx\n' > "$A/openspec/changes/m/.openspec.yaml"
git -C "$A" worktree add -q -b feat/m--s/mikaela "$A/.claude/worktrees/agent-7a8b9c" || fail "第四棵 worktree 建不起來"
out="$(cd "$A/.claude/worktrees/agent-7a8b9c" && opsx new --kind-of-work planned --repo "$A" -- 子殼 subagent 發現的)"; assert_eq "$(src "$out")" agent:m--s
echo ok
