#!/usr/bin/env bash
# opsx check <主 change>：子殼齊不齊。Stop hook 有 subs/ 時擋不齊的子殼。
# 驗收：openspec/changes/split-plan/specs/subchange-propose/spec.md「opsx check 檢查子殼」「Stop hook 擋子殼不齊」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"; export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo r)"; cd "$R"
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
echo ok
