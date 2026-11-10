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
# pane 在 linked worktree 裡，--show-toplevel 會拿到沒有 openspec/ 的路徑；卡目錄不存在要喊出來，不能當成沒有指示
printf '%s' "$note_line" | grep -qF -- '--git-common-dir' || fail "派工指示條沒說 <top> 怎麼算：$note_line"
printf '%s' "$note_line" | grep -qF 'does not exist' || fail "派工指示條沒說卡目錄不存在時回報：$note_line"

# --- Scenario：轉送帶絕對路徑 ---
relay_row="$(section '## Relaying' "$DOC" | grep -F '有新的派工指示')"
[ -n "$relay_row" ] || fail "Relaying 段沒有轉送新派工指示的那一列"
printf '%s' "$relay_row" | grep -qF '<top>/openspec/changes/<slug>/inbox.md' || fail "轉送列沒帶絕對路徑：$relay_row"
printf '%s' "$relay_row" | grep -qF 'not spawned yet' || fail "轉送列沒處理還沒 spawn 的子卡：$relay_row"

# --- Scenario：子 change 讀主卡的派工指示 ---
subs="$(section '## When the main change has subs/' "$APPLY")"
sub_line="$(printf '%s\n' "$subs" | grep -F '## 派工指示')"
[ -n "$sub_line" ] || fail "apply 子 change 段沒提到 ## 派工指示"
printf '%s' "$sub_line" | grep -qF '<top>/openspec/changes/<主>/inbox.md' || fail "子 change 沒指到主殼 inbox.md：$sub_line"
printf '%s' "$sub_line" | grep -qF 'NEEDS-USER <子>' || fail "子 change 的衝突回報不是 NEEDS-USER <子>：$sub_line"

# --- subs-note-relay：開工後才到的指示轉給執行中的子 subagent ---
# 驗收：openspec/changes/subs-note-relay/specs/fan-out-note-brief/spec.md
relay_step="$(printf '%s\n' "$subs" | grep -F '有新的派工指示')"
[ -n "$relay_step" ] || fail "apply 子 change 段沒有處理「有新的派工指示」的那一步"
printf '%s' "$relay_step" | grep -qF 'SendMessage' || fail "轉送步沒寫 SendMessage：$relay_step"
printf '%s' "$relay_step" | grep -qF '<top>/openspec/changes/<主>/inbox.md' || fail "轉送步沒帶主殼絕對路徑：$relay_step"
for k in 'DONE' 'opsx stack' 'new subagent' 'type: decision'; do
  printf '%s' "$relay_step" | grep -qF "$k" || fail "轉送步沒處理已 DONE 的子 change，缺 $k：$relay_step"
done

echo ok
