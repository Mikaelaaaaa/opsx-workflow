#!/usr/bin/env bash
# 一個 gate 留給人、停 pane 或照建議答的純函式：十二條規則由上往下取第一個符合的，只有 opsx-workflow 的 decision 回 answer。
# 驗收：specs/gate-rule/spec.md（代不代答由一個純函式判斷）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

decide_in() { # <repo> <waiting 的 JSON，缺的欄位補成決定題的空值> → decide 的結果
  OPSX_REPO="$1" OPSX_W="$2" OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import json, os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import gaterule
w = {"gate_id": "g1", "type": "等待決定", "action": None, "question": "", "recommended": None, "options": [], "waits_on": None}
w.update(json.loads(os.environ["OPSX_W"]))
print(gaterule.decide(w, os.environ["OPSX_REPO"]))'
}
decide() { decide_in other-repo "$1"; }

assert_eq "$(decide '{"gate_id": "drive-apply-3", "recommended": "用 A"}')" "('human', 'stuck')" "卡住的 gate"
assert_eq "$(decide '{"gate_id": "卡在接 /review #2", "recommended": "用 A"}')" "('human', 'stuck')" "Stop hook 卡住的 gate"
assert_eq "$(decide '{"needs": "run", "recommended": "用 A"}')" "('human', 'run')" "needs run"
# 協調者代跑的題（Scenario Outline，正例）：by 排在 type、合併字與 hands 判斷前
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "recommended": "chmod +x hooks/reload.sh"}')" "('coordinator', 'run')" "代跑：決定題"
assert_eq "$(decide '{"type": "等待授權", "action": "push", "needs": "run", "by": "coordinator", "recommended": "cd /x/wt && git push gitlab feat/a/mikaela-lin"}')" "('coordinator', 'run')" "代跑：授權題"
assert_eq "$(decide '{"type": "等待授權", "action": "push", "needs": "run", "by": "coordinator", "recommended": "push 前先 fetch 一次"}')" "('coordinator', 'run')" "代跑：授權題，by 排在授權判斷前"
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "recommended": "你在終端機跑 opsx stop x"}')" "('coordinator', 'run')" "代跑：建議含要人動手的字"
# 只有 by 沒有 needs run 不算代跑；卡住的 gate 標了 by 仍留給人（反例）
assert_eq "$(decide '{"by": "coordinator", "recommended": "用 A"}')" "('human', 'decision')" "只有 by"
assert_eq "$(decide '{"gate_id": "drive-apply-3", "needs": "run", "by": "coordinator", "recommended": "用 A"}')" "('human', 'stuck')" "卡住的 gate 標了 by"
# 合併類、等別張卡、type 不明、split 標了 by 仍照原規則（design D7、D8）
assert_eq "$(decide '{"type": "等待授權", "action": "mr-merge", "needs": "run", "by": "coordinator", "recommended": "glab mr merge 12"}')" "('human', 'run')" "合併 action 標了 by"
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "question": "要 Merge 嗎", "recommended": "glab mr merge 12"}')" "('human', 'run')" "題目含合併字標了 by"
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "question": "CI 綠了，收尾", "recommended": "glab mr merge 42"}')" "('human', 'run')" "建議含合併字標了 by（design D14）"
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "waits_on": "other-card", "recommended": "chmod +x x.sh"}')" "('human', 'run')" "waits-on 標了 by"
assert_eq "$(decide '{"type": "type 不明", "needs": "run", "by": "coordinator", "recommended": "chmod +x x.sh"}')" "('human', 'run')" "type 不明標了 by"
assert_eq "$(decide '{"gate_id": "split", "needs": "run", "by": "coordinator", "recommended": "chmod +x x.sh"}')" "('human', 'run')" "split 標了 by"
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
# opsx repo 的決定題照建議答（Scenario Outline，正例）
assert_eq "$(decide_in opsx-workflow '{"question": "範圍要不要收窄？", "recommended": "A。收窄"}')" "('answer', 'A。收窄')" "opsx 的決定題帶建議"
assert_eq "$(decide_in opsx-workflow '{"gate_id": "split", "recommended": "照這個拆法", "options": ["照這個拆法", "改拆法", "不拆"]}')" "('answer', '照這個拆法')" "opsx 的 split 也照建議答"
# opsx repo 裡留給人的題不變（Scenario Outline，反例）
assert_eq "$(decide_in opsx-workflow '{"gate_id": "drive-apply-3", "recommended": "用 A"}')" "('human', 'stuck')" "opsx 卡住的 gate"
assert_eq "$(decide_in opsx-workflow '{"gate_id": "stale-wait-20261120101500", "recommended": "用 A"}')" "('human', 'stuck')" "opsx 協調者自己的 stale-wait gate"
assert_eq "$(decide_in opsx-workflow '{"question": "選哪個", "options": ["B", "C"]}')" "('human', 'no-pick')" "opsx 沒有建議、只有選項"
assert_eq "$(decide_in opsx-workflow '{"needs": "run", "recommended": "用 A"}')" "('human', 'run')" "opsx needs run"
assert_eq "$(decide_in opsx-workflow '{"type": "等待授權", "action": "push", "question": "要 push 嗎"}')" "('human', 'approval')" "opsx 授權題"
assert_eq "$(decide_in opsx-workflow '{"type": "等待授權", "action": "mr-merge", "question": "要合併嗎"}')" "('human', 'merge-grant')" "opsx 合併授權"
assert_eq "$(decide_in opsx-workflow '{"type": "type 不明", "recommended": "用 A"}')" "('human', 'type')" "opsx type 不明"
assert_eq "$(decide_in opsx-workflow '{"waits_on": "card-x", "recommended": "用 A"}')" "('park', 'card-x')" "opsx waits-on"
assert_eq "$(decide_in opsx-workflow '{"recommended": "重試 merge"}')" "('human', 'merge')" "opsx 合併類決定題"
assert_eq "$(decide_in opsx-workflow '{"question": "選哪個"}')" "('human', 'no-pick')" "opsx 沒選項沒建議"
assert_eq "$(decide_in opsx-workflow '{"question": "選哪個", "recommended": "你在 sandbox 外跑"}')" "('human', 'hands')" "opsx 建議要人動手"
# 其他 repo 的決定題留給人（邊界：名字只是開頭相同）
assert_eq "$(decide_in opsx-workflow-fork '{"question": "選哪個", "recommended": "用 A"}')" "('human', 'decision')" "opsx-workflow-fork 不算"
# import 全在檔頂（~/.claude/CLAUDE.md §5）：docstring 之後，第一個非 import 敘述之前
assert_eq "$(python3 -I -c '
import ast, sys
body = ast.parse(open(sys.argv[1], encoding="utf-8").read()).body
if isinstance(body[0], ast.Expr): body = body[1:]
kinds = [isinstance(n, (ast.Import, ast.ImportFrom)) for n in body]
print(kinds.count(True) == kinds[:kinds.index(False)].count(True))' "$OPSX_ROOT/bin/lib/gaterule.py")" True "gaterule.py 的 import 要在檔頂"
echo ok
