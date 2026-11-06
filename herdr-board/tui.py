#!/usr/bin/env python3
"""opsx 看板的 herdr pane（最小 TUI，herdr-board D4）：同一份 `opsx collect`，一行一卡。
按鍵：↑↓ / j k 選、Enter 跳到該卡的 pane（herdr pane focus）、r 重拉、d 展開/收起已完成、q 關。
不回 gate、不派工、不合併：那些在網頁（open-board）。排序與游標在 tui_model.py，這裡只畫。
collect 在背景 thread 跑，畫面迴圈只讀最新一份，所以 collect 慢的時候按鍵照樣有反應。
"""
from __future__ import annotations

import curses
import json
import pathlib
import subprocess
import sys
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import tui_model as tm  # noqa: E402

REFRESH_S = 5
COLLECT_TIMEOUT = 60
EMPTY = {"cards": [], "unmatched_agents": [], "errors": []}


def collect() -> dict:
    try:
        p = subprocess.run(["bash", str(HERE.parent / "bin" / "opsx"), "collect"], capture_output=True, text=True, timeout=COLLECT_TIMEOUT)
    except subprocess.TimeoutExpired:
        return dict(EMPTY, errors=[{"source": "opsx", "message": "opsx collect 超過 %d 秒" % COLLECT_TIMEOUT}])
    if p.returncode != 0:
        return dict(EMPTY, errors=[{"source": "opsx", "message": p.stderr.strip()[:200]}])
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError as e:
        return dict(EMPTY, errors=[{"source": "opsx", "message": "collect 不是 JSON：%s" % e}])


class Feed:
    """背景抓資料；latest 永遠是最後一份完整結果，wake 叫它馬上再抓一次。"""

    def __init__(self):
        self.latest: dict | None = None
        self.seq = 0
        self.wake = threading.Event()
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.loop, daemon=True)

    def start(self):
        self.thread.start()

    def loop(self):
        while not self.stop.is_set():
            self.latest = collect(); self.seq += 1
            self.wake.wait(REFRESH_S); self.wake.clear()


def draw(scr, rows, cur: tm.Cursor, data: dict, note: str) -> None:
    scr.erase()
    h, w = scr.getmaxyx()
    n_wait = sum(1 for r in rows if r["kind"] == "card" and r["card"].get("section") == "待處理")
    scr.addstr(0, 0, tm.fit(" opsx  待處理 %d" % n_wait, w - 1), curses.A_BOLD)
    y = 2
    top = max(0, (cur.index or 0) - (h - 6))
    for i, r in enumerate(rows):
        if i < top or y >= h - 2:
            continue
        if r["kind"] == "header":
            scr.addstr(y, 0, tm.fit("%s %s · %d" % ("▸" if r.get("collapsed") else "▾", r["section"], r["count"]), w - 1), curses.A_BOLD)
        else:
            attr = curses.A_REVERSE if i == cur.index else curses.A_NORMAL
            scr.addstr(y, 2, tm.fit("%s %s" % (r["mark"], r["text"]), w - 3), attr)
        y += 1
    errs = "；".join("%s：%s" % (e.get("source"), e.get("message")) for e in data.get("errors") or [])
    foot = note or errs or "↑↓ 選  ↵ 跳 pane  r 重拉  d 已完成  q 關  （回 gate / 指派 / 合併在網頁）"
    scr.addstr(h - 1, 0, tm.fit(foot, w - 1), curses.A_DIM)
    scr.refresh()


def main(scr) -> None:
    curses.curs_set(0)
    scr.timeout(250)
    feed = Feed(); feed.start()
    done_open = False
    data: dict = dict(EMPTY)
    seen = 0
    rows = tm.rows(data, done_open)
    cur = tm.Cursor(rows)
    note = "載入中…"
    while True:
        if feed.latest is not None and feed.seq != seen:
            data = feed.latest; seen = feed.seq
            rows = tm.rows(data, done_open); cur.rebind(rows)
            if note == "載入中…" or note == "重拉了": note = ""
        draw(scr, rows, cur, data, note)
        k = scr.getch()
        if k == -1:
            continue
        if k in (ord("q"), 27):
            feed.stop.set(); feed.wake.set(); return
        if k in (curses.KEY_DOWN, ord("j")):
            cur.move(1); note = ""
        elif k in (curses.KEY_UP, ord("k")):
            cur.move(-1); note = ""
        elif k == ord("r"):
            feed.wake.set(); note = "重拉了"
        elif k == ord("d"):
            done_open = not done_open; rows = tm.rows(data, done_open); cur.rebind(rows)
        elif k in (curses.KEY_ENTER, 10, 13) and cur.index is not None:
            argv = tm.enter(rows[cur.index])
            if argv is None:
                note = "這張還沒派出，沒有 pane"
            else:
                r = subprocess.run(argv, capture_output=True, text=True)
                note = " ".join(argv) if r.returncode == 0 else "%s 失敗：%s" % (" ".join(argv), r.stderr.strip()[:80])


if __name__ == "__main__":
    curses.wrapper(main)
