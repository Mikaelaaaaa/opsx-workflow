#!/usr/bin/env bash
# opsx new 的自動併入：agent 開的範圍外卡遇到同 area、還沒動工的卡就併進那張的 inbox.md，不建殼。
# 驗收：openspec/changes/new-auto-merge/subs/new-merge-into/specs/card-auto-merge/spec.md 每個 Scenario。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes date herdr
export OPSX_FAKE_LOG="$FX/herdr.log"
export OPSX_TEST_NOW="2026-11-11 10:40"
cd "$FX"

E="$(mk_opsx_repo e)"
C="$E/openspec/changes"
printf 'hooks\nboard\n' > "$E/openspec/areas.txt"
mkdir -p "$E/.claude/worktrees"
git -C "$E" worktree add -q -b fix/foo/mikaela "$E/.claude/worktrees/foo" || fail "worktree foo 建不起來"
W="$(cd "$E/.claude/worktrees/foo" && pwd -P)"
OUT="$FX/out"; ERR="$FX/err"

reset() { rm -rf "$C"/* "$OPSX_FAKE_LOG"; }
card() { # card <slug> <area> [frontmatter 行…]：只有 inbox.md 的卡（stage explore）
  local s="$1" d="$C/$1" a="$2"; shift 2
  mkdir -p "$d"; printf 'schema: opsx\n' > "$d/.openspec.yaml"
  { printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-10\nrelated:\nkind_of_work: planned\narea: %s\n' "$a"; printf '%s\n' "$@"; printf -- '---\n\n## 一句話\n\n%s\n\n## 證據\n\n' "$s"; } > "$d/inbox.md"
}
to_propose() { # to_propose <slug>：有 explore.md（待決空）、grill.md、proposal.md，沒有 tasks.md
  printf '## 已知\n\n- a\n\n## 待決\n\n## 不做\n\n- c\n' > "$C/$1/explore.md"
  printf 'D1 a\n' > "$C/$1/grill.md"; printf '## Why\n\na\n' > "$C/$1/proposal.md"
}
agent_new() { (cd "$W" && opsx new "$@") > "$OUT" 2> "$ERR"; }
dirs() { find "$C" -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | LC_ALL=C sort | tr '\n' ' '; }
stage() { (source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; stage_name "$E" "$1"); }

# --- 併進 explore 的卡 ---
reset; card x hooks
agent_new --kind-of-work planned --area hooks --repo "$E" -- 鉤子漏擋; assert_eq "$?" 0 "併入要退出 0：$(cat "$ERR")"
assert_eq "$(cat "$OUT")" x "stdout 是目標 slug"
assert_grep '併進 x（id agent-20261111-1040）' "$ERR"
assert_eq "$(dirs)" "x " "不建殼"
assert_eq "$(find "$E/openspec" -maxdepth 1 -name '.reserve-*' | wc -l | tr -d ' ')" 0 "不留保留目錄"
assert_grep '^## 併入：2026-11-11T10:40:[0-9][0-9]+08:00 agent:foo$' "$C/x/inbox.md"
assert_grep '^- id: agent-20261111-1040$' "$C/x/inbox.md"
assert_grep '^- kind_of_work: planned$' "$C/x/inbox.md"
assert_grep '^- area: hooks$' "$C/x/inbox.md"
assert_not_grep '^- impact:' "$C/x/inbox.md"; assert_not_grep '^- evidence:' "$C/x/inbox.md"
assert_eq "$(tail -1 "$C/x/inbox.md")" 鉤子漏擋 "一句話是併入段最後一行"
assert_eq "$(grep -c '^## 一句話$' "$C/x/inbox.md")" 1 "原本的內容不動"

# --- 併進 propose 的卡 ---
reset; card x hooks; to_propose x
assert_eq "$(stage x)" propose "fixture 要是 propose"
agent_new --kind-of-work planned --area hooks --repo "$E" -- 併進 propose; assert_eq "$(cat "$OUT")" x "$(cat "$ERR")"
assert_eq "$(dirs)" "x "; assert_grep '^併進 propose$' "$C/x/inbox.md"

# --- 多張符合取字母序第一張 ---
reset; card me-20261109-1000 hooks; card agent-20261110-0900 hooks
agent_new --kind-of-work planned --area hooks --repo "$E" -- 取第一張; assert_eq "$(cat "$OUT")" agent-20261110-0900
assert_not_grep '## 併入' "$C/me-20261109-1000/inbox.md"

# --- 同一分鐘兩次併入 ---
reset; card x hooks
agent_new --kind-of-work planned --area hooks --repo "$E" -- 第一次
agent_new --kind-of-work planned --area hooks --repo "$E" -- 第二次
assert_grep '併進 x（id agent-20261111-1040-2）' "$ERR"
assert_eq "$(grep '^- id:' "$C/x/inbox.md" | tr '\n' ' ')" "- id: agent-20261111-1040 - id: agent-20261111-1040-2 "
assert_eq "$(dirs)" "x "

# --- planned 帶 evidence：evidence 跟著進併入段 ---
reset; card x hooks
agent_new --kind-of-work planned --evidence "tests/a.test.sh 紅" --area hooks --repo "$E" -- 有證據
assert_eq "$(cat "$OUT")" x "$(cat "$ERR")"
assert_grep '^- kind_of_work: planned$' "$C/x/inbox.md"
assert_grep '^- evidence: tests/a.test.sh 紅$' "$C/x/inbox.md"
assert_not_grep '^- impact:' "$C/x/inbox.md"

# --- 不併的情況：照樣建殼，別的卡不動 ---
keep() { cp "$C/$1/inbox.md" "$FX/keep.md"; }
kept() { cmp -s "$C/$1/inbox.md" "$FX/keep.md" || fail "$1/inbox.md 不該變：$(cat "$C/$1/inbox.md")"; }
new_shell_out() { # 建了新殼：stdout 以 <前綴> 開頭、殼存在、stderr 沒有「併進」
  case "$(cat "$OUT")" in "$1"-*) ;; *) fail "要建新殼（$1-），stdout：$(cat "$OUT") stderr：$(cat "$ERR")" ;; esac
  assert_file "$C/$(cat "$OUT")/inbox.md"; assert_not_grep '併進' "$ERR"
}
# 不同 area
reset; card y board; keep y
agent_new --kind-of-work planned --area hooks --repo "$E" -- 不同 area; new_shell_out agent; kept y
# 目標已有 tasks.md
reset; card x hooks; to_propose x; printf -- '- [ ] 1.1 a\n' > "$C/x/tasks.md"; keep x
assert_eq "$(stage x)" apply "fixture 要是 apply"
agent_new --kind-of-work planned --area hooks --repo "$E" -- 已有 tasks; new_shell_out agent; kept x
# 目標在 review（tasks 全勾、tests green）
reset; card x hooks; to_propose x; printf -- '- [x] 1.1 a\n' > "$C/x/tasks.md"; printf '{"tests":"green"}\n' > "$C/x/status.json"; keep x
assert_eq "$(stage x)" review "fixture 要是 review"
agent_new --kind-of-work planned --area hooks --repo "$E" -- 在 review; new_shell_out agent; kept x
# 目標在 pr（有 report.md）
reset; card x hooks; to_propose x; printf -- '- [x] 1.1 a\n' > "$C/x/tasks.md"; printf '# r\n' > "$C/x/report.md"; keep x
assert_eq "$(stage x)" pr "fixture 要是 pr"
agent_new --kind-of-work planned --area hooks --repo "$E" -- 在 pr; new_shell_out agent; kept x
# 目標已拆
reset; card x hooks "split_into: [x-a, x-b]"; keep x
assert_eq "$(stage x)" split "fixture 要是 split"
agent_new --kind-of-work planned --area hooks --repo "$E" -- 已拆; new_shell_out agent; kept x
# P0 不併
reset; card x hooks; keep x
agent_new --kind-of-work incident --impact security --evidence e --area hooks --repo "$E" -- P0; new_shell_out agent; kept x
# 使用者開的卡不併
reset; card x hooks; keep x
(cd "$E" && opsx new --area hooks --repo "$E" -- 使用者的) > "$OUT" 2> "$ERR"; new_shell_out me; kept x
# 不併進自己的卡（worktree foo 對到卡 foo）
reset; card foo hooks; to_propose foo; keep foo
agent_new --kind-of-work planned --area hooks --repo "$E" -- 自己的範圍外; new_shell_out agent; kept foo
# 子殼 subagent（branch foo--s）也不併進主殼 foo
reset; card foo hooks; mkdir -p "$C/foo/subs/s"; keep foo
git -C "$E" worktree add -q -b feat/foo--s/mikaela "$E/.claude/worktrees/agent-a1" || fail "子殼 worktree 建不起來"
(cd "$E/.claude/worktrees/agent-a1" && opsx new --kind-of-work planned --area hooks --repo "$E" -- 子殼的範圍外) > "$OUT" 2> "$ERR"
new_shell_out agent; kept foo; assert_grep '^source: agent:foo--s$' "$C/$(cat "$OUT")/inbox.md"
# 帶附件不併
reset; card x hooks; keep x; printf 'png' > "$FX/a.png"
agent_new --kind-of-work planned --area hooks --repo "$E" --attach "$FX/a.png" -- 有附件; new_shell_out agent; kept x
assert_eq "$(cat "$C/$(cat "$OUT")/attachments/a.png")" png
# 一句話長得像段落標題或段內欄位：不併（併進去會切斷那一段、偽造 id）
reset; card x hooks; keep x
agent_new --kind-of-work planned --area hooks --repo "$E" -- "## 鉤子漏擋"; new_shell_out agent; kept x
assert_grep '^## 鉤子漏擋$' "$C/$(cat "$OUT")/inbox.md"
reset; card x hooks; keep x
agent_new --kind-of-work planned --area hooks --repo "$E" -- "- id: x-1"; new_shell_out agent; kept x
reset; card x hooks; keep x
agent_new --kind-of-work planned --area hooks --repo "$E" -- "- area: board"; new_shell_out agent; kept x
# incident 一律不併：目標的等級事後可能掉回 P2（milestone、覆寫、依賴繼承），併進去的 incident 會跟著掉
reset; card x hooks; keep x
agent_new --kind-of-work incident --impact blocks_all_agents --evidence e --area hooks --repo "$E" -- 擋住大家; new_shell_out agent; kept x
reset; card x hooks "priority: P1" "priority_reason: 測試"; keep x
agent_new --kind-of-work incident --impact workaround_exists --evidence e --area hooks --repo "$E" -- 目標是 P1 也不併; new_shell_out agent; kept x

# --- 兩邊都有紀錄 ---
reset; card x hooks; card foo board
agent_new --kind-of-work planned --area hooks --repo "$E" -- 記兩邊; assert_eq "$(cat "$OUT")" x
case "$(tail -1 "$C/x/decisions.tsv")" in *"併入 agent-20261111-1040：記兩邊"*) ;; *) fail "x/decisions.tsv 最後一列要含併入：$(cat "$C/x/decisions.tsv")" ;; esac
case "$(tail -1 "$C/foo/decisions.tsv")" in *"併進 x（id agent-20261111-1040）"*) ;; *) fail "foo/decisions.tsv 最後一列要含併進 x：$(cat "$C/foo/decisions.tsv" 2>&1)" ;; esac
# 自己的卡不存在時只記目標那邊、不報錯（source 是 agent:foo，卡 foo 不在）
reset; card x hooks
agent_new --kind-of-work planned --area hooks --repo "$E" -- 沒有自己的卡; assert_eq "$?" 0 "$(cat "$ERR")"
assert_file "$C/x/decisions.tsv"; assert_no_file "$C/foo"

# --- 在 herdr 裡發通知 ---
reset; card x hooks
(export HERDR_ENV=w1; cd "$W" && opsx new --kind-of-work planned --area hooks --repo "$E" -- 要通知) > "$OUT" 2> "$ERR"
assert_eq "$(cat "$OUT")" x "$(cat "$ERR")"
assert_grep '^notification show \[e/x\] 併入 --body 要通知 併進 x$' "$OPSX_FAKE_LOG"

# --- 不在 herdr 裡不發 ---
reset; card x hooks
agent_new --kind-of-work planned --area hooks --repo "$E" -- 不通知
assert_no_file "$OPSX_FAKE_LOG"; assert_grep '^不通知$' "$C/x/inbox.md"

# --- 通知失敗不影響併入 ---
reset; card x hooks; printf 'boom\n' > "$FX/notify-err"
(export HERDR_ENV=w1 OPSX_TEST_NOTIFY_ERR="$FX/notify-err"; cd "$W" && opsx new --kind-of-work planned --area hooks --repo "$E" -- 通知會失敗) > "$OUT" 2> "$ERR"
assert_eq "$?" 0 "通知失敗仍退出 0：$(cat "$ERR")"
assert_eq "$(cat "$OUT")" x; assert_grep '通知' "$ERR"; assert_grep 'boom' "$ERR"
assert_grep '^通知會失敗$' "$C/x/inbox.md"

# --- 同時兩個併入不掉段 ---
reset; card x hooks
(cd "$W" && opsx new --kind-of-work planned --area hooks --repo "$E" -- 並行甲 > "$FX/p1.out" 2> "$FX/p1.err") &
(cd "$W" && opsx new --kind-of-work planned --area hooks --repo "$E" -- 並行乙 > "$FX/p2.out" 2> "$FX/p2.err") &
wait
assert_eq "$(cat "$FX/p1.out" "$FX/p2.out" | tr '\n' ' ')" "x x " "兩個都併進 x：$(cat "$FX/p1.err" "$FX/p2.err")"
assert_eq "$(grep -c '^## 併入：' "$C/x/inbox.md")" 2 "兩段都在"
assert_eq "$(grep '^- id:' "$C/x/inbox.md" | sort -u | wc -l | tr -d ' ')" 2 "兩段 id 不同"
assert_grep '^並行甲$' "$C/x/inbox.md"; assert_grep '^並行乙$' "$C/x/inbox.md"
assert_eq "$(dirs)" "x "
echo ok
