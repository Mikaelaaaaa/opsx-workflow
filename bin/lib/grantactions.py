"""第二級授權動作的合法 action 值：gates.md 的 `action:` 與 grants 的 key 只准這八個。

hooks/opsx-grant-gate.sh 的每個 `level2 <動作>` 呼叫是 bash 字面量，不讀這份；
tests/grant-action.test.sh 比對兩邊的集合一致。
"""
from __future__ import annotations

ACTIONS = ("push", "mr", "migrate", "delete", "install", "rebase", "external", "env")
