#!/usr/bin/env bash
# 一個 gate 留給人還是停 pane 的純函式：十一條規則由上往下取第一個符合的，從不回代答。
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
# 原本會代答的 gate 都留給人（Scenario Outline，正例）
assert_eq "$(decide '{"type": "等待授權", "action": "push", "question": "要 push 嗎"}')" "('human', 'approval')" "長期授權清單內的授權題"
assert_eq "$(decide '{"type": "等待授權", "action": "deploy", "question": "要部署嗎"}')" "('human', 'approval')" "清單外的 action"
assert_eq "$(decide '{"type": "等待授權", "action": null, "question": "要做嗎"}')" "('human', 'approval')" "沒寫 action"
assert_eq "$(decide '{"type": "終端機等待輸入", "question": "y/n?"}')" "('human', 'terminal')" "終端機等待輸入"
assert_eq "$(decide '{"type": "type 不明", "recommended": "用 A"}')" "('human', 'type')" "type 不明"
assert_eq "$(decide '{"gate_id": "split", "recommended": "拆兩張"}')" "('human', 'split')" "拆法確認"
assert_eq "$(decide '{"waits_on": "card-x", "recommended": "等 card-x 合併後繼續"}')" "('park', 'card-x')" "waits-on 排在合併類之前"
assert_eq "$(decide '{"recommended": "重試 merge"}')" "('human', 'merge')" "合併類決定題"
assert_eq "$(decide '{"options": ["先合併再說"]}')" "('human', 'merge')" "沒建議時看第一個選項的合併字"
assert_eq "$(decide '{"question": "要不要上真機驗", "recommended": "用 A"}')" "('human', 'decision')" "真機題"
assert_eq "$(decide '{"question": "可以 push 嗎", "recommended": "用 A"}')" "('human', 'decision')" "授權字題"
assert_eq "$(decide '{"question": "0303 刪 skills 時改過的 prompt 要不要留", "recommended": "照現在"}')" "('human', 'decision')" "migration-edited-prompts 重現"
assert_eq "$(decide '{"question": "範圍要不要收窄？", "recommended": "A。收窄"}')" "('human', 'decision')" "orca-allow-scope 重現"
assert_eq "$(decide '{"question": "選哪個", "options": ["B", "C"]}')" "('human', 'decision')" "沒有建議、只有選項"
assert_eq "$(decide '{"question": "選哪個"}')" "('human', 'no-pick')" "沒選項沒建議"
assert_eq "$(decide '{"question": "選哪個", "recommended": "你在 sandbox 外跑"}')" "('human', 'hands')" "建議要人動手"
assert_eq "$(decide '{"question": "這只有你能做", "recommended": "用 A"}')" "('human', 'hands')" "題目說只有你能做"
# 不回代答（反例）：模組裡不再有代答用的固定答覆
assert_eq "$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import gaterule
print(hasattr(gaterule, "VERIFY_ANSWER") or hasattr(gaterule, "GRANT_ANSWER"))')" False "gaterule 不該留代答的固定答覆"
# import 全在檔頂（~/.claude/CLAUDE.md §5）：docstring 之後，第一個非 import 敘述之前
assert_eq "$(python3 -I -c '
import ast, sys
body = ast.parse(open(sys.argv[1], encoding="utf-8").read()).body
if isinstance(body[0], ast.Expr): body = body[1:]
kinds = [isinstance(n, (ast.Import, ast.ImportFrom)) for n in body]
print(kinds.count(True) == kinds[:kinds.index(False)].count(True))' "$OPSX_ROOT/bin/lib/gaterule.py")" True "gaterule.py 的 import 要在檔頂"
echo ok
