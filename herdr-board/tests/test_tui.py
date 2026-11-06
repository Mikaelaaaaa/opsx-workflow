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

    def test_card_line_text(self):
        rows = tm.rows(DATA, done_open=False)
        ask = next(r for r in rows if r["kind"] == "card" and r["card"]["slug"] == "ask1")
        self.assertIn("等待授權", ask["text"])
        self.assertIn("push?", ask["text"])
        run = next(r for r in rows if r["kind"] == "card" and r["card"]["slug"] == "run1")
        self.assertIn("apply 3/8", run["text"])


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
