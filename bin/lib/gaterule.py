"""一個 gate 要通知人、停 pane 等別張卡、交協調者 session 代跑，還是由協調者照建議答；協調者與 collect 共用。
只看 waiting 與 repo 名，不讀檔、不跑指令、不通知。只有 opsx-workflow repo 的 decision 由協調者照建議答；
approval 與其他 repo 的 gate 都由使用者答。代跑是照建議跑一次指令、把結果貼回，不是替人做決定。

decide(waiting, repo) 回傳四種處置之一：
  ("human", reason)        留給人；reason 是理由代碼，文字由呼叫端對照
  ("park", waits_on)       等 waits_on 那張卡合進 main
  ("coordinator", "run")   needs: run 且 by: coordinator，協調者 session 照建議跑
  ("answer", pick)         協調者照建議答；pick 是建議，沒有建議的題留給人
"""
import re

# 建議或選項裡有這些字，代表要人動手
HUMAN_WORDS = ("你", "使用者", "沙盒外", "自己跑", "本人", "人工", "跑指令", "跑腳本", "錄", "貼路徑")
HUMAN_QUESTION = ("只有你能做", "誰來跑")
MERGE_WORDS = ("合併", "merge")
# explore 寫的拆法確認 gate 的 id
SPLIT_GATE = "split"
# 這個 repo 的 decision 由協調者照建議答
ANSWER_REPO = "opsx-workflow"
# drive、Stop hook 卡住與協調者等背景工作太久時寫的 gate 標題（drive-<站>-<n>、卡在接 /<站> [#<n>]、stale-wait-<時間>）：
# 建議欄是給人看的提示，不是答案
STUCK_GATE = re.compile(r"drive-[a-z]+-[0-9]+|卡在接 /[a-z]+( #[0-9]+)?|stale-wait-[0-9]+")


def decide(w, repo):
    if w["gate_id"] and STUCK_GATE.fullmatch(w["gate_id"]):
        return ("human", "stuck")
    # 排在 type 前：approval 型的 push 題也交協調者，使用者在協調者 pane 按權限提示。
    # 合併類、等別張卡、type 不明、split 不交，往下照原規則
    merge_text = ((w.get("action") or "") + " " + (w.get("question") or "")).lower()
    # 協調者跑的就是建議欄，所以這裡連建議也比
    run_text = merge_text + " " + (w.get("recommended") or "").lower()
    if (w.get("needs") == "run" and w.get("by") == "coordinator" and not w.get("waits_on")
            and w["type"] != "type 不明" and w["gate_id"] != SPLIT_GATE
            and not any(k in run_text for k in MERGE_WORDS)):
        return ("coordinator", "run")
    if w.get("needs") == "run":
        return ("human", "run")
    if w["type"] == "等待授權":
        # 合併永遠由人按：action 不一定剛好寫成 merge（mr-merge、external 打合併 API），題目也要看
        if any(k in merge_text for k in MERGE_WORDS):
            return ("human", "merge-grant")
        return ("human", "approval")
    if w["type"] == "終端機等待輸入":
        return ("human", "terminal")
    if w["type"] == "type 不明":
        return ("human", "type")
    if w["gate_id"] == SPLIT_GATE and repo != ANSWER_REPO:
        return ("human", "split")
    q = w.get("question") or ""
    pick = w.get("recommended") or (w.get("options") or [None])[0]
    # gate 明寫 waits-on 才算等別張卡。要排在合併類規則前，不然會被它吃掉
    if w.get("waits_on"):
        return ("park", w["waits_on"])
    if any(k in (q + " " + (pick or "")).lower() for k in MERGE_WORDS):
        return ("human", "merge")
    if not pick:
        return ("human", "no-pick")
    if any(k in pick for k in HUMAN_WORDS) or any(k in q for k in HUMAN_QUESTION):
        return ("human", "hands")
    if repo == ANSWER_REPO:
        return ("answer", pick) if w.get("recommended") else ("human", "no-pick")
    return ("human", "decision")
