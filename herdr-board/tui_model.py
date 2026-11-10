"""opsx 看板 TUI 的純函式：把 collect 的 JSON 排成一行一卡、游標、Enter 要做什麼。curses 在 tui.py。
herdr-board D4 / 5.2，specs/board-plugin「最小 TUI」。
"""
from __future__ import annotations

import unicodedata

SECTIONS = ("待處理", "進行中", "待指派", "收件匣", "已完成")
MARK = {"待處理": "▲", "進行中": "●", "待指派": "○", "收件匣": "·", "已完成": "—"}
SELECTABLE = ("card", "session")


def width(s: str) -> int:
    """終端機欄寬：CJK 與全形算 2，其餘算 1（curses 的 addnstr 數的是字元，CJK 一行會超出視窗）。"""
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in s)


def fit(s: str, cols: int) -> str:
    """截到 cols 欄寬以內，不切到半個全形字。"""
    out, used = [], 0
    for ch in s:
        w = 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
        if used + w > cols:
            break
        out.append(ch); used += w
    return "".join(out)


def _line(card: dict) -> str:
    w = card.get("waiting")
    s = card.get("status")
    if w:
        detail = "%s：%s" % (w.get("type"), w.get("question") or w.get("action") or "")
    elif s:
        detail = "%s %s/%s · %s" % (s.get("phase"), s.get("step"), s.get("total"), s.get("label"))
    else:
        detail = "階段 %s" % card.get("stage", "")
    return "%s  %s  %s  %s" % (card.get("repo", ""), card.get("title") or card.get("slug"), detail, card.get("since") or "")


def _session_line(s: dict) -> str:
    """與網頁 sessionLine 同一格式；目前站沒有 stage 就只寫 slug。"""
    cur = s["current"]
    here = "已合併" if cur is None else " ".join(x for x in (cur["slug"], cur["stage"]) if x)
    return "%s · 主 change %s/%s · 子 change %s/%s · %s" % (
        s["feature"], s["main_done"], s["main_total"], s["sub_done"], s["sub_total"], here)


def rows(data: dict, done_open: bool, inbox_open: bool = False) -> list[dict]:
    """[{kind: 'header', section, count} | {kind: 'session', session, key, text} | {kind: 'card', card, key, text}]，
    待處理在最上，收件匣與已完成預設收起。收進 session 的主 change 卡不單獨一行。"""
    cards = [c for c in data.get("cards") or [] if not c.get("session")]
    sessions = data.get("sessions") or []
    opened = {"收件匣": inbox_open, "已完成": done_open}
    out: list[dict] = []
    for section in SECTIONS:
        group = [c for c in cards if c.get("section") == section]
        sgroup = [s for s in sessions if s["section"] == section]
        collapsed = not opened.get(section, True)
        out.append({"kind": "header", "section": section, "count": len(group) + len(sgroup), "collapsed": collapsed})
        if collapsed:
            continue
        for s in sgroup:
            out.append({"kind": "session", "session": s, "key": "session:%s/%s" % (s["repo"], s["feature"]),
                        "mark": MARK[section], "text": _session_line(s)})
        for c in group:
            out.append({"kind": "card", "card": c, "key": "%s/%s" % (c.get("repo"), c.get("slug")),
                        "mark": MARK[section], "text": _line(c)})
    return out


def enter(row: dict) -> list[str] | None:
    """Enter：已派出的卡回 herdr agent focus 的 argv（agent 名 = slug）；session 行聚焦目前站主 change 的 agent
    （dispatch.json 的 herdr_name，沒有就是主 change slug）；其他回 None（什麼都不做）。"""
    if row.get("kind") == "session":
        s = row["session"]
        if s["current"] is None:
            return None
        m = next(m for m in s["mains"] if m["slug"] == s["current"]["slug"])
        d = m["dispatch"] or {}
        return ["herdr", "agent", "focus", d.get("herdr_name") or m["slug"]] if d.get("pane") else None
    if row.get("kind") != "card":
        return None
    c = row["card"]
    d = c.get("dispatch") or {}
    return ["herdr", "agent", "focus", str(c.get("slug"))] if d.get("pane") else None


class Cursor:
    """游標只停在卡與 session 行上，不越界；重拉資料後用 key 找回同一行。"""

    def __init__(self, rows_: list[dict]):
        self.rows = rows_
        self.index: int | None = next((i for i, r in enumerate(rows_) if r["kind"] in SELECTABLE), None)

    @property
    def key(self) -> str | None:
        return self.rows[self.index]["key"] if self.index is not None else None

    def move(self, delta: int) -> None:
        if self.index is None:
            return
        cards = [i for i, r in enumerate(self.rows) if r["kind"] in SELECTABLE]
        pos = cards.index(self.index)
        self.index = cards[max(0, min(len(cards) - 1, pos + delta))]

    def rebind(self, rows_: list[dict]) -> None:
        key = self.key
        self.rows = rows_
        self.index = next((i for i, r in enumerate(rows_) if r["kind"] in SELECTABLE and r["key"] == key), None)
        if self.index is None:
            self.index = next((i for i, r in enumerate(rows_) if r["kind"] in SELECTABLE), None)
