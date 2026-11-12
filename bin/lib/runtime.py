"""agent runtime 的 python 版：每個動詞回傳一條 herdr argv，不執行。

執行留給呼叫者，因為 coordinate 的 dry-run 與行為記錄、看板的 timeout 加 killpg 都是執行器的行為。
對象是卡片身分 card="<repo>/<slug>"（feature session 是 "<repo>/@<feature>"，也就是 dispatch.json 的 key），
或 agent="<名>"：不是卡的 agent（協調者），不讀 dispatch.json。dispatch.json 的路徑由呼叫者傳入。
查表規則與 argv 跟 bin/lib/runtime.sh 相同，由 tests/runtime-py.test.sh 用同一張表對照。
開 agent 與送 /exit 要送多條指令，只有 bash 呼叫者，這裡不提供。
"""
import json


class MissingHandle(LookupError):
    """要 pane 或 tab 的動詞，對象在 dispatch.json 查不到它。"""


def _target(card, agent, dispatch):
    """回傳 (對象, agent 名, pane, tab)；查不到的 pane、tab 是空字串。"""
    if (card is None) == (agent is None):
        raise ValueError("runtime: card 與 agent 要剛好給一個，收到 card=%r agent=%r" % (card, agent))
    if agent is not None:
        if not agent:
            raise ValueError("runtime: agent 名是空的")
        return agent, agent, "", ""
    if "/" not in card:
        raise ValueError("runtime: 對象要是卡片身分 <repo>/<slug> 或 agent=<名>，收到：%r" % card)
    if dispatch is None:
        raise ValueError("runtime: %s 是卡片身分，要給 dispatch=<dispatch.json 路徑>" % card)
    try:
        with open(dispatch, encoding="utf-8") as f:
            entries = json.load(f)
    except FileNotFoundError:
        entries = {}
    # 跟 runtime.sh 一樣，null 與空字串都當成沒有
    e = entries.get(card) or {}
    name = e.get("herdr_name") or card.rsplit("/", 1)[1].removeprefix("@")
    return card, name, e.get("pane") or "", e.get("tab") or ""


def _need(who, kind, value):
    if not value:
        raise MissingHandle("runtime: %s 在 dispatch.json 沒有 %s（還沒派出去，或對象是 agent=）" % (who, kind))
    return value


def prompt(text, *, card=None, agent=None, dispatch=None):
    _, name, _, _ = _target(card, agent, dispatch)
    return ["herdr", "agent", "prompt", name, text]


def read(*, card=None, agent=None, dispatch=None, lines=None):
    """不給 lines 讀 pane 原文；給了讀 agent 的文字畫面最後 lines 行。"""
    who, _, pane, _ = _target(card, agent, dispatch)
    pane = _need(who, "pane", pane)
    if lines is None:
        return ["herdr", "pane", "read", pane]
    return ["herdr", "agent", "read", pane, "--lines", str(lines), "--format", "text"]


def get(*, card=None, agent=None, dispatch=None):
    _, name, _, _ = _target(card, agent, dispatch)
    return ["herdr", "agent", "get", name]


def list_agents():
    return ["herdr", "agent", "list"]


def wait(*, card=None, agent=None, dispatch=None, until=None, timeout=None):
    """timeout 是毫秒。"""
    _, name, _, _ = _target(card, agent, dispatch)
    argv = ["herdr", "agent", "wait", name]
    if until is not None:
        argv += ["--until", until]
    if timeout is not None:
        argv += ["--timeout", str(timeout)]
    return argv


def focus(*, card=None, agent=None, dispatch=None):
    _, name, _, _ = _target(card, agent, dispatch)
    return ["herdr", "agent", "focus", name]


def close(mode, *, card=None, agent=None, dispatch=None):
    """mode 是 pane 或 tab。"""
    who, _, pane, tab = _target(card, agent, dispatch)
    if mode == "pane":
        return ["herdr", "pane", "close", _need(who, "pane", pane)]
    if mode == "tab":
        return ["herdr", "tab", "close", _need(who, "tab", tab)]
    raise ValueError("runtime: %s 的關法只有 pane、tab（送 /exit 只有 bash 版），收到：%r" % (who, mode))


def notify(title, body):
    return ["herdr", "notification", "show", title, "--body", body, "--sound", "request"]
