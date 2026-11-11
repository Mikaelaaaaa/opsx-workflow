#!/usr/bin/env bash
# archive skill：搬進 archive 之前要跑 opsx check，擋下還有 ## 併入 項目沒去處的卡（捨棄路徑也一樣）。
# 驗收：openspec/changes/new-auto-merge/specs/card-auto-merge/spec.md「併入項目要有去處」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/archive/SKILL.md"
sec() { awk -v h="$1" 'index($0,h)==1{on=1;print;next} on && /^#{2,3} /{on=0} on' "$SK"; }

S3="$FX/s3"; sec "### 3. Check task completion status" > "$S3"; [ -s "$S3" ] || fail "archive 少步驟 3"
S5="$FX/s5"; sec "### 5. Perform the archive" > "$S5"; [ -s "$S5" ] || fail "archive 少步驟 5"
grep -qF 'opsx check <name>' "$S5" || fail "步驟 5 搬檔前要跑 opsx check <name>"
grep -qF '## 併入' "$S5" || fail "步驟 5 要說明 opsx check 擋的是沒去處的 ## 併入 項目"
grep -qF 'opsx split-out' "$S5" || fail "步驟 5 要說明擋下時用 opsx split-out"
# 捨棄路徑先寫 outcome: declined，check 才會檢查沒有 tasks.md 的卡
a="$(grep -nF 'outcome: declined' "$S3" | head -1 | cut -d: -f1)"
[ -n "$a" ] || fail "步驟 3 的捨棄路徑要寫 outcome: declined"
echo ok
