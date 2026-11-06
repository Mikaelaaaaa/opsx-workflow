"""opsx 看板 TUI 的純函式：把 collect 的 JSON 排成一行一卡、游標、Enter 要做什麼。curses 在 tui.py。
herdr-board D4 / 5.2，specs/board-plugin「最小 TUI」。
"""
from __future__ import annotations

import unicodedata

SECTIONS = ("待處理", "進行中", "待指派", "已完成")
MARK = {"待處理": "▲", "進行中": "●", "待指派": "○", "已完成": "—"}


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


def rows(data: dict, done_open: bool) -> list[dict]:
    """[{kind: 'header', section, count} | {kind: 'card', card, key, text}]，待處理在最上，已完成預設收起。"""
    cards = data.get("cards") or []
    out: list[dict] = []
    for section in SECTIONS:
        group = [c for c in cards if c.get("section") == section]
        out.append({"kind": "header", "section": section, "count": len(group), "collapsed": section == "已完成" and not done_open})
        if section == "已完成" and not done_open:
            continue
        for c in group:
            out.append({"kind": "card", "card": c, "key": "%s/%s" % (c.get("repo"), c.get("slug")),
                        "mark": MARK[section], "text": _line(c)})
    return out


def enter(row: dict) -> list[str] | None:
    """Enter：已派出的卡回 herdr pane focus 的 argv；其他回 None（什麼都不做）。"""
    if row.get("kind") != "card":
        return None
    d = row["card"].get("dispatch") or {}
    pane = d.get("pane")
    return ["herdr", "pane", "focus", str(pane)] if pane else None


class Cursor:
    """游標只停在卡上，不越界；重拉資料後用 key 找回同一張卡。"""

    def __init__(self, rows_: list[dict]):
        self.rows = rows_
        self.index: int | None = next((i for i, r in enumerate(rows_) if r["kind"] == "card"), None)

    @property
    def key(self) -> str | None:
        return self.rows[self.index]["key"] if self.index is not None else None

    def move(self, delta: int) -> None:
        if self.index is None:
            return
        cards = [i for i, r in enumerate(self.rows) if r["kind"] == "card"]
        pos = cards.index(self.index)
        self.index = cards[max(0, min(len(cards) - 1, pos + delta))]

    def rebind(self, rows_: list[dict]) -> None:
        key = self.key
        self.rows = rows_
        self.index = next((i for i, r in enumerate(rows_) if r["kind"] == "card" and r["key"] == key), None)
        if self.index is None:
            self.index = next((i for i, r in enumerate(rows_) if r["kind"] == "card"), None)
