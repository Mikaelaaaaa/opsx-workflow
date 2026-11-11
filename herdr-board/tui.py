#!/usr/bin/env python3
"""opsx 看板的 herdr pane（最小 TUI，herdr-board D4）：同一份 `opsx collect`，一行一卡。
按鍵：↑↓ / j k 選、Enter 跳到該卡的 agent（herdr agent focus <slug>）、r 重拉、i 展開/收起收件匣、d 展開/收起已完成、
o 網頁開這張、+ 丟一句話進收件匣（opsx new）、Tab 換 workspace 範圍、z 全屏、q 關。
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
    """成功回 collect 的 JSON；失敗只回 {errors}，畫面沿用上一份（tm.refreshed）。"""
    try:
        p = subprocess.run(["bash", str(HERE.parent / "bin" / "opsx"), "collect"], capture_output=True, text=True, timeout=COLLECT_TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"errors": [{"source": "opsx", "message": "opsx collect 超過 %d 秒" % COLLECT_TIMEOUT}]}
    if p.returncode != 0:
        return {"errors": [{"source": "opsx", "message": p.stderr.strip()[:200]}]}
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError as e:
        return {"errors": [{"source": "opsx", "message": "collect 不是 JSON：%s" % e}]}


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


def draw(scr, rows, cur: tm.Cursor, data: dict, note: str, scope: str | None, box: tm.LineInput | None) -> None:
    scr.erase()
    h, w = scr.getmaxyx()
    scr.addstr(0, 0, tm.fit(tm.top_line(data, scope), w - 1), curses.A_BOLD)
    errs = "；".join("%s：%s" % (e.get("source"), e.get("message")) for e in data.get("errors") or [])
    foot = note or errs or "↑↓ 選  ↵ 跳 pane  r 重拉  i 收件匣  d 已完成  o 網頁  + 收件匣  ⇥ 範圍  z 全屏  q 關  （回 gate / 指派 / 合併在網頁）"
    foot_lines = [""] if box is not None else tm.wrap(foot, w - 1, 3)   # 沒有 opener 時的網址要整段看得到
    # 矮視窗先砍進度行，至少留一列給卡片；捲動保留行數不能是負的，不然游標列會被捲出畫面
    lines = tm.progress_lines(data, scope)[:max(0, h - 4 - len(foot_lines))]
    for i, line in enumerate(lines):
        scr.addstr(1 + i, 0, tm.fit(line, w - 1))
    y = 2 + len(lines)
    top = max(0, (cur.index or 0) - max(0, h - 6 - len(lines)))
    for i, r in enumerate(rows):
        if i < top or y >= h - 1 - len(foot_lines):
            continue
        if r["kind"] == "header":
            scr.addstr(y, 0, tm.fit("%s %s · %d%s" % ("▸" if r.get("collapsed") else "▾", r["section"], r["count"], " · 孤兒 pane %d（網頁上關）" % r["orphans"] if r["orphans"] else ""), w - 1), curses.A_BOLD)
        else:
            attr = curses.A_REVERSE if i == cur.index else curses.A_NORMAL
            scr.addstr(y, 2, tm.fit("%s %s" % (r["mark"], r["text"]), w - 3), attr)
        y += 1
    if box is not None:
        prompt = tm.fit("+ 收件匣：" + box.text, w - 2)
        scr.addstr(h - 1, 0, prompt)
        scr.move(h - 1, tm.width(prompt))
    else:
        for i, line in enumerate(foot_lines):
            scr.addstr(h - len(foot_lines) + i, 0, line, curses.A_DIM)
    scr.refresh()


def main(scr) -> None:
    curses.curs_set(0)
    scr.timeout(250)
    feed = Feed(); feed.start()
    done_open = inbox_open = False
    data: dict = dict(EMPTY)
    seen = 0
    scope = None
    box: tm.LineInput | None = None   # 不是 None 時底列在輸入，按鍵改用 get_wch 讀
    rows = tm.rows(data, done_open, inbox_open, scope)
    cur = tm.Cursor(rows)
    note = "載入中…"
    while True:
        if feed.latest is not None and feed.seq != seen:
            data = tm.refreshed(data, feed.latest); seen = feed.seq
            scope = tm.keep_scope(data, scope)
            rows = tm.rows(data, done_open, inbox_open, scope); cur.rebind(rows)
            if note == "載入中…" or note == "重拉了": note = ""
        draw(scr, rows, cur, data, note, scope, box)
        if box is not None:
            try:
                res = box.feed(scr.get_wch())
            except curses.error:   # timeout 到了沒有按鍵
                continue
            if res is not None:
                # 貼上的多行或手快多按的鍵還在緩衝裡，不清掉會落到一般模式當熱鍵（q 關 TUI、o 開網頁）
                box = None; curses.curs_set(0); curses.flushinp(); note = ""
            if res is not None and res[0] == "submit":
                argv = tm.new_argv(str(HERE.parent), data, scope, res[1])
                r = subprocess.run(argv, capture_output=True, text=True)
                note = tm.outcome(argv, r, "收件匣 +1：%s" % r.stdout.strip())
            continue
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
            done_open = not done_open; rows = tm.rows(data, done_open, inbox_open, scope); cur.rebind(rows)
        elif k == ord("i"):
            inbox_open = not inbox_open; rows = tm.rows(data, done_open, inbox_open, scope); cur.rebind(rows)
        elif k == ord("\t"):
            scope = tm.next_scope(data, scope); rows = tm.rows(data, done_open, inbox_open, scope); cur.rebind(rows); note = ""
        elif k in (curses.KEY_ENTER, 10, 13) and cur.index is not None:
            argv = tm.enter(rows[cur.index])
            if argv is None:
                note = "這張還沒派出，沒有 pane"
            else:
                note = tm.outcome(argv, subprocess.run(argv, capture_output=True, text=True), " ".join(argv))
        elif k == ord("o"):
            argv = tm.open_argv(str(HERE.parent), rows[cur.index] if cur.index is not None else None)
            if argv is None:
                note = "沒有可開的卡（游標不在卡上，或 session 已全部合併）"
            else:
                note = tm.open_outcome(argv, subprocess.run(argv, capture_output=True, text=True))
        elif k == ord("+"):
            box = tm.LineInput(); curses.curs_set(1)
        elif k == ord("z"):
            note = tm.outcome(tm.ZOOM_ARGV, subprocess.run(tm.ZOOM_ARGV, capture_output=True, text=True), "全屏切換了")


if __name__ == "__main__":
    curses.wrapper(main)
