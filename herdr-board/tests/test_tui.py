"""herdr-board/tui_model.py：TUI 的純函式（排序、游標、範圍、輸入框、各鍵的 argv）；MainLoopTest 用假的 curses 視窗跑 tui.main 的按鍵迴圈。畫面長相不在這裡測。
驗收：specs/board-plugin/spec.md「最小 TUI」的 Scenario（herdr-board 5.2、tui-keys/tui-new-keys）。
跑法：python3 -I herdr-board/tests/test_tui.py
"""
import curses
import importlib.util
import os
import pathlib
import subprocess
import threading
import time
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("tui_model", HERE.parent / "tui_model.py")
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)
tui_spec = importlib.util.spec_from_file_location("tui", HERE.parent / "tui.py")
tui = importlib.util.module_from_spec(tui_spec)
tui_spec.loader.exec_module(tui)


def card(slug, section, pane=None, waiting=None, status=None, repo="a"):
    return {"repo": repo, "slug": slug, "title": slug + " 標題", "section": section, "stage": "apply", "since": "2026-11-05",
            "waiting": waiting, "dispatch": {"pane": pane, "agent": slug} if pane else None, "status": status,
            "agent_status": "working" if pane else None, "mr": None}


def in_progress_header(data):
    return next(r for r in tm.rows(data, done_open=False) if r["kind"] == "header" and r["section"] == "進行中")


DATA = {"generated_at": "t", "scopes": [], "errors": [], "unmatched_agents": [],
        "cards": [
            card("done1", "已完成"),
            card("inbox1", "收件匣"),
            card("ready1", "待指派"),
            card("run1", "進行中", pane="p5", status={"phase": "apply", "step": "3", "total": "8", "label": "x"}),
            card("ask1", "待處理", pane="p4", waiting={"type": "等待授權", "question": "push?", "recommended": "允許"}),
            card("ask2", "待處理", pane="p2", waiting={"type": "可以合併", "question": "MR 全綠", "recommended": "合併"}),
        ]}


class RowsTest(unittest.TestCase):
    def test_sections_in_order_and_done_collapsed(self):
        rows = tm.rows(DATA, done_open=False)
        kinds = [(r["kind"], r.get("section") or r.get("card", {}).get("slug")) for r in rows]
        self.assertEqual(kinds[0], ("header", "待處理"))
        slugs = [r["card"]["slug"] for r in rows if r["kind"] == "card"]
        self.assertEqual(slugs, ["ask1", "ask2", "run1", "ready1"], "待處理在最上，已完成收起")
        headers = [r["section"] for r in rows if r["kind"] == "header"]
        self.assertEqual(headers, ["待處理", "進行中", "待指派", "收件匣", "已完成"])
        collapsed = {r["section"]: r["collapsed"] for r in rows if r["kind"] == "header"}
        self.assertTrue(collapsed["收件匣"] and collapsed["已完成"], "收件匣與已完成預設收起")

    def test_inbox_open_lists_inbox_before_done(self):
        slugs = [r["card"]["slug"] for r in tm.rows(DATA, done_open=True, inbox_open=True) if r["kind"] == "card"]
        self.assertEqual(slugs[-2:], ["inbox1", "done1"])

    def test_inbox_open_lists_shortcut_counts_per_repo(self):
        hit = {"file": "x.py", "line": 1, "limit": "l", "trigger": "t"}
        data = {**DATA, "debt": {"a": [hit, hit], "b": [hit], "c": []}}
        debt = [r for r in tm.rows(data, done_open=False, inbox_open=True) if r["kind"] == "debt"]
        self.assertEqual([(r["repo"], r["count"]) for r in debt], [("a", 2), ("b", 1)], "只列有 shortcut 的 repo，數量照筆數")
        self.assertIn("2", debt[0]["text"])
        self.assertEqual([r for r in tm.rows(data, done_open=False) if r["kind"] == "debt"], [], "收件匣收起時不列")
        self.assertEqual([r for r in tm.rows(DATA, done_open=False, inbox_open=True) if r["kind"] == "debt"], [], "沒有 debt 鍵（舊資料）不列")
        self.assertEqual(tm.enter(debt[0]), None, "Enter 在 shortcut 行什麼都不做")

    def test_done_open_lists_done_cards(self):
        slugs = [r["card"]["slug"] for r in tm.rows(DATA, done_open=True) if r["kind"] == "card"]
        self.assertEqual(slugs[-1], "done1")

    def test_in_progress_header_counts_orphans(self):
        self.assertEqual(in_progress_header({**DATA, "orphans": [{"pane": "w1:p1"}, {"pane": "w1:p2"}]})["orphans"], 2)
        self.assertEqual(in_progress_header(DATA)["orphans"], 0, "舊資料沒有 orphans 這個鍵")

    def test_card_line_text(self):
        rows = tm.rows(DATA, done_open=False)
        ask = next(r for r in rows if r["kind"] == "card" and r["card"]["slug"] == "ask1")
        self.assertIn("等待授權", ask["text"])
        self.assertIn("push?", ask["text"])
        run = next(r for r in rows if r["kind"] == "card" and r["card"]["slug"] == "run1")
        self.assertIn("apply 3/8", run["text"])


SESSION = {"repo": "a", "feature": "fb", "section": "進行中", "main_done": 1, "main_total": 2, "sub_done": 5, "sub_total": 7,
           "current": {"slug": "bt", "stage": "review"},
           "mains": [{"slug": "bt", "pr_status": "in-progress", "stage": "review", "section": "進行中",
                      "dispatch": {"pane": "p9", "agent": "claude", "herdr_name": "fb"}, "agent_status": "working",
                      "open_gates": [], "waiting": None, "subs": []}]}
SDATA = {"cards": [dict(card("bt", "進行中", pane="p9"), session="a/fb"), card("solo", "進行中")],
         "sessions": [SESSION], "unmatched_agents": [], "errors": []}


class SessionRowsTest(unittest.TestCase):
    def test_session_line_text(self):
        rows = tm.rows(SDATA, done_open=False)
        s = next(r for r in rows if r["kind"] == "session")
        self.assertIn("fb · 主 change 1/2 · 子 change 5/7 · bt review", s["text"])
        self.assertTrue(tm._session_line(dict(SESSION, current=None)).endswith("已合併"))
        self.assertEqual(tm._session_line(dict(SESSION, current={"slug": "bt", "stage": None})),
                         "fb · 主 change 1/2 · 子 change 5/7 · bt", "目前站沒有 stage 就只寫 slug")

    def test_session_replaces_its_mains(self):
        rows = tm.rows(SDATA, done_open=False)
        i = next(i for i, r in enumerate(rows) if r["kind"] == "header" and r["section"] == "進行中")
        j = next(i for i, r in enumerate(rows) if r["kind"] == "header" and r["section"] == "待指派")
        names = [r["session"]["feature"] if r["kind"] == "session" else r["card"]["slug"] for r in rows[i + 1:j]]
        self.assertEqual(names, ["fb", "solo"], "進行中有 fb 一行與 solo 一行，沒有 bt")
        self.assertEqual(rows[i]["count"], 2, "區塊計數含 session")

    def test_collapsed_section_keeps_session_hidden_but_counted(self):
        data = dict(SDATA, sessions=[dict(SESSION, section="已完成", current=None)])
        rows = tm.rows(data, done_open=False)
        done = next(r for r in rows if r["kind"] == "header" and r["section"] == "已完成")
        self.assertTrue(done["collapsed"])
        self.assertEqual(done["count"], 1)
        self.assertFalse(any(r["kind"] == "session" for r in rows))

    def test_enter_on_session_focuses_current_main(self):
        rows = tm.rows(SDATA, done_open=False)
        cur = tm.Cursor(rows)
        self.assertEqual(rows[cur.index]["kind"], "session", "游標停在 session 行")
        self.assertEqual(tm.enter(rows[cur.index]), ["herdr", "agent", "focus", "fb"])
        cur.move(1)
        self.assertEqual(rows[cur.index]["card"]["slug"], "solo")
        cur.move(-1)
        self.assertEqual(rows[cur.index]["key"], "session:a/fb")

    def test_enter_on_session_uses_slug_without_herdr_name_and_none_when_not_dispatched(self):
        main = dict(SESSION["mains"][0], dispatch={"pane": "p9", "agent": "claude"})
        self.assertEqual(tm.enter({"kind": "session", "session": dict(SESSION, mains=[main])}),
                         ["herdr", "agent", "focus", "bt"])
        idle = dict(SESSION["mains"][0], dispatch=None)
        self.assertIsNone(tm.enter({"kind": "session", "session": dict(SESSION, mains=[idle])}))
        self.assertIsNone(tm.enter({"kind": "session", "session": dict(SESSION, current=None)}))


class WidthTest(unittest.TestCase):
    def test_cjk_counts_two_columns(self):
        self.assertEqual(tm.width("ab"), 2)
        self.assertEqual(tm.width("中文"), 4)
        self.assertEqual(tm.width("a中"), 3)

    def test_fit_never_splits_a_wide_char(self):
        self.assertEqual(tm.fit("中文字", 4), "中文")
        self.assertEqual(tm.fit("中文字", 5), "中文")
        self.assertEqual(tm.fit("abc", 2), "ab")
        self.assertEqual(tm.fit("", 3), "")


class CursorTest(unittest.TestCase):
    def test_moves_only_over_cards_and_stays_in_bounds(self):
        rows = tm.rows(DATA, done_open=False)
        cur = tm.Cursor(rows)
        self.assertEqual(rows[cur.index]["card"]["slug"], "ask1", "起始在第一張卡")
        cur.move(-1)
        self.assertEqual(rows[cur.index]["card"]["slug"], "ask1", "上面沒有了就不動")
        cur.move(1); cur.move(1); cur.move(1)
        self.assertEqual(rows[cur.index]["card"]["slug"], "ready1")
        cur.move(1)
        self.assertEqual(rows[cur.index]["card"]["slug"], "ready1", "最後一列按 ↓ 不動")
        self.assertTrue(all(rows[i]["kind"] == "card" for i in [cur.index]))

    def test_cursor_keeps_card_across_refresh(self):
        rows = tm.rows(DATA, done_open=False)
        cur = tm.Cursor(rows); cur.move(2)
        key = cur.key
        rows2 = tm.rows(DATA, done_open=True)
        cur.rebind(rows2)
        self.assertEqual(cur.key, key)

    def test_enter_focuses_pane_only_when_dispatched(self):
        rows = tm.rows(DATA, done_open=False)
        cur = tm.Cursor(rows)
        self.assertEqual(tm.enter(rows[cur.index]), ["herdr", "agent", "focus", "ask1"])   # agent 名 = slug，不是 pane id
        cur.move(3)
        self.assertEqual(rows[cur.index]["card"]["slug"], "ready1")
        self.assertIsNone(tm.enter(rows[cur.index]), "沒派出的卡 Enter 不做事")

    def test_empty_board(self):
        rows = tm.rows({"cards": [], "unmatched_agents": [], "errors": []}, done_open=False)
        cur = tm.Cursor(rows)
        self.assertIsNone(cur.index)
        cur.move(1)
        self.assertIsNone(cur.index)


def proc(argv, rc=0, out="", err=""):
    return subprocess.CompletedProcess(argv, rc, out, err)


class ZoomTest(unittest.TestCase):
    def test_zoom_argv(self):
        self.assertEqual(tm.ZOOM_ARGV, ["herdr", "pane", "zoom", "--current", "--toggle"])

    def test_outcome_shows_ok_text_or_first_80_of_stderr(self):
        self.assertEqual(tm.outcome(tm.ZOOM_ARGV, proc(tm.ZOOM_ARGV), "全屏切換了"), "全屏切換了")
        note = tm.outcome(tm.ZOOM_ARGV, proc(tm.ZOOM_ARGV, rc=1, err="  " + "x" * 100 + "\n"), "全屏切換了")
        self.assertEqual(note, "herdr pane zoom --current --toggle 失敗：" + "x" * 80)


SCOPES = [{"workspace": "w1", "repos": ["a"]}, {"workspace": None, "repos": ["b"]}]
WDATA = {"scopes": SCOPES, "repo_paths": {"a": "/r/a", "b": "/r/b"}, "unmatched_agents": [], "errors": [],
         "cards": [card("ka", "待處理", repo="a"), card("kb", "待處理", repo="b")],
         "sessions": [dict(SESSION, repo="b")]}


class ScopeTest(unittest.TestCase):
    def test_tab_cycles_all_then_workspaces_then_all(self):
        seen, scope = [], None
        for _ in range(3):
            scope = tm.next_scope(WDATA, scope)
            seen.append(tm.scope_label(scope))
        self.assertEqual(seen, ["w1", "沒掛的", "全部"])

    def test_tab_with_no_scopes_stays_all(self):
        self.assertIsNone(tm.next_scope({"cards": []}, None))

    def test_scope_filters_cards_and_sessions_but_not_pending_count(self):
        rows = tm.rows(WDATA, done_open=False, scope="w1")
        self.assertEqual([r["card"]["slug"] for r in rows if r["kind"] == "card"], ["ka"])
        self.assertFalse(any(r["kind"] == "session" for r in rows), "repo b 的 session 不在 w1")
        self.assertEqual(tm.top_line(WDATA, "w1"), " opsx  待處理 2  範圍 w1")
        unmounted = tm.rows(WDATA, done_open=False, scope=tm.next_scope(WDATA, "w1"))
        self.assertEqual([r["card"]["slug"] for r in unmounted if r["kind"] == "card"], ["kb"])
        self.assertEqual([r["kind"] for r in unmounted].count("session"), 1)

    def test_all_scope_keeps_everything(self):
        rows = tm.rows(WDATA, done_open=False, scope=None)
        self.assertEqual([r["card"]["slug"] for r in rows if r["kind"] == "card"], ["ka", "kb"])
        self.assertEqual(tm.top_line(WDATA, None), " opsx  待處理 2  範圍 全部")

    def test_vanished_workspace_falls_back_to_all(self):
        gone = dict(WDATA, scopes=[{"workspace": "w2", "repos": ["a"]}])
        self.assertIsNone(tm.keep_scope(gone, "w1"))
        self.assertIsNone(tm.next_scope(gone, "w1"), "從消失的範圍按 Tab 也回全部")
        self.assertEqual(tm.keep_scope(WDATA, "w1"), "w1")
        self.assertEqual(tm.keep_scope(WDATA, tm.UNMOUNTED), tm.UNMOUNTED)


def progress(milestone="1.0", at="2026-11-11T14:30:00+08:00", remaining=5):
    return {"milestone": milestone, "goal": "能開單出貨", "remaining": remaining, "mergeable": 1, "testing": 1, "developing": 1,
            "waiting_on_you": 1, "not_dispatched": 1, "not_dispatched_planned": ["x"], "at": at}


ONE_LINE = "進度 14:30 · 1.0：剩 5 張 · 可合併 1 · 測試中 1 · 開發中 1 · 等你 1 · 還沒派 1"
FIVE = dict(WDATA, scopes=[{"workspace": "w1", "repos": ["e", "d"]}, {"workspace": None, "repos": ["c", "b", "a"]}],
            progress={r: progress() for r in "abcde"})


class ProgressLinesTest(unittest.TestCase):
    """specs/board-plugin「TUI 頂列下的進度行」；預期字串與網頁 progressLine 的測試共用。"""

    def setUp(self):
        self.tz = os.environ.get("TZ")
        os.environ["TZ"] = "Asia/Taipei"
        time.tzset()

    def tearDown(self):
        if self.tz is None:
            del os.environ["TZ"]
        else:
            os.environ["TZ"] = self.tz
        time.tzset()

    def test_same_string_as_web(self):
        self.assertEqual(tm.progress_lines(dict(WDATA, progress={"a": progress()}), "w1"), [ONE_LINE])

    def test_no_milestone_says_in_progress(self):
        line = tm.progress_text("a", progress(milestone=None, remaining=4), False)
        self.assertIn("進行中 4 張", line)
        self.assertNotIn("剩", line)

    def test_time_is_local(self):
        os.environ["TZ"] = "UTC"
        time.tzset()
        self.assertTrue(tm.progress_text("a", progress(), False).startswith("進度 06:30 · "))

    def test_out_of_scope_repo_not_listed(self):
        data = dict(WDATA, progress={"a": progress(), "b": progress()})
        self.assertEqual(tm.progress_lines(data, "w1"), [ONE_LINE], "b 不在 w1，也只剩一個 repo 所以不加 repo 名")
        self.assertEqual(tm.top_line(data, "w1"), " opsx  待處理 2  範圍 w1", "頂列待處理數仍照全部算")

    def test_two_repos_prefix_repo_name_in_scopes_order(self):
        data = dict(WDATA, progress={"b": progress(), "a": progress()})
        self.assertEqual(tm.progress_lines(data, None), ["a " + ONE_LINE, "b " + ONE_LINE])

    def test_repo_without_progress_skipped(self):
        self.assertEqual(tm.progress_lines(dict(WDATA, progress={"b": progress()}), None), [ONE_LINE])

    def test_more_than_three_repos_collapse(self):
        self.assertEqual(tm.progress_lines(FIVE, None),
                         ["e " + ONE_LINE, "d " + ONE_LINE, "c " + ONE_LINE, "另 2 個 repo，⇥ 切範圍"])

    def test_no_progress_field_draws_nothing(self):
        self.assertEqual(tm.progress_lines(WDATA, None), [])
        self.assertEqual(tm.progress_lines(dict(tui.EMPTY), None), [], "一開始還沒資料也不報錯")

    def test_cards_start_below_progress_lines(self):
        scr = DrawScr()
        rows = tm.rows(FIVE, done_open=False)
        tui.draw(scr, rows, tm.Cursor(rows), FIVE, "", None, None)
        self.assertEqual([y for y, text in scr.lines if "另 2 個 repo" in text], [4])
        self.assertEqual(min(y for y, text in scr.lines if "待處理 ·" in text), 6, "卡片從 2 + 4 行進度之後開始")

    def test_short_terminal_still_shows_cursor_row(self):
        scr = DrawScr(h=9)
        rows = tm.rows(FIVE, done_open=False)
        cur = tm.Cursor(rows)
        cur.move(99)
        tui.draw(scr, rows, cur, FIVE, "", None, None)
        self.assertEqual(len(scr.reversed), 1, "游標在最後一張卡時反白列仍要畫出來：%s" % scr.lines)

    def test_cursor_row_shown_with_one_line_footer(self):
        scr = DrawScr(h=9)
        rows = tm.rows(FIVE, done_open=False)
        cur = tm.Cursor(rows)
        cur.move(99)
        tui.draw(scr, rows, cur, FIVE, "", None, tm.LineInput())
        self.assertEqual(len(scr.reversed), 1, "輸入框開著（底列 1 行）時反白列要畫出來：%s" % scr.lines)

    def test_cursor_row_shown_with_three_line_footer(self):
        scr = DrawScr(h=12)
        rows = tm.rows(FIVE, done_open=False)
        cur = tm.Cursor(rows)
        cur.move(99)
        tui.draw(scr, rows, cur, FIVE, "x" * 300, None, None)
        self.assertEqual(len(scr.reversed), 1, "底列折成 3 行時反白列要畫出來：%s" % scr.lines)

    def test_tiny_terminal_does_not_write_outside(self):
        scr = DrawScr(h=4)
        rows = tm.rows(FIVE, done_open=False)
        tui.draw(scr, rows, tm.Cursor(rows), FIVE, "", None, None)
        self.assertEqual([t for _, t in scr.lines if "進度" in t or "另 2 個 repo" in t], [], "放不下卡片時不畫進度行")


def typed(*keys):
    box = tm.LineInput()
    results = [box.feed(k) for k in keys]
    return box, results


class LineInputTest(unittest.TestCase):
    def test_edit_chinese_with_backspace(self):
        box, results = typed("修", "正", curses.KEY_BACKSPACE, "好")
        self.assertEqual(box.text, "修好")
        self.assertEqual(results, [None, None, None, None])

    def test_terminal_backspace_chars_and_empty_backspace(self):
        box, _ = typed("\x7f", "a", "b", "\x7f", "c", "\x08")
        self.assertEqual(box.text, "a")

    def test_enter_submits_stripped_text(self):
        self.assertEqual(typed(" ", "修", " ", "X", " ", "\n")[1][-1], ("submit", "修 X"))
        self.assertEqual(typed("y", curses.KEY_ENTER)[1][-1], ("submit", "y"))
        self.assertEqual(typed("y", "\r")[1][-1], ("submit", "y"))

    def test_esc_cancels_and_blank_enter_is_not_sent(self):
        self.assertEqual(typed("修", " ", "X", "\x1b")[1][-1], ("cancel",))
        self.assertEqual(typed(" ", " ", "\n")[1][-1], ("cancel",))
        self.assertEqual(typed("\n")[1][-1], ("cancel",))

    def test_other_keys_and_control_chars_are_ignored(self):
        box, results = typed("a", curses.KEY_LEFT, "\t", "b")
        self.assertEqual(box.text, "ab")
        self.assertEqual(results, [None, None, None, None])


class NewArgvTest(unittest.TestCase):
    def test_single_repo_scope_passes_repo_path(self):
        self.assertEqual(tm.new_argv("/root", WDATA, "w1", "修 X"),
                         ["bash", "/root/bin/opsx", "new", "--repo", "/r/a", "--", "修 X"])

    def test_all_scope_goes_to_unfiled(self):
        self.assertEqual(tm.new_argv("/root", WDATA, None, "修 X"), ["bash", "/root/bin/opsx", "new", "--", "修 X"])

    def test_multi_repo_scope_goes_to_unfiled(self):
        data = dict(WDATA, scopes=[{"workspace": "w1", "repos": ["a", "b"]}])
        self.assertEqual(tm.new_argv("/root", data, "w1", "修 X"), ["bash", "/root/bin/opsx", "new", "--", "修 X"])

    def test_unmounted_single_repo_uses_its_path(self):
        self.assertEqual(tm.new_argv("/root", WDATA, tm.UNMOUNTED, "y"),
                         ["bash", "/root/bin/opsx", "new", "--repo", "/r/b", "--", "y"])


OPEN = ["bash", "/root/herdr-board/scripts/open-board.sh"]


class OpenArgvTest(unittest.TestCase):
    def test_card_row_opens_repo_slug(self):
        row = next(r for r in tm.rows(DATA, done_open=False) if r["kind"] == "card" and r["card"]["slug"] == "ask1")
        self.assertEqual(tm.open_argv("/root", row), OPEN + ["a/ask1"])

    def test_session_row_opens_current_main(self):
        row = next(r for r in tm.rows(SDATA, done_open=False) if r["kind"] == "session")
        self.assertEqual(tm.open_argv("/root", row), OPEN + ["a/bt"])

    def test_nothing_to_open(self):
        self.assertIsNone(tm.open_argv("/root", {"kind": "session", "session": dict(SESSION, current=None)}), "session 已全部合併")
        self.assertIsNone(tm.open_argv("/root", {"kind": "header", "section": "待處理"}))
        self.assertIsNone(tm.open_argv("/root", None), "游標不在卡上")


class KeysRunOut(Exception):
    """FakeScr 的按鍵用完：main 還在迴圈裡（沒被某個鍵關掉）。"""


class FakeScr:
    """照順序吐按鍵的 curses 視窗。字串是按鍵，可呼叫的項目在輪到時執行一次（模擬兩次按鍵之間發生的事）。"""

    def __init__(self, keys):
        self.keys = list(keys)

    def next(self):
        if not self.keys:
            raise KeysRunOut
        return self.keys.pop(0)

    def getch(self):
        k = self.next()
        if callable(k):
            k()
            return -1
        return ord(k) if isinstance(k, str) else k

    def get_wch(self):
        k = self.next()
        if callable(k):
            k()
            raise curses.error("no input")
        return k

    def flushinp(self):
        self.keys.clear()

    def getmaxyx(self):
        return (24, 80)

    def timeout(self, ms):
        pass

    def erase(self):
        pass

    def addstr(self, *args):
        pass

    def move(self, y, x):
        pass

    def refresh(self):
        pass


class DrawScr(FakeScr):
    """記下 draw 每次 addstr 的 (y, 文字)，反白的列另記；跟真的 curses 一樣，寫到視窗外丟 curses.error。"""

    def __init__(self, h=24):
        super().__init__([])
        self.h = h
        self.lines = []
        self.reversed = []

    def getmaxyx(self):
        return (self.h, 80)

    def addstr(self, y, x, text, *attr):
        if y >= self.h:
            raise curses.error("addwstr() returned ERR")
        self.lines.append((y, text))
        if attr and attr[0] == curses.A_REVERSE:
            self.reversed.append(text)


class FakeFeed:
    def __init__(self, data):
        self.latest, self.seq = data, 1
        self.wake, self.stop = threading.Event(), threading.Event()

    def start(self):
        pass

    def fail(self):
        """下一份是 collect 失敗的結果（逾時）。"""
        with mock.patch.object(tui.subprocess, "run", side_effect=subprocess.TimeoutExpired("opsx", 60)):
            self.latest = tui.collect()
        self.seq += 1


class Runs:
    """代替 subprocess.run，記下每個 argv。"""

    def __init__(self):
        self.argvs = []
        self.kws = []

    def __call__(self, argv, **kw):
        self.argvs.append(argv)
        self.kws.append(kw)
        return proc(argv, out="me-1\n")


def curs_set(n):
    pass


def drive(feed, scr, runs=None):
    """跑 tui.main 直到按鍵用完；回 main 跑過的外部指令。main 自己 return（被某個鍵關掉）時 assert 失敗。runs 給了就由呼叫端讀它記下的 kwargs。"""
    runs = runs or Runs()
    with mock.patch.object(tui, "Feed", return_value=feed), mock.patch.object(tui.subprocess, "run", runs), \
            mock.patch.object(tui.curses, "curs_set", curs_set), mock.patch.object(tui.curses, "flushinp", scr.flushinp):
        try:
            tui.main(scr)
        except KeysRunOut:
            return runs.argvs
    raise AssertionError("main 在按鍵用完前就結束了（某個按鍵被當成 q／Esc）")


class MainLoopTest(unittest.TestCase):
    def test_pasted_lines_after_submit_are_not_hotkeys(self):
        argvs = drive(FakeFeed(WDATA), FakeScr(["+", "a", "b", "\n", "o", "q"]))
        self.assertEqual(argvs, [["bash", str(HERE.parent.parent / "bin" / "opsx"), "new", "--", "ab"]],
                         "只送出第一行；換行後的 o 不開網頁、q 不關 TUI")

    def test_new_does_not_pass_opsx_card_to_opsx(self):
        runs = Runs()
        with mock.patch.dict(os.environ,{"OPSX_CARD": "foo"}):
            drive(FakeFeed(WDATA), FakeScr(["+", "a", "\n"]), runs)
        self.assertEqual(len(runs.kws), 1)
        self.assertNotIn("OPSX_CARD", runs.kws[0]["env"])

    def test_queued_keys_after_cancel_are_not_hotkeys(self):
        self.assertEqual(drive(FakeFeed(WDATA), FakeScr(["+", "a", "\x1b", "z", "\x1b"])), [], "Esc 取消後排隊的 z、Esc 不執行")

    def test_failed_collect_keeps_scope_and_board(self):
        feed = FakeFeed(WDATA)
        argvs = drive(feed, FakeScr(["\t", feed.fail, "+", "x", "\n"]))
        self.assertEqual(argvs[-1][-4:], ["--repo", "/r/a", "--", "x"], "collect 失敗一次，範圍仍是 w1")

    def test_failed_collect_replaces_only_errors(self):
        with mock.patch.object(tui.subprocess, "run", side_effect=subprocess.TimeoutExpired("opsx", 60)):
            err = tui.collect()
        kept = tm.refreshed(WDATA, err)
        self.assertEqual(kept["cards"], WDATA["cards"])
        self.assertEqual(kept["scopes"], WDATA["scopes"])
        self.assertIn("超過", kept["errors"][0]["message"])
        self.assertIs(tm.refreshed(WDATA, DATA), DATA, "collect 成功就整份換新")

    def test_kept_board_says_so_on_top_line(self):
        with mock.patch.object(tui.subprocess, "run", side_effect=subprocess.TimeoutExpired("opsx", 60)):
            err = tui.collect()
        self.assertIn("collect 失敗", tm.top_line(tm.refreshed(WDATA, err), "w1"), "底列有 note 時頂列仍看得出資料是舊的")
        self.assertIn("collect 失敗", tm.top_line(tm.refreshed(dict(tui.EMPTY), err), None), "一開始就失敗也要說")
        self.assertNotIn("collect 失敗", tm.top_line(tm.refreshed(tm.refreshed(WDATA, err), WDATA), "w1"), "下一次成功就拿掉")


TOKEN = "T" * 43
NO_OPENER = "opsx board: 沒有 open 或 xdg-open，自己開 http://127.0.0.1:8791/#token=%s&card=opsx-workflow/notification-toast-replays-on-load" % TOKEN


class OpenOutcomeTest(unittest.TestCase):
    def test_failure_starts_with_short_label_and_keeps_whole_message(self):
        argv = tm.open_argv("/Users/someone/code/sandbox/opsx-workflow", {"kind": "card", "card": {"repo": "a", "slug": "x"}})
        note = tm.open_outcome(argv, proc(argv, rc=1, err=NO_OPENER + "\n"))
        self.assertTrue(note.startswith("open-board 失敗："), note)
        self.assertIn("#token=%s&card=" % TOKEN, note)
        lines = tm.wrap(note, 79, 3)
        self.assertEqual("".join(lines), note, "80 欄寬三行內放得下整個網址")
        self.assertTrue(all(tm.width(l) <= 79 for l in lines))

    def test_multiline_stderr_becomes_one_line(self):
        argv = tm.open_argv("/r", {"kind": "card", "card": {"repo": "a", "slug": "x"}})
        note = tm.open_outcome(argv, proc(argv, rc=1, err="opsx board: server 起不來\nTraceback (most recent call last):\n  x\n"))
        self.assertNotIn("\n", note)
        self.assertEqual(tm.open_outcome(argv, proc(argv)), "網頁開了 a/x")

    def test_wrap_keeps_at_most_n_rows_from_the_start(self):
        self.assertEqual(tm.wrap("中文字ab", 4, 3), ["中文", "字ab"])
        self.assertEqual(tm.wrap("abcdefg", 2, 2), ["ab", "cd"])
        self.assertEqual(tm.wrap("", 5, 3), [""])


if __name__ == "__main__":
    unittest.main()
