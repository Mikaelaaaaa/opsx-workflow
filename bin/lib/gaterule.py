"""一個 gate 要通知人還是停 pane 等別張卡，協調者與 collect 共用；只看 waiting，不讀檔、不跑指令、不通知。
gate 一律由使用者答，協調者從不代答，所以沒有「代答」這種處置。

decide(waiting) 回傳兩種處置之一：
  ("human", reason)        留給人；reason 是理由代碼，文字由呼叫端對照
  ("park", waits_on)       等 waits_on 那張卡合進 main
"""
import re

# 建議或選項裡有這些字，代表要人動手
HUMAN_WORDS = ("你", "使用者", "沙盒外", "自己跑", "本人", "人工", "跑指令", "跑腳本", "錄", "貼路徑")
HUMAN_QUESTION = ("只有你能做", "誰來跑")
MERGE_WORDS = ("合併", "merge")
# explore 寫的拆法確認 gate 的 id
SPLIT_GATE = "split"
# drive 與 Stop hook 卡住時寫的 gate 標題（drive-<站>-<n>、卡在接 /<站> [#<n>]）：建議欄是給人看的提示，不是答案
STUCK_GATE = re.compile(r"drive-[a-z]+-[0-9]+|卡在接 /[a-z]+( #[0-9]+)?")


def decide(w):
    if w["gate_id"] and STUCK_GATE.fullmatch(w["gate_id"]):
        return ("human", "stuck")
    if w.get("needs") == "run":
        return ("human", "run")
    if w["type"] == "等待授權":
        # 合併永遠由人按：action 不一定剛好寫成 merge（mr-merge、external 打合併 API），題目也要看
        if any(k in ((w["action"] or "") + " " + (w.get("question") or "")).lower() for k in MERGE_WORDS):
            return ("human", "merge-grant")
        return ("human", "approval")
    if w["type"] == "終端機等待輸入":
        return ("human", "terminal")
    if w["type"] == "type 不明":
        return ("human", "type")
    if w["gate_id"] == SPLIT_GATE:
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
    return ("human", "decision")
