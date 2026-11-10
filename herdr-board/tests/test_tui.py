"""herdr-board/tui_model.py：TUI 的純函式（排序、游標、Enter 要做什麼）。curses 不在這裡測。
驗收：specs/board-plugin/spec.md「最小 TUI」三個 Scenario（herdr-board 5.2）。
跑法：python3 -I herdr-board/tests/test_tui.py
"""
import importlib.util
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("tui_model", HERE.parent / "tui_model.py")
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)


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


if __name__ == "__main__":
    unittest.main()
