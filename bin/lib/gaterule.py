"""代不代答一個 gate 的判斷，協調者與 collect 共用；只看 waiting，不讀檔、不跑指令、不通知。

decide(waiting) 回傳三種處置之一：
  ("answer", text, grant)  代答 text；grant 為真時以授權身分答
  ("human", reason)        留給人；reason 是理由代碼，文字由呼叫端對照
  ("park", waits_on)       等 waits_on 那張卡合進 main
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grantactions  # noqa: E402

VERIFY_WORDS = ("真機", "實測", "瀏覽器", "herdr 驗", "resume", "真的 claude", "真 herdr", "量測")
GRANT_WORDS = ("授權", "開 PR", "開 / 改 MR", "gh pr create", "push", "推到 origin", "rebase")
# 建議或選項裡有這些字，代表要人動手；不替人承諾
HUMAN_WORDS = ("你", "使用者", "沙盒外", "自己跑", "本人", "人工", "跑指令", "跑腳本", "錄", "貼路徑")
HUMAN_QUESTION = ("只有你能做", "誰來跑")
MERGE_WORDS = ("合併", "merge")
# explore 寫的拆法確認 gate 的 id：要人決定，永遠不代答
SPLIT_GATE = "split"
# drive 與 Stop hook 卡住時寫的 gate 標題（drive-<站>-<n>、卡在接 /<站> [#<n>]）：建議欄是給人看的提示，不是答案，永遠不代答
STUCK_GATE = re.compile(r"drive-[a-z]+-[0-9]+|卡在接 /[a-z]+( #[0-9]+)?")
VERIFY_ANSWER = "這個要真機跑的驗證使用者之後自己做：把它標成「等使用者驗」寫進 report.md 的 Consider，不要再開 gate，繼續做完剩下的 task 到 /opsx-workflow:review、/opsx-workflow:pr。"
GRANT_ANSWER = "允許。長期授權在 grants.toml，直接做。"


def decide(w):
    if w["gate_id"] and STUCK_GATE.fullmatch(w["gate_id"]):
        return ("human", "stuck")
    if w.get("needs") == "run":
        return ("human", "run")
    if w["type"] == "等待授權":
        # 合併永遠由人按：action 不一定剛好寫成 merge（mr-merge、external 打合併 API），題目也要看
        if any(k in ((w["action"] or "") + " " + (w.get("question") or "")).lower() for k in MERGE_WORDS):
            return ("human", "merge-grant")
        return ("answer", "允許", w["action"] in grantactions.ACTIONS)
    if w["type"] == "終端機等待輸入":
        return ("human", "terminal")
    if w["type"] == "type 不明":
        return ("human", "type")
    if w["gate_id"] == SPLIT_GATE:
        return ("human", "split")
    q = w.get("question") or ""
    pick = w.get("recommended") or (w.get("options") or [None])[0]
    # gate 明寫 waits-on 才算等別張卡：答了它查完又會開一個 gate。要排在合併類規則前，不然會被它吃掉
    if w.get("waits_on"):
        return ("park", w["waits_on"])
    # 合併授權綁 head sha，代答「重試合併」這類題就等於替人決定合併
    if any(k in (q + " " + (pick or "")).lower() for k in MERGE_WORDS):
        return ("human", "merge")
    if any(k in q for k in VERIFY_WORDS):
        return ("answer", VERIFY_ANSWER, False)
    if any(k in q for k in GRANT_WORDS):
        return ("answer", GRANT_ANSWER, False)
    if not pick:
        return ("human", "no-pick")
    if any(k in pick for k in HUMAN_WORDS) or any(k in q for k in HUMAN_QUESTION):
        return ("human", "hands")
    return ("answer", pick, False)
