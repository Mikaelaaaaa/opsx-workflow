#!/usr/bin/env bash
# references/fan-out.md 與 apply 子 change brief 對派工指示的規定。只證明文件寫了；內容對不對由 review 對照 D1。
# 驗收：openspec/changes/me-20261110-1409/specs/fan-out-note-brief/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
DOC="$OPSX_ROOT/references/fan-out.md"
APPLY="$OPSX_ROOT/skills/apply/SKILL.md"
assert_file "$DOC"
assert_file "$APPLY"

section() { awk -v h="$1" '$0 == h {f=1; next} /^## /{f=0} f' "$2"; }

# --- Scenario：Spawning 要求先讀派工指示 ---
spawn="$(section '## Spawning' "$DOC")"
note_line="$(printf '%s\n' "$spawn" | grep -F '## 派工指示')"
[ -n "$note_line" ] || fail "Spawning 段沒提到 ## 派工指示"
printf '%s' "$note_line" | grep -qF '<top>/openspec/changes/<slug>/inbox.md' || fail "Spawning 的派工指示條沒有絕對路徑：$note_line"

# --- Scenario：衝突回報 NEEDS-USER ---
printf '%s' "$note_line" | grep -qF 'NEEDS-USER' || fail "派工指示條沒寫衝突回報 NEEDS-USER：$note_line"
printf '%s' "$note_line" | grep -qF 'design.md' || fail "派工指示條沒指到 design.md 的 D：$note_line"

# --- Scenario：轉送帶絕對路徑 ---
relay_row="$(section '## Relaying' "$DOC" | grep -F '有新的派工指示')"
[ -n "$relay_row" ] || fail "Relaying 段沒有轉送新派工指示的那一列"
printf '%s' "$relay_row" | grep -qF '<top>/openspec/changes/<slug>/inbox.md' || fail "轉送列沒帶絕對路徑：$relay_row"

# --- Scenario：子 change 讀主卡的派工指示 ---
subs="$(section '## When the main change has subs/' "$APPLY")"
sub_line="$(printf '%s\n' "$subs" | grep -F '## 派工指示')"
[ -n "$sub_line" ] || fail "apply 子 change 段沒提到 ## 派工指示"
printf '%s' "$sub_line" | grep -qF '<top>/openspec/changes/<主>/inbox.md' || fail "子 change 沒指到主殼 inbox.md：$sub_line"

echo ok
