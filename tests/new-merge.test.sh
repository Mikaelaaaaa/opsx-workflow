#!/usr/bin/env bash
# opsx new 的自動併入：P2 的 bug／技術債提到的 repo 檔案，跟一張還沒動工的卡提到的檔案有交集，就併進那張的 inbox.md，不建殼。
# 驗收：specs/card-auto-merge「同檔案併入」「不併的情況」每個 Scenario。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date herdr
export OPSX_FAKE_LOG="$FX/herdr.log"
export OPSX_TEST_NOW="2026-11-11 10:40"
cd "$FX"

E="$(mk_opsx_repo e)"
C="$E/openspec/changes"
mkdir -p "$E/bin" "$E/.claude/worktrees"
printf 'x\n' > "$E/bin/x.sh"; printf 'y\n' > "$E/bin/y.sh"
git -C "$E" worktree add -q -b fix/foo/mikaela "$E/.claude/worktrees/foo" || fail "worktree foo 建不起來"
W="$(cd "$E/.claude/worktrees/foo" && pwd -P)"
ER="$(cd "$E" && pwd -P)"
OUT="$FX/out"; ERR="$FX/err"

reset() { rm -rf "$C"/* "$OPSX_FAKE_LOG"; }
card() { # card <slug> <證據> [frontmatter 行…]：只有 inbox.md 的卡（stage explore）
  local s="$1" d="$C/$1" ev="$2"; shift 2
  mkdir -p "$d"; printf 'schema: opsx\n' > "$d/.openspec.yaml"
  { printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-10\nrelated:\nkind_of_work: planned\n'; printf '%s\n' "$@"; printf -- '---\n\n## 一句話\n\n%s\n\n## 證據\n\n%s\n' "$s" "$ev"; } > "$d/inbox.md"
}
to_propose() { # to_propose <slug>：有 explore.md（待決空）、grill.md、proposal.md，沒有 tasks.md
  printf '## 已知\n\n- a\n\n## 待決\n\n## 不做\n\n- c\n' > "$C/$1/explore.md"
  printf 'D1 a\n' > "$C/$1/grill.md"; printf '## Why\n\na\n' > "$C/$1/proposal.md"
}
agent_new() { (cd "$W" && opsx new "$@") > "$OUT" 2> "$ERR"; }
user_new() { (cd "$E" && opsx new "$@") > "$OUT" 2> "$ERR"; }
dirs() { find "$C" -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | LC_ALL=C sort | tr '\n' ' '; }
stage() { (source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; stage_name "$E" "$1"); }
merged_into() { # merged_into <目標>：stdout 是目標、沒有新殼
  assert_eq "$(cat "$OUT")" "$1" "要併進 $1：$(cat "$ERR")"
  assert_eq "$(dirs | tr ' ' '\n' | grep -c .)" "$2" "不建殼：$(dirs)"
}

# --- 同檔案併入 bug ---
reset; card x '`bin/x.sh` 的檢查'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh:12 漏擋"; assert_eq "$?" 0 "併入要退出 0：$(cat "$ERR")"
merged_into x 1
assert_grep '併進 x（id agent-20261111-1040）' "$ERR"
assert_eq "$(find "$E/openspec" -maxdepth 1 -name '.reserve-*' | wc -l | tr -d ' ')" 0 "不留保留目錄"
assert_grep '^## 併入：2026-11-11T10:40:[0-9][0-9]+08:00 agent:foo$' "$C/x/inbox.md"
assert_grep '^- id: agent-20261111-1040$' "$C/x/inbox.md"
assert_grep '^- kind_of_work: planned$' "$C/x/inbox.md"
assert_grep '^- type: bug$' "$C/x/inbox.md"
assert_not_grep '^- area:' "$C/x/inbox.md"; assert_not_grep '^- impact:' "$C/x/inbox.md"; assert_not_grep '^- evidence:' "$C/x/inbox.md"
assert_eq "$(tail -1 "$C/x/inbox.md")" "bin/x.sh:12 漏擋" "一句話是併入段最後一行"
assert_eq "$(grep -c '^## 一句話$' "$C/x/inbox.md")" 1 "原本的內容不動"

# --- 技術債也併 ---
reset; card x 'bin/x.sh'
agent_new --type 技術債 --kind-of-work planned --repo "$E" -- "bin/x.sh 重複"; merged_into x 1
assert_grep '^- type: 技術債$' "$C/x/inbox.md"

# --- 使用者卡帶 bug 也併 ---
reset; card x 'bin/x.sh'
user_new --type bug --repo "$E" -- "bin/x.sh 漏擋"; merged_into x 1
assert_grep '^## 併入：2026-11-11T10:40:[0-9][0-9]+08:00 me$' "$C/x/inbox.md"
assert_grep '^- id: me-20261111-1040$' "$C/x/inbox.md"

# --- 只差行號算同檔案 ---
reset; card x 'bin/x.sh:3'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh:99 錯"; merged_into x 1
reset; card x 'bin/x.sh:3-8.'
agent_new --kind-of-work planned --repo "$E" -- "見 bin/x.sh:99）"; merged_into x 1

# --- 絕對路徑也認（repo 根目錄、worktree 底下）---
reset; card x 'bin/x.sh'
agent_new --kind-of-work planned --evidence "$ER/bin/x.sh:5 紅" --repo "$E" -- 一句話沒路徑; merged_into x 1
reset; card x "$W/bin/x.sh:2"
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 錯"; merged_into x 1

# --- 併入段的檔案也算 ---
reset; card x '沒有路徑'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 錯"; new_out="$(cat "$OUT")"
case "$new_out" in agent-*) ;; *) fail "x 沒提到 bin/x.sh，要建新殼：$new_out" ;; esac
rm -rf "$C/$new_out"
printf '\n## 併入：2026-11-10T09:00:00+08:00 agent:bar\n\n- id: agent-20261110-0900\n- kind_of_work: planned\n- evidence: 見 bin/x.sh\n- type: bug\n\nbin/y.sh 錯\n' >> "$C/x/inbox.md"
agent_new --kind-of-work planned --repo "$E" -- "bin/y.sh 又錯"; merged_into x 1
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 再錯"; merged_into x 1

# --- 目標卡的路徑只在 frontmatter evidence（opsx new --evidence 寫的位置）也算 ---
reset
agent_new --kind-of-work planned --evidence "bin/x.sh:7 紅" --repo "$E" -- 第一張沒寫路徑; first="$(cat "$OUT")"
case "$first" in agent-*) ;; *) fail "第一張要建殼：$first $(cat "$ERR")" ;; esac
assert_grep '^evidence: bin/x.sh:7 紅$' "$C/$first/inbox.md"
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh:9 又紅"; merged_into "$first" 1

# --- 共同檔案多的優先 ---
reset; card a 'bin/x.sh'; card b 'bin/x.sh bin/y.sh'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh bin/y.sh 都錯"; merged_into b 2
assert_not_grep '## 併入' "$C/a/inbox.md"

# --- 平手取字母序第一張 ---
reset; card me-20261109-1000 'bin/x.sh'; card agent-20261110-0900 'bin/x.sh'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 錯"; merged_into agent-20261110-0900 2
assert_not_grep '## 併入' "$C/me-20261109-1000/inbox.md"

# --- 併進 propose 的卡 ---
reset; card x 'bin/x.sh'; to_propose x
assert_eq "$(stage x)" propose "fixture 要是 propose"
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 併進 propose"; merged_into x 1

# --- 同一分鐘兩次併入 ---
reset; card x 'bin/x.sh'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 第一次"
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 第二次"
assert_grep '併進 x（id agent-20261111-1040-2）' "$ERR"
assert_eq "$(grep '^- id:' "$C/x/inbox.md" | tr '\n' ' ')" "- id: agent-20261111-1040 - id: agent-20261111-1040-2 "
assert_eq "$(dirs)" "x "

# --- evidence 帶進去 ---
reset; card x 'bin/x.sh'
agent_new --kind-of-work planned --evidence "bin/x.sh 紅" --repo "$E" -- 有證據; merged_into x 1
assert_grep '^- kind_of_work: planned$' "$C/x/inbox.md"
assert_grep '^- evidence: bin/x.sh 紅$' "$C/x/inbox.md"
assert_not_grep '^- impact:' "$C/x/inbox.md"

# --- 不併的情況：照樣建殼，別的卡不動 ---
keep() { cp "$C/$1/inbox.md" "$FX/keep.md"; }
kept() { cmp -s "$C/$1/inbox.md" "$FX/keep.md" || fail "$1/inbox.md 不該變：$(cat "$C/$1/inbox.md")"; }
new_shell_out() { # 建了新殼：stdout 以 <前綴> 開頭、殼存在、stderr 沒有「併進」
  case "$(cat "$OUT")" in "$1"-*) ;; *) fail "要建新殼（$1-），stdout：$(cat "$OUT") stderr：$(cat "$ERR")" ;; esac
  assert_file "$C/$(cat "$OUT")/inbox.md"; assert_not_grep '併進' "$ERR"
}
# 功能不併
reset; card x 'bin/x.sh'; keep x
agent_new --type 功能 --kind-of-work planned --repo "$E" -- "bin/x.sh 新功能"; new_shell_out agent; kept x
assert_grep '^type: 功能$' "$C/$(cat "$OUT")/inbox.md"
# 想法不併
reset; card x 'bin/x.sh'; keep x
agent_new --type 想法 --kind-of-work planned --repo "$E" -- "bin/x.sh 想法"; new_shell_out agent; kept x
# 使用者卡預設待定不併
reset; card x 'bin/x.sh'; keep x
user_new --repo "$E" -- "bin/x.sh 漏擋"; new_shell_out me; kept x
assert_grep '^type: 待定$' "$C/$(cat "$OUT")/inbox.md"
# incident 一律不併
reset; card x 'bin/x.sh'; keep x
agent_new --kind-of-work incident --impact workaround_exists --evidence "bin/x.sh" --repo "$E" -- 有繞法; new_shell_out agent; kept x
reset; card x 'bin/x.sh'; keep x
agent_new --kind-of-work incident --impact security --evidence "bin/x.sh" --repo "$E" -- P0; new_shell_out agent; kept x
# 目標 P0 不併
reset; card x 'bin/x.sh' 'kind_of_work: incident' 'impact: security' 'evidence: e'; keep x
sed -i '' '/^kind_of_work: planned$/d' "$C/x/inbox.md"; keep x
assert_eq "$(opsx priority x --repo "$E" | cut -f1)" P0 "fixture 要是 P0"
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 漏擋"; new_shell_out agent; kept x
# 目標 P0 跳過，下一張有共同檔案的照併
rm -rf "$C/$(cat "$OUT")"; card y 'bin/x.sh'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 再漏"; assert_eq "$(cat "$OUT")" y "$(cat "$ERR")"; kept x
# 目標等級算不出來不併
reset; card x 'bin/x.sh' 'impact: slow'; keep x
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 漏擋"; new_shell_out agent; kept x
assert_grep 'x' "$ERR"; assert_grep '等級' "$ERR"
# 沒有路徑不併
reset; card x 'bin/x.sh 鉤子'; keep x
agent_new --kind-of-work planned --repo "$E" -- 鉤子漏擋; new_shell_out agent; kept x
# 路徑不存在不併（目錄也不算檔案）
reset; card x 'bin/nope.sh bin'; keep x
agent_new --kind-of-work planned --repo "$E" -- "bin/nope.sh 錯"; new_shell_out agent; kept x
agent_new --kind-of-work planned --repo "$E" -- "bin/ 錯"; new_shell_out agent; kept x
# repo 外的絕對路徑不算
reset; card x 'bin/x.sh'; keep x; mkdir -p "$FX/bin"; printf 'o\n' > "$FX/bin/x.sh"
agent_new --kind-of-work planned --repo "$E" -- "$FX/bin/x.sh 錯"; new_shell_out agent; kept x
# 沒有共同檔案不併
reset; card y 'bin/y.sh'; keep y
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 錯"; new_shell_out agent; kept y
# 目標已有 tasks.md
reset; card x 'bin/x.sh'; to_propose x; printf -- '- [ ] 1.1 a\n' > "$C/x/tasks.md"; keep x
assert_eq "$(stage x)" apply "fixture 要是 apply"
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 已有 tasks"; new_shell_out agent; kept x
# 目標已拆
reset; card x 'bin/x.sh' "split_into: [x-a, x-b]"; keep x
assert_eq "$(stage x)" split "fixture 要是 split"
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 已拆"; new_shell_out agent; kept x
# 不併進自己的卡（worktree foo 對到卡 foo）
reset; card foo 'bin/x.sh'; to_propose foo; keep foo
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 自己的範圍外"; new_shell_out agent; kept foo
# 子殼 subagent（branch foo--s）也不併進主殼 foo
reset; card foo 'bin/x.sh'; mkdir -p "$C/foo/subs/s"; keep foo
git -C "$E" worktree add -q -b feat/foo--s/mikaela "$E/.claude/worktrees/agent-a1" || fail "子殼 worktree 建不起來"
(cd "$E/.claude/worktrees/agent-a1" && opsx new --kind-of-work planned --repo "$E" -- "bin/x.sh 子殼的範圍外") > "$OUT" 2> "$ERR"
new_shell_out agent; kept foo; assert_grep '^source: agent:foo--s$' "$C/$(cat "$OUT")/inbox.md"
# 帶附件不併
reset; card x 'bin/x.sh'; keep x; printf 'png' > "$FX/a.png"
agent_new --kind-of-work planned --repo "$E" --attach "$FX/a.png" -- "bin/x.sh 有附件"; new_shell_out agent; kept x
assert_eq "$(cat "$C/$(cat "$OUT")/attachments/a.png")" png
# 一句話像段落結構不併
reset; card x 'bin/x.sh'; keep x
agent_new --kind-of-work planned --repo "$E" -- "## bin/x.sh"; new_shell_out agent; kept x
assert_grep '^## bin/x.sh$' "$C/$(cat "$OUT")/inbox.md"
agent_new --kind-of-work planned --repo "$E" -- "- id: x-1 bin/x.sh"; new_shell_out agent; kept x
agent_new --kind-of-work planned --repo "$E" -- "- type: bug bin/x.sh"; new_shell_out agent; kept x
agent_new --kind-of-work planned --repo "$E" -- "- area: board bin/x.sh"; new_shell_out agent; kept x

# --- 讀不了的候選卡不能讓新項目遺失（review R1.2）---
# 一張 inbox.md 不是 UTF-8：照常建殼，stderr 有警告，x 不動
reset; card x 'bin/x.sh'; card bad 'bin/x.sh'; printf '\xff\xfe\n' >> "$C/bad/inbox.md"; keep x
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 有壞卡"; assert_eq "$?" 0 "壞卡不能讓 opsx new 失敗：$(cat "$ERR")"
new_shell_out agent; kept x; assert_grep 'opsx: new:' "$ERR"
# 候選 slug 對不到檔案（列出候選後卡被 drop／archive）：跳過那張並警告，其他照比
reset; card x 'bin/x.sh'
got="$(python3 -I "$OPSX_ROOT/bin/lib/mergematch.py" pick "$E" "bin/x.sh 錯" "" gone x 2> "$ERR")"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_eq "$got" x "消失的候選要跳過"; assert_grep 'gone' "$ERR"

# --- 鎖內重查目標：判斷後、寫入前目標進了 apply 或被拆，就不寫（review R1.3）---
append() { python3 -I "$OPSX_ROOT/bin/lib/inboxmerge.py" append "$C/x" agent-20261111-1040 2026-11-11T10:40:00+08:00 agent:foo planned "" bug "bin/x.sh 晚到" 2> "$ERR"; }
reset; card x 'bin/x.sh'; printf -- '- [ ] 1.1 a\n' > "$C/x/tasks.md"; keep x
append; assert_eq "$?" 4 "目標有 tasks.md 要退出 4：$(cat "$ERR")"; kept x; assert_grep 'tasks.md' "$ERR"
reset; card x 'bin/x.sh' "split_into: [x-a, x-b]"; keep x
append; assert_eq "$?" 4 "目標已拆要退出 4：$(cat "$ERR")"; kept x; assert_grep 'split_into' "$ERR"
reset; card x 'bin/x.sh'
append > /dev/null; assert_eq "$?" 0 "還沒開工的照寫：$(cat "$ERR")"; assert_grep '^bin/x.sh 晚到$' "$C/x/inbox.md"
# opsx new 整條路（review R2.1）：先握住 x 的卡鎖，opsx new 判斷完、卡在寫入前；這時 x 開工或被拆，放鎖後 opsx new 要建新殼、x 不動
hold_x() { # hold_x：背景持 x 的卡鎖，等 $FX/go 出現才放
  rm -f "$FX/held" "$FX/go"
  python3 -I -c '
import os, sys, time
sys.path.insert(0, sys.argv[1]); import safefile
with safefile.CardLock(sys.argv[2]):
    open(sys.argv[3], "w").close()
    while not os.path.exists(sys.argv[4]):
        time.sleep(0.02)
' "$OPSX_ROOT/bin/lib" "$C/x" "$FX/held" "$FX/go" &
  HOLDER=$!
  for _ in $(seq 100); do [ -e "$FX/held" ] && break; sleep 0.05; done
  [ -e "$FX/held" ] || fail "拿不到 x 的卡鎖"
}
late_new() { # late_new <在鎖內對 x 做的事>：opsx new 等鎖時做那件事，再放鎖
  hold_x
  agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 晚到" &
  NEW=$!
  sleep 1
  eval "$1"; keep x
  : > "$FX/go"; wait "$HOLDER"; wait "$NEW"; assert_eq "$?" 0 "目標開工後 opsx new 要照常建殼：$(cat "$ERR")"
  new_shell_out agent; kept x; assert_grep 'inboxmerge' "$ERR"
}
reset; card x 'bin/x.sh'
late_new "printf -- '- [ ] 1.1 a\n' > '$C/x/tasks.md'"
reset; card x 'bin/x.sh'
late_new "sed -i '' 's/^kind_of_work: planned\$/kind_of_work: planned\nsplit_into: [x-a]/' '$C/x/inbox.md'"
assert_grep '^split_into: \[x-a\]$' "$C/x/inbox.md"

# --- 兩邊都有紀錄 ---
reset; card x 'bin/x.sh'; card foo '沒路徑'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 記兩邊"; assert_eq "$(cat "$OUT")" x
case "$(tail -1 "$C/x/decisions.tsv")" in *"併入 agent-20261111-1040：bin/x.sh 記兩邊"*) ;; *) fail "x/decisions.tsv 最後一列要含併入：$(cat "$C/x/decisions.tsv")" ;; esac
case "$(tail -1 "$C/foo/decisions.tsv")" in *"併進 x（id agent-20261111-1040）"*) ;; *) fail "foo/decisions.tsv 最後一列要含併進 x：$(cat "$C/foo/decisions.tsv" 2>&1)" ;; esac
# 自己的卡不存在時只記目標那邊、不報錯
reset; card x 'bin/x.sh'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 沒有自己的卡"; assert_eq "$?" 0 "$(cat "$ERR")"
assert_file "$C/x/decisions.tsv"; assert_no_file "$C/foo"

# --- 在 herdr 裡發通知 ---
reset; card x 'bin/x.sh'
(export HERDR_ENV=w1; cd "$W" && opsx new --kind-of-work planned --repo "$E" -- "bin/x.sh 要通知") > "$OUT" 2> "$ERR"
assert_eq "$(cat "$OUT")" x "$(cat "$ERR")"
assert_grep '^notification show \[e/x\] 併入 --body bin/x.sh 要通知 併進 x$' "$OPSX_FAKE_LOG"

# --- 不在 herdr 裡不發 ---
reset; card x 'bin/x.sh'
agent_new --kind-of-work planned --repo "$E" -- "bin/x.sh 不通知"
assert_no_file "$OPSX_FAKE_LOG"; assert_grep '^bin/x.sh 不通知$' "$C/x/inbox.md"

# --- 通知失敗不影響併入 ---
reset; card x 'bin/x.sh'; printf 'boom\n' > "$FX/notify-err"
(export HERDR_ENV=w1 OPSX_TEST_NOTIFY_ERR="$FX/notify-err"; cd "$W" && opsx new --kind-of-work planned --repo "$E" -- "bin/x.sh 通知會失敗") > "$OUT" 2> "$ERR"
assert_eq "$?" 0 "通知失敗仍退出 0：$(cat "$ERR")"
assert_eq "$(cat "$OUT")" x; assert_grep '通知' "$ERR"; assert_grep 'boom' "$ERR"

# --- 同時兩個併入不掉段 ---
reset; card x 'bin/x.sh'
(cd "$W" && opsx new --kind-of-work planned --repo "$E" -- "bin/x.sh 並行甲" > "$FX/p1.out" 2> "$FX/p1.err") &
(cd "$W" && opsx new --kind-of-work planned --repo "$E" -- "bin/x.sh 並行乙" > "$FX/p2.out" 2> "$FX/p2.err") &
wait
assert_eq "$(cat "$FX/p1.out" "$FX/p2.out" | tr '\n' ' ')" "x x " "兩個都併進 x：$(cat "$FX/p1.err" "$FX/p2.err")"
assert_eq "$(grep -c '^## 併入：' "$C/x/inbox.md")" 2 "兩段都在"
assert_eq "$(grep '^- id:' "$C/x/inbox.md" | sort -u | wc -l | tr -d ' ')" 2 "兩段 id 不同"
assert_eq "$(dirs)" "x "
echo ok
