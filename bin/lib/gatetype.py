"""gates.md 的 type 只有 approval（要授權）與 decision（要決定）；舊寫法經 SYNONYMS 對應回來。

用法（bash 內嵌 python）：
    sys.path.insert(0, os.environ["OPSX_LIB"]); import gatetype
    gatetype.normalize(raw)    # "approval" | "decision" | None（沒寫或不在表內）

比對是去前後空白後的整值全等，英文不分大小寫；不做子字串或模糊比對。
hooks/gate-timestamp.sh 的 awk 另存一份同樣的表（awk 不能 import），tests/gatetype.test.sh 比對兩份一致。
"""
from __future__ import annotations

APPROVAL = "approval"
DECISION = "decision"

SYNONYMS = {
    "authorization": APPROVAL,
    "授權": APPROVAL,
    "等待授權": APPROVAL,
    "等待決定": DECISION,
    "決定": DECISION,
}


def normalize(raw: str) -> str | None:
    v = raw.strip().lower()
    if v in (APPROVAL, DECISION):
        return v
    return SYNONYMS.get(v)
