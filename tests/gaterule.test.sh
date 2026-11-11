#!/usr/bin/env bash
# 代不代答一個 gate 的純函式：十三條規則由上往下取第一個符合的。
# 驗收：specs/gate-rule/spec.md（代不代答由一個純函式判斷）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

decide() { # <waiting 的 JSON，缺的欄位補成決定題的空值> → decide 的結果
  OPSX_W="$1" OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import json, os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import gaterule
w = {"gate_id": "g1", "type": "等待決定", "action": None, "question": "", "recommended": None, "options": [], "waits_on": None}
w.update(json.loads(os.environ["OPSX_W"]))
print(gaterule.decide(w))'
}

assert_eq "$(decide '{"gate_id": "drive-apply-3", "recommended": "用 A"}')" "('human', 'stuck')" "卡住的 gate"
assert_eq "$(decide '{"gate_id": "卡在接 /review #2", "recommended": "用 A"}')" "('human', 'stuck')" "Stop hook 卡住的 gate"
assert_eq "$(decide '{"needs": "run", "recommended": "用 A"}')" "('human', 'run')" "needs run"
assert_eq "$(decide '{"type": "等待授權", "action": "mr-merge", "question": "要合併嗎"}')" "('human', 'merge-grant')" "合併授權"
assert_eq "$(decide '{"type": "等待授權", "action": "external", "question": "打 Merge API"}')" "('human', 'merge-grant')" "題目含合併字，不分大小寫"
assert_eq "$(decide '{"type": "等待授權", "action": "push", "question": "要 push 嗎"}')" "('answer', '允許', True)" "長期授權清單內"
assert_eq "$(decide '{"type": "等待授權", "action": "deploy", "question": "要部署嗎"}')" "('answer', '允許', False)" "清單外的 action 不以授權身分答"
assert_eq "$(decide '{"type": "等待授權", "action": null, "question": "要做嗎"}')" "('answer', '允許', False)" "沒寫 action"
assert_eq "$(decide '{"type": "終端機等待輸入", "question": "y/n?"}')" "('human', 'terminal')" "終端機等待輸入"
assert_eq "$(decide '{"type": "type 不明", "recommended": "用 A"}')" "('human', 'type')" "type 不明"
assert_eq "$(decide '{"gate_id": "split", "recommended": "拆兩張"}')" "('human', 'split')" "拆法確認"
assert_eq "$(decide '{"waits_on": "card-x", "recommended": "等 card-x 合併後繼續"}')" "('park', 'card-x')" "waits-on 排在合併類之前"
assert_eq "$(decide '{"recommended": "重試 merge"}')" "('human', 'merge')" "合併類決定題"
assert_eq "$(decide '{"options": ["先合併再說"]}')" "('human', 'merge')" "沒建議時看第一個選項的合併字"
assert_eq "$(decide '{"question": "要不要上真機驗", "recommended": "用 A"}')" "$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import gaterule
print(("answer", gaterule.VERIFY_ANSWER, False))')" "真機題"
case "$(decide '{"question": "要不要上真機驗"}')" in *等使用者驗*) ;; *) fail "真機題的固定答覆沒有「等使用者驗」";; esac
assert_eq "$(decide '{"question": "可以 push 嗎", "recommended": "用 A"}')" "('answer', '允許。長期授權在 grants.toml，直接做。', False)" "授權題"
assert_eq "$(decide '{"question": "選哪個"}')" "('human', 'no-pick')" "沒選項沒建議"
assert_eq "$(decide '{"question": "選哪個", "recommended": "你在 sandbox 外跑"}')" "('human', 'hands')" "建議要人動手"
assert_eq "$(decide '{"question": "這只有你能做", "recommended": "用 A"}')" "('human', 'hands')" "題目說只有你能做"
assert_eq "$(decide '{"question": "選哪個", "recommended": "用 A"}')" "('answer', '用 A', False)" "代答建議"
assert_eq "$(decide '{"question": "選哪個", "options": ["B", "C"]}')" "('answer', 'B', False)" "沒建議答第一個選項"
echo ok
