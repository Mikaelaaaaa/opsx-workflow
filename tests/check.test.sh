#!/usr/bin/env bash
# opsx check <主 change>：子殼齊不齊。Stop hook 有 subs/ 時擋不齊的子殼。
# 驗收：openspec/changes/split-plan/specs/subchange-propose/spec.md「opsx check 檢查子殼」「Stop hook 擋子殼不齊」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"; export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo r)"; cd "$R"; git branch main   # check_blast 拿 main...HEAD 當 diff 基準
# 主殼 <m>，子殼 subs/a 齊全：四個檔、spec 有 Scenario、task 兩行、D-id 對得到、parent 對
mk_main() { # <m>
  local m="$R/openspec/changes/$1" s="$R/openspec/changes/$1/subs/a"
  mkdir -p "$s/specs/cap"
  printf 'schema: opsx\nkind: dev\n' > "$m/.openspec.yaml"
  printf '## Decisions\n\n- D1 x\n- D2 y\n' > "$m/design.md"
  printf 'schema: opsx\nkind: dev\nparent: %s\n' "$1" > "$s/.openspec.yaml"
  printf '## Why\n\nx\n' > "$s/proposal.md"
  printf '## Decisions\n\n引用主殼 D1、D2。\n' > "$s/design.md"
  printf '## ADDED Requirements\n\n### Requirement: R1\nx SHALL y\n\n#### Scenario: s1\n- **WHEN** a\n- **THEN** b\n\n### Requirement: R2\nz\n\n#### Scenario: s2\n- **WHEN** a\n- **THEN** b\n' > "$s/specs/cap/spec.md"
  printf '## 1. x\n\n- [ ] 1.1 a\n  - 驗收：s1\n  - 測試：tests/a.test.sh\n- [x] 1.2 b\n  - 驗收：s2\n  - 測試：無 · 文件\n' > "$s/tasks.md"
  printf '%s' "$s"
}
chk() { opsx check "$1" 2>&1; }

# --- Scenario：完整子殼通過 ---
mk_main ok >/dev/null
out="$(chk ok)" || fail "完整子殼要回 0: $out"
mkdir -p "$R/openspec/changes/plain"; printf 'schema: opsx\n' > "$R/openspec/changes/plain/.openspec.yaml"
out="$(chk plain)" || fail "沒有 subs/ 回 0: $out"
assert_rc 2 opsx check nope
assert_rc 2 opsx check

# --- Scenario：缺 specs ---
S="$(mk_main nospec)"; rm -r "$S/specs"
out="$(chk nospec)" && fail "缺 specs 要非零"
printf '%s' "$out" | grep -q 'subs/a/specs: ' || fail "要指出 subs/a/specs: $out"

# --- 缺 proposal / design / tasks 各一行 ---
S="$(mk_main nofiles)"; rm "$S/proposal.md" "$S/tasks.md"
out="$(chk nofiles)" && fail "缺檔要非零"
printf '%s' "$out" | grep -q 'subs/a/proposal.md: ' || fail "缺 proposal: $out"
printf '%s' "$out" | grep -q 'subs/a/tasks.md: ' || fail "缺 tasks: $out"
! printf '%s' "$out" | grep -q 'subs/a/design.md' || fail "design 在，不該報: $out"

# --- Scenario：task 缺測試行 ---
S="$(mk_main notest)"; printf '## 1. x\n\n- [ ] 1.1 a\n  - 驗收：s1\n  - 測試：tests/a.test.sh\n- [ ] 1.2 b\n  - 驗收：s2\n- [ ] 1.3 c\n  - 測試：tests/c.test.sh\n' > "$S/tasks.md"
out="$(chk notest)" && fail "task 缺測試行要非零"
printf '%s' "$out" | grep 'subs/a/tasks.md: ' | grep '1.2' | grep -q '測試' || fail "要指出 1.2 缺 測試：$out"
printf '%s' "$out" | grep 'subs/a/tasks.md: ' | grep '1.3' | grep -q '驗收' || fail "要指出 1.3 缺 驗收：$out"
! printf '%s' "$out" | grep -q '1\.1' || fail "1.1 齊全不該報: $out"

# --- Scenario：Requirement 沒有 Scenario ---
S="$(mk_main noscen)"; printf '## ADDED Requirements\n\n### Requirement: R1\nx\n\n#### Scenario: s1\n- a\n\n### Requirement: Lonely\ny\n' > "$S/specs/cap/spec.md"
out="$(chk noscen)" && fail "Requirement 沒有 Scenario 要非零"
printf '%s' "$out" | grep 'subs/a/specs/cap/spec.md: ' | grep -q 'Lonely' || fail "要指出 Lonely: $out"
! printf '%s' "$out" | grep -q 'R1' || fail "R1 有 Scenario 不該報: $out"

# --- Scenario：D-id 對不到 ---
S="$(mk_main badd)"; printf '引用主殼 D1、D12，還有 ADD12 不是 D-id。\n' > "$S/design.md"
out="$(chk badd)" && fail "D-id 對不到要非零"
printf '%s' "$out" | grep 'subs/a/design.md: ' | grep -q 'D12' || fail "要指出 D12: $out"
assert_eq "$(printf '%s\n' "$out" | grep -c 'design.md')" 1 "只報 D12 一行（D1 對得到、ADD12 不算）: $out"

# --- Scenario：parent 不符 ---
S="$(mk_main badparent)"; printf 'schema: opsx\nparent: q\n' > "$S/.openspec.yaml"
out="$(chk badparent)" && fail "parent 不符要非零"
printf '%s' "$out" | grep 'subs/a/.openspec.yaml: ' | grep -q 'parent' || fail "要指出 parent: $out"

# --- Scenario：Stop hook 擋子殼不齊 ---
S="$(mk_main stopper)"; rm "$S/tasks.md"
git -C "$R" checkout -q -b feat/stopper/mikaela
printf '## 1. x\n\n- [ ] 1.1 a\n' > "$R/openspec/changes/stopper/tasks.md"
out="$(printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>"$FX/stop.err")"
assert_eq "$(printf '%s' "$out" | jq -r '.decision // ""')" block "stop: 子殼不齊要擋（stderr: $(cat "$FX/stop.err")）"
printf '%s' "$out" | jq -r '.reason' | grep -q 'subs/a/tasks.md' || fail "stop: 理由要含缺項: $out"
mk_main stopper >/dev/null   # 補齊後回到原本的判斷（tasks 沒勾）
out="$(printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null)"
printf '%s' "$out" | jq -r '.reason' | grep -q 'task 沒勾' || fail "stop: 子殼齊了就照舊擋未勾: $out"

# --- explore.md 步驟紀錄（驗收：openspec/changes/node-steps-wired/specs/node-step-wiring/spec.md） ---
STEP_NAMES=("讀卡" "how" "影響範圍" "why" "prototype" "查資料" "對照 code" "待決" "unslop")
mk_explore() { # <slug> [<步驟號> <內容>]...：九步預設都填「已知」，後面成對參數覆寫某一步（內容空字串表示該行留白，內容 x 表示整行拿掉）
  local c="$R/openspec/changes/$1" i val; shift
  mkdir -p "$c"; printf 'schema: opsx\ncreated: 2026-11-12\nkind: bug-fix\n' > "$c/.openspec.yaml"
  { printf '## 已知\n\n- x\n\n## 待決\n\n- \n\n## 不做\n\n- \n\n## 步驟\n\n'
    for i in 1 2 3 4 5 6 7 8 9; do
      val="已知"; set -- "${@}"
      local rest=("$@"); while [ ${#rest[@]} -ge 2 ]; do [ "${rest[0]}" = "$i" ] && val="${rest[1]}"; rest=("${rest[@]:2}"); done
      [ "$val" = x ] && continue
      printf -- '- %s %s：%s\n' "$i" "${STEP_NAMES[$((i-1))]}" "$val"
    done; } > "$c/explore.md"
}
mk_explore steps-ok 3 "skip：沒有符號被別處引用"
out="$(chk steps-ok)" || fail "九步齊全（含有原因的 skip）要回 0: $out"

mk_explore steps-gap 3 x
out="$(chk steps-gap)" && fail "缺一步要非零"
printf '%s' "$out" | grep -q '3 影響範圍' || fail "要指出缺的是 3 影響範圍: $out"

mk_explore steps-noreason 4 "skip："
out="$(chk steps-noreason)" && fail "skip 沒原因要非零"
printf '%s' "$out" | grep -q '4 why' || fail "要指出 4 why: $out"

mk_explore steps-blank 2 ""
out="$(chk steps-blank)" && fail "該行留白要非零"
printf '%s' "$out" | grep -q '2 how' || fail "要指出 2 how: $out"

mkdir -p "$R/openspec/changes/steps-none"; printf 'schema: opsx\ncreated: 2026-11-12\n' > "$R/openspec/changes/steps-none/.openspec.yaml"
printf '## 已知\n\n- x\n\n## 待決\n\n無\n' > "$R/openspec/changes/steps-none/explore.md"
out="$(chk steps-none)" && fail "沒有 ## 步驟 段要非零"
printf '%s' "$out" | grep -q '1 讀卡' || fail "沒有步驟段要列出全部步驟: $out"

# 舊卡與沒有 created: 的卡不查步驟（日期門檻跟 stage 一樣）
printf 'schema: opsx\ncreated: 2026-11-05\n' > "$R/openspec/changes/steps-none/.openspec.yaml"
out="$(chk steps-none)" || fail "舊卡沒有 ## 步驟 要回 0: $out"
printf 'schema: opsx\n' > "$R/openspec/changes/steps-none/.openspec.yaml"
out="$(chk steps-none)" || fail "沒有 created: 的卡沒有 ## 步驟 要回 0: $out"

# --- 影響範圍寫 skip 時，對 diff 的檔案 grep 別處引用，印 Must-fix 候選（驗收：node-steps-gates/specs/node-step-gates/spec.md「skip 影響範圍對照 diff」） ---
B="$(mk_repo blast)"; git -C "$B" branch -M main
printf 'echo lib\n' > "$B/lib.sh"; printf 'echo alone\n' > "$B/alone.sh"; printf 'source lib.sh\n' > "$B/user.sh"
git -C "$B" add . && git -C "$B" commit -qm base
git -C "$B" checkout -q -b feat/blast/mikaela
mkdir -p "$B/openspec/changes/blast"; printf 'schema: opsx\nkind: bug-fix\n' > "$B/openspec/changes/blast/.openspec.yaml"
mk_blast() { # <步驟 3 的內容>：九步齊全，只有步驟 3 變
  { printf '## 步驟\n\n'
    for i in 1 2 3 4 5 6 7 8 9; do
      val="已知"; [ "$i" = 3 ] && val="$1"
      printf -- '- %s %s：%s\n' "$i" "${STEP_NAMES[$((i-1))]}" "$val"
    done; } > "$B/openspec/changes/blast/explore.md"
}
mk_blast "skip：沒有符號被別處引用"
printf 'echo lib2\n' > "$B/lib.sh"; printf 'echo alone2\n' > "$B/alone.sh"
git -C "$B" commit -qam change
out="$(cd "$B" && opsx check blast 2>&1)" || fail "只有 Must-fix 候選時退出碼要 0（propose 與 review 讀退出碼）: $out"
printf '%s' "$out" | grep -q 'Must-fix 候選' || fail "要印 Must-fix 候選: $out"
printf '%s' "$out" | grep -q 'lib.sh.*user.sh' || fail "候選要點名被引用的檔與引用處: $out"
printf '%s' "$out" | grep -q 'alone.sh' && fail "沒被別處引用的 alone.sh 不該列: $out"
mk_blast "已知：沒有別的引用"
out="$(cd "$B" && opsx check blast 2>&1)" || fail "步驟 3 不是 skip 不跑對照: $out"

# --- Scenario：agent 開的卡要有事實欄位（board-actions「agent 開的卡要帶事實欄位」）---
mk_inbox() { # <slug> <frontmatter 內容>；source 寫在內容裡
  mkdir -p "$R/openspec/changes/$1"; printf 'schema: opsx\n' > "$R/openspec/changes/$1/.openspec.yaml"
  printf -- '---\n%s\n---\n\n## 一句話\n\nx\n' "$2" > "$R/openspec/changes/$1/inbox.md"
}
NL=$'\n'
mk_inbox f-nokind 'source: agent:p'
out="$(chk f-nokind)" && fail "agent 卡沒有 kind_of_work 要非零"
printf '%s' "$out" | grep 'inbox.md: ' | grep -q 'kind_of_work' || fail "要指出 kind_of_work: $out"
mk_inbox f-badkind "source: agent:p${NL}kind_of_work: urgent"
out="$(chk f-badkind)" && fail "kind_of_work 值域外要非零"
printf '%s' "$out" | grep -q 'urgent' || fail "要指出值 urgent: $out"
mk_inbox f-inc "source: agent:p${NL}kind_of_work: incident"
out="$(chk f-inc)" && fail "incident 缺 impact 與 evidence 要非零"
printf '%s' "$out" | grep -q 'impact' || fail "要指出 impact: $out"
printf '%s' "$out" | grep -q 'evidence' || fail "要指出 evidence: $out"
mk_inbox f-inc2 "source: agent:p${NL}kind_of_work: incident${NL}impact: data"
out="$(chk f-inc2)" && fail "incident 缺 evidence 要非零"
printf '%s' "$out" | grep -q 'evidence' || fail "要指出 evidence: $out"
mk_inbox f-okinc "source: agent:p${NL}kind_of_work: incident${NL}impact: data${NL}evidence: tests/x.test.sh"
out="$(chk f-okinc)" || fail "incident 事實齊要通過: $out"
mk_inbox f-nested "source: agent:p${NL}kind_of_work: incident${NL}impact:${NL}  workaround_exists: true${NL}  evidence: \"log 在 ## 證據\""
out="$(chk f-nested)" || fail "巢狀寫法的 impact 與 evidence 要通過: $out"
mk_inbox f-planned "source: agent:p${NL}kind_of_work: planned"
out="$(chk f-planned)" || fail "planned 不需要 evidence: $out"
mk_inbox f-me 'source: me'
out="$(chk f-me)" || fail "使用者開的卡不強制: $out"
mk_inbox f-gitlab 'source: gitlab:a#1'
out="$(chk f-gitlab)" || fail "同步來的卡不強制: $out"
# 這張卡開出去的卡（source: agent:<這張卡>）也要齊
mk_inbox f-parent 'source: me'; mk_inbox f-child 'source: agent:f-parent'
out="$(chk f-parent)" && fail "它開的卡缺 kind 要非零"
printf '%s' "$out" | grep -q 'f-child/inbox.md: ' || fail "要指出 f-child/inbox.md: $out"
mk_inbox f-child "source: agent:f-parent${NL}kind_of_work: planned"
out="$(chk f-parent)" || fail "它開的卡補齊就通過: $out"

# --- Scenario：Stop hook 擋事實欄位不齊 ---
mk_inbox f-stop 'source: agent:q'; printf '## 1. x\n\n- [ ] 1.1 a\n' > "$R/openspec/changes/f-stop/tasks.md"
git -C "$R" checkout -q -b feat/f-stop/mikaela
out="$(printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null)"
assert_eq "$(printf '%s' "$out" | jq -r '.decision // ""')" block "stop: 事實欄位缺要擋"
printf '%s' "$out" | jq -r '.reason' | grep -q 'kind_of_work' || fail "stop: 理由要含缺的欄位: $out"
mk_inbox f-stop "source: agent:q${NL}kind_of_work: planned"
out="$(printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null)"
printf '%s' "$out" | jq -r '.reason' | grep -q 'task 沒勾' || fail "stop: 事實欄位齊了就照舊判斷: $out"

# --- review 退回的邊界 ---
# 模板原樣的 incident：impact 與 evidence 還是 <!-- … -->
mk_inbox f-ph "source: agent:p${NL}kind_of_work: incident${NL}impact: <!-- incident 才填 -->${NL}evidence: <!-- 有 impact 就要 evidence -->"
out="$(chk f-ph)" && fail "模板佔位字不能算有填"
printf '%s' "$out" | grep -q 'incident 缺 impact' || fail "佔位的 impact 要報缺: $out"
printf '%s' "$out" | grep -q 'incident 缺 evidence' || fail "佔位的 evidence 要報缺: $out"
# 尾端空白、CRLF：開出去的卡仍被掃到
mk_inbox f-ws 'source: me'; mk_inbox f-ws-child "source: agent:f-ws "
out="$(chk f-ws)" && fail "source 尾端空白的卡缺 kind 要非零"
printf '%s' "$out" | grep -q 'f-ws-child/inbox.md: ' || fail "尾端空白: $out"
mk_inbox f-cr 'source: me'; mkdir -p "$R/openspec/changes/f-cr-child"
printf -- '---\r\nsource: agent:f-cr\r\n---\r\n\r\n## 一句話\r\n\r\nx\r\n' > "$R/openspec/changes/f-cr-child/inbox.md"
out="$(chk f-cr)" && fail "CRLF 的卡缺 kind 要非零"
printf '%s' "$out" | grep -q 'f-cr-child/inbox.md: ' || fail "CRLF: $out"
printf -- '---\r\nsource: agent:f-cr\r\nkind_of_work: planned\r\n---\r\n' > "$R/openspec/changes/f-cr-child/inbox.md"
out="$(chk f-cr)" || fail "CRLF 補齊要通過: $out"

stop() { printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; }
# 它開出去的卡缺 kind：Stop 擋，理由含那張卡
mk_inbox f-sp 'source: me'; printf '## 1. x\n\n- [ ] 1.1 a\n' > "$R/openspec/changes/f-sp/tasks.md"; mk_inbox f-sp-child 'source: agent:f-sp'
git -C "$R" checkout -q -b feat/f-sp/mikaela
out="$(stop)"; assert_eq "$(printf '%s' "$out" | jq -r '.decision // ""')" block "stop: 開出去的卡缺欄位要擋"
printf '%s' "$out" | jq -r '.reason' | grep -q 'f-sp-child/inbox.md' || fail "stop: 理由要含子卡: $out"
# 等待中不擋：有會擋的 open gate、或 review 的 subagent 還在跑
mk_inbox f-wait 'source: agent:q'; printf '## 1. x\n\n- [ ] 1.1 a\n' > "$R/openspec/changes/f-wait/tasks.md"
git -C "$R" checkout -q -b feat/f-wait/mikaela
printf '## g1\ntype: decision\nstatus: open\n' > "$R/openspec/changes/f-wait/gates.md"
assert_eq "$(stop)" "" "stop: 有 open gate 時事實欄位不擋"
rm "$R/openspec/changes/f-wait/gates.md"
printf '## 1. x\n\n- [x] 1.1 a\n' > "$R/openspec/changes/f-wait/tasks.md"   # review 在跑時 task 都已勾
printf '{"phase":"review","step":2,"total":7,"tests":"green"}' > "$R/openspec/changes/f-wait/status.json"
assert_eq "$(stop)" "" "stop: review 在跑時事實欄位不擋"
rm "$R/openspec/changes/f-wait/status.json"
# 擋滿 3 次：自動 gate 標題是 /facts，文字說的是事實欄位
mk_inbox f-loop 'source: agent:q'; printf '## 1. x\n\n- [ ] 1.1 a\n' > "$R/openspec/changes/f-loop/tasks.md"
git -C "$R" checkout -q -b feat/f-loop/mikaela
stop >/dev/null; stop >/dev/null; stop >/dev/null; stop >/dev/null
assert_grep '^## 卡在接 /facts #1$' "$R/openspec/changes/f-loop/gates.md"
assert_grep '^問題: .*事實欄位' "$R/openspec/changes/f-loop/gates.md"
assert_not_grep '沒有 invoke' "$R/openspec/changes/f-loop/gates.md"

# --- review 第 2 輪退回 ---
# 主殼掃得到子殼 subagent 開的卡（source: agent:<主>--<子>）
mk_inbox f-m 'source: me'; mk_inbox f-m-child 'source: agent:f-m--s'
out="$(chk f-m)" && fail "子殼 subagent 開的卡缺 kind 要非零"
printf '%s' "$out" | grep -q 'f-m-child/inbox.md: ' || fail "要指出子殼開的卡: $out"
# 子殼的 subagent 在跑：事實欄位不擋（只在 subagent 條件被拿掉時才會紅）
mk_main f-sub >/dev/null; mk_inbox f-sub 'source: agent:q'   # mk_inbox 重寫 .openspec.yaml，子殼仍齊全
printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/f-sub/.openspec.yaml"
printf '## 1. x\n\n- [ ] 1.1 `a`：子殼\n' > "$R/openspec/changes/f-sub/tasks.md"
printf '{"phase":"apply","step":1,"total":3,"worker":"subagent-a","at":"%s"}' "$(date -u '+%Y-%m-%dT%H:%M:%S+00:00')" > "$R/openspec/changes/f-sub/subs/a/status.json"
git -C "$R" checkout -q -b feat/f-sub/mikaela
assert_eq "$(stop)" "" "stop: 子殼 subagent 在跑時事實欄位不擋"
# 補一張缺欄位的卡算進度：擋滿 3 次後補一張，仍然 block，不寫 /facts gate
mk_inbox f-prog 'source: me'; printf '## 1. x\n\n- [ ] 1.1 a\n' > "$R/openspec/changes/f-prog/tasks.md"
mk_inbox f-prog-1 'source: agent:f-prog'; mk_inbox f-prog-2 'source: agent:f-prog'; mk_inbox f-prog-3 'source: agent:f-prog'
git -C "$R" checkout -q -b feat/f-prog/mikaela
stop >/dev/null; stop >/dev/null; stop >/dev/null
mk_inbox f-prog-1 "source: agent:f-prog${NL}kind_of_work: planned"
out="$(stop)"; assert_eq "$(printf '%s' "$out" | jq -r '.decision // ""')" block "stop: 補了一張就是進度，不開 gate"
assert_no_file "$R/openspec/changes/f-prog/gates.md"
printf '%s' "$out" | jq -r '.reason' | grep -q 'gates.md' || fail "stop: 理由要提可以寫 gates.md: $out"
echo ok
