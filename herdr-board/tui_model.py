"""opsx 看板 TUI 的純函式：把 collect 的 JSON 排成一行一卡、游標、範圍、底列輸入框、各鍵要跑的 argv。畫面在 tui.py，這裡只用 curses 的鍵碼常數。
herdr-board D4 / 5.2，specs/board-plugin「最小 TUI」。
"""
from __future__ import annotations

import curses
import unicodedata

SECTIONS = ("待處理", "進行中", "待指派", "收件匣", "已完成")
MARK = {"待處理": "▲", "進行中": "●", "待指派": "○", "收件匣": "·", "已完成": "—"}
SELECTABLE = ("card", "session")
UNMOUNTED = "沒掛的"   # scopes[] 裡 workspace 為 null 的那一項，跟網頁範圍選單同名


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


def scopes(data: dict) -> list[str | None]:
    """Tab 的輪替清單：None 是全部，接著 collect scopes[] 的 workspace；workspace null 用 UNMOUNTED 代表。"""
    return [None] + [s["workspace"] if s["workspace"] is not None else UNMOUNTED for s in data.get("scopes") or []]


def keep_scope(data: dict, scope: str | None) -> str | None:
    """重拉後目前的 workspace 不在 scopes[] 了就回全部。"""
    return scope if scope in scopes(data) else None


def next_scope(data: dict, scope: str | None) -> str | None:
    order = scopes(data)
    if scope not in order:
        return None
    return order[(order.index(scope) + 1) % len(order)]


def scope_label(scope: str | None) -> str:
    return "全部" if scope is None else scope


def scope_repos(data: dict, scope: str | None) -> list[str] | None:
    """範圍底下的 repo；全部回 None。"""
    if scope is None:
        return None
    ws = None if scope == UNMOUNTED else scope
    return next(s["repos"] for s in data["scopes"] if s["workspace"] == ws)


def top_line(data: dict, scope: str | None) -> str:
    # 待處理數照舊數全部 cards[]：不受範圍篩選，收進 session 的主 change 卡也算
    n_wait = sum(1 for c in data.get("cards") or [] if c.get("section") == "待處理")
    return " opsx  待處理 %d  範圍 %s" % (n_wait, scope_label(scope))


def rows(data: dict, done_open: bool, inbox_open: bool = False, scope: str | None = None) -> list[dict]:
    """[{kind: 'header', section, count} | {kind: 'session', session, key, text} | {kind: 'card', card, key, text}]，
    待處理在最上，收件匣與已完成預設收起。收進 session 的主 change 卡不單獨一行。scope 不是全部時只留範圍內 repo 的卡與 session。"""
    repos = scope_repos(data, scope)
    cards = [c for c in data.get("cards") or [] if not c.get("session") and (repos is None or c.get("repo") in repos)]
    sessions = [s for s in data.get("sessions") or [] if repos is None or s["repo"] in repos]
    opened = {"收件匣": inbox_open, "已完成": done_open}
    out: list[dict] = []
    for section in SECTIONS:
        group = [c for c in cards if c.get("section") == section]
        sgroup = [s for s in sessions if s["section"] == section]
        collapsed = not opened.get(section, True)
        orphans = len(data.get("orphans") or []) if section == "進行中" else 0   # 沒對上卡的 opsx pane，在網頁上關
        out.append({"kind": "header", "section": section, "count": len(group) + len(sgroup), "collapsed": collapsed, "orphans": orphans})
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


ZOOM_ARGV = ["herdr", "pane", "zoom", "--current", "--toggle"]


def outcome(argv: list[str], proc, ok: str) -> str:
    """外部指令跑完要寫在底列的一行：成功寫 ok，失敗寫 argv 與 stderr 前 80 字。"""
    return ok if proc.returncode == 0 else "%s 失敗：%s" % (" ".join(argv), proc.stderr.strip()[:80])


def open_argv(root: str, row: dict | None) -> list[str] | None:
    """`o`：卡列開那張卡，session 列開目前那站的主 change；session 已全部合併或游標不在卡上時回 None。"""
    if row is None:
        return None
    if row["kind"] == "card":
        key = "%s/%s" % (row["card"]["repo"], row["card"]["slug"])
    elif row["kind"] == "session" and row["session"]["current"] is not None:
        key = "%s/%s" % (row["session"]["repo"], row["session"]["current"]["slug"])
    else:
        return None
    return ["bash", "%s/herdr-board/scripts/open-board.sh" % root, key]


def new_argv(root: str, data: dict, scope: str | None, text: str) -> list[str]:
    """`+` 送出：範圍內只有一個 repo 就建在那裡，否則不帶 --repo，卡進待分類。"""
    repos = scope_repos(data, scope)
    where = ["--repo", data["repo_paths"][repos[0]]] if repos is not None and len(repos) == 1 else []
    return ["bash", "%s/bin/opsx" % root, "new", *where, "--", text]


class LineInput:
    """底列單行輸入。feed 吃 get_wch() 的回傳：字串字元或整數鍵碼。
    回 ('submit', 去頭尾空白的文字)、('cancel',)（Esc，或空白時按 Enter），其他回 None。"""

    ENTER = ("\n", "\r", curses.KEY_ENTER)
    BACKSPACE = ("\x7f", "\x08", curses.KEY_BACKSPACE)
    ESC = "\x1b"

    def __init__(self):
        self.text = ""

    def feed(self, key: str | int) -> tuple | None:
        if key in self.ENTER:
            text = self.text.strip()
            return ("submit", text) if text else ("cancel",)
        if key == self.ESC:
            return ("cancel",)
        if key in self.BACKSPACE:
            self.text = self.text[:-1]
        elif isinstance(key, str) and key.isprintable():
            self.text += key
        return None


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
