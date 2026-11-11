"""herdr-board/tui_model.py：TUI 的純函式（排序、游標、範圍、輸入框、各鍵的 argv）；MainLoopTest 用假的 curses 視窗跑 tui.main 的按鍵迴圈。畫面長相不在這裡測。
驗收：specs/board-plugin/spec.md「最小 TUI」的 Scenario（herdr-board 5.2、tui-keys/tui-new-keys）。
跑法：python3 -I herdr-board/tests/test_tui.py
"""
import curses
import importlib.util
import pathlib
import subprocess
import threading
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

    def __call__(self, argv, **kw):
        self.argvs.append(argv)
        return proc(argv, out="me-1\n")


def curs_set(n):
    pass


def drive(feed, scr):
    """跑 tui.main 直到按鍵用完；回 main 跑過的外部指令。main 自己 return（被某個鍵關掉）時 assert 失敗。"""
    runs = Runs()
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


if __name__ == "__main__":
    unittest.main()
