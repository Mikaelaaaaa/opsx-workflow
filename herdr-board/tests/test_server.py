"""herdr-board/server.py：本機 server。驗收：specs/board-web/spec.md「本機 server」四個 Scenario（herdr-board 4.1）。

起一支真的 server（--port 0 隨機 port、--collect 固定 JSON），PATH 前置一個記錄參數的 opsx shim，用 urllib 打。
跑法：python3 -I herdr-board/tests/test_server.py（目錄名有連字號，不能用 -m unittest 的模組路徑），或 bash tests/run.sh（它會叫這支）。
"""
import base64
import http.client
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
SERVER = ROOT / "herdr-board" / "server.py"


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def start_server(env: dict, fixture: pathlib.Path | None, cwd: pathlib.Path | None = None) -> tuple[subprocess.Popen, str, int]:
    """起一支 server（--port 0），回 (proc, host, port)；等到 /healthz 回應。fixture 是 None 就不帶 --collect，collect 走 opsx。"""
    proc = subprocess.Popen(
        [sys.executable, "-I", str(SERVER), "--port", "0", *(["--collect", str(fixture)] if fixture else [])],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True, cwd=cwd,
    )
    line = proc.stdout.readline()
    m = re.search(r"http://(127\.0\.0\.1):(\d+)/", line)
    if not m:
        proc.kill()
        raise AssertionError("server 沒印出監聽位址：%r %s" % (line, proc.stderr.read()))
    for _ in range(50):
        try:
            urllib.request.urlopen("http://127.0.0.1:%s/healthz" % m.group(2), timeout=1); break
        except (urllib.error.URLError, ConnectionError):
            time.sleep(0.05)
    return proc, m.group(1), int(m.group(2))


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = pathlib.Path(tempfile.mkdtemp(prefix="opsx-server."))
        cls.state = cls.tmp / "state"
        cls.state.mkdir()
        cls.log = cls.tmp / "opsx.log"
        cls.fail_flag = cls.tmp / "opsx.fail"
        cls.rc_file = cls.tmp / "opsx.rc"   # 有這個檔就以檔裡的數字退出（測 sync 的退出碼 3）
        shim_dir = cls.tmp / "bin"
        shim_dir.mkdir()
        cls.env_log = cls.tmp / "env.log"
        cls.cwd_log = cls.tmp / "cwd.log"
        cls.herdr_log = cls.tmp / "herdr.log"
        cls.attached = cls.tmp / "attached"   # shim 執行當下把 --attach 的檔複製到這裡，server 回應後暫存檔已刪
        cls.attached.mkdir()
        cls.contents = cls.tmp / "attached.b64"   # 同名的檔在 attached/ 會互蓋，這裡依 --attach 順序一行一個 base64
        # server 跑的是 plugin 自己的 bin/opsx，不靠 PATH；測試用 OPSX_TEST_OPSX 指到這支假的
        shim = shim_dir / "opsx"
        shim.write_text(
            "#!/usr/bin/env bash\n"
            f'printf "%s\\n" "$*" >> "{cls.log}"\n'
            f'prev=; for a in "$@"; do if [ "$prev" = --attach ]; then cp "$a" "{cls.attached}/"; base64 < "$a" | tr -d "\\n" >> "{cls.contents}"; echo >> "{cls.contents}"; fi; prev="$a"; done\n'
            f'printf "OPSX_STATE_DIR=%s\\n" "${{OPSX_STATE_DIR:-}}" >> "{cls.env_log}"\n'
            f'pwd -P >> "{cls.cwd_log}"\n'
            f'if [ -f "{cls.fail_flag}" ]; then echo "opsx: 假的失敗" >&2; exit 2; fi\n'
            f'if [ -f "{cls.rc_file}" ]; then echo "opsx: 假的退出碼" >&2; exit "$(cat "{cls.rc_file}")"; fi\n'
            'if [ "$1" = timeline ]; then echo \'{"generated_at": "g", "last_seen": null, "events": [], "errors": []}\'; exit 0; fi\n'
            'echo "ok: $1"\n'
        )
        shim.chmod(0o755)
        herdr = shim_dir / "herdr"
        herdr.write_text("#!/usr/bin/env bash\n" f'printf "%s\\n" "$*" >> "{cls.herdr_log}"\n'
                         'if [ "$3" = "w9:p9" ]; then echo "pane not found" >&2; exit 1; fi\n'
                         'if [ "$1 $2 $3" = "agent focus gone" ]; then echo "agent not found" >&2; exit 1; fi\n'
                         'if [ "$1 $2" = "agent read" ]; then printf "line 1\\nline 2\\n"; exit 0; fi\n'
                         'echo "{}"\n')
        herdr.chmod(0o755)
        cls.open_log = cls.tmp / "open.log"
        open_shim = shim_dir / "open"
        open_shim.write_text("#!/usr/bin/env bash\n" f'printf "%s\\n" "$*" >> "{cls.open_log}"\n'
                             'if [ "$2" = "Nope" ]; then echo "Unable to find application named Nope" >&2; exit 1; fi\n')
        open_shim.chmod(0o755)
        cls.config = cls.state / "config.toml"
        cls.repo = cls.tmp / "repo"
        (cls.repo / "openspec" / "changes").mkdir(parents=True)   # --repo 只收真的 opsx repo 根
        cls.fixture = cls.tmp / "collect.json"
        cls.fixture.write_text(json.dumps({"generated_at": "t", "scopes": [], "cards": [{"slug": "x"}], "unmatched_agents": [], "errors": []}))
        env = dict(os.environ, HERDR_ENV="1", OPSX_STATE_DIR=str(cls.state), OPSX_TEST_OPSX=str(shim), PATH=f"{shim_dir}:{os.environ['PATH']}")
        cls.proc, cls.host, cls.port = start_server(env, cls.fixture)
        cls.base = "http://127.0.0.1:%d" % cls.port
        cls.token = (cls.state / "board-token").read_text().strip()

    @classmethod
    def tearDownClass(cls):
        cls.proc.kill()
        cls.proc.wait()

    def req(self, path, body=None, token=None, method=None):
        data = json.dumps(body).encode() if body is not None else None
        r = urllib.request.Request(self.base + path, data=data, method=method or ("POST" if data else "GET"))
        if data is not None:
            r.add_header("Content-Type", "application/json")
        if token:
            r.add_header("X-Opsx-Token", token)
        try:
            with urllib.request.urlopen(r, timeout=5) as resp:
                return resp.status, resp.headers.get("Content-Type", ""), resp.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.headers.get("Content-Type", ""), e.read().decode()

    def setUp(self):
        self.log.write_text("")
        self.cwd_log.write_text("")
        if self.fail_flag.exists():
            self.fail_flag.unlink()
        if self.rc_file.exists():
            self.rc_file.unlink()
        self.open_log.write_text("")
        self.herdr_log.write_text("")
        if self.config.exists():
            self.config.unlink()
        shutil.rmtree(self.attached)
        self.attached.mkdir()
        self.contents.write_text("")

    def paste_dir(self, pattern: str) -> pathlib.Path:
        """log 這一行要整行符合 pattern（`(\\S+)` 抓暫存資料夾），回暫存資料夾。"""
        line = self.log.read_text().strip()
        m = re.fullmatch(pattern, line)
        self.assertIsNotNone(m, line)
        return pathlib.Path(m.group(1))

    def test_paste_with_file(self):
        data = bytes(range(256)) * 4
        status, _, body = self.req("/api/paste", {"text": "鍵盤蓋住輸入框", "files": [{"name": "shot.png", "data": b64(data)}]}, token=self.token)
        self.assertEqual(status, 200, body)
        out = json.loads(body)
        self.assertTrue(out["ok"], out)
        self.assertIn("ok: new", out["stdout"])
        d = self.paste_dir(r"new --source me --attach (\S+)/shot\.png -- 鍵盤蓋住輸入框")
        self.assertEqual((self.attached / "shot.png").read_bytes(), data)
        self.assertFalse(d.exists(), "回應後暫存資料夾要刪掉")

    def test_paste_multiline_saves_paste_md_first(self):
        text = "第一行\nhttps://example.com/x\n第三行"
        status, _, body = self.req("/api/paste", {"text": text, "files": []}, token=self.token)
        self.assertEqual(status, 200, body)
        d = self.paste_dir(r"new --source me --attach (\S+)/paste\.md -- 第一行")
        self.assertEqual((self.attached / "paste.md").read_text(encoding="utf-8"), text)
        self.assertFalse(d.exists())
        self.log.write_text("")
        status, _, body = self.req("/api/paste", {"text": "\n  標題  \n內文", "files": [{"name": "a.txt", "data": b64(b"a")}]}, token=self.token)
        self.assertEqual(status, 200, body)
        self.paste_dir(r"new --source me --attach (\S+)/paste\.md --attach \S+/a\.txt -- 標題")

    def test_paste_single_line_with_file_has_no_paste_md(self):
        self.req("/api/paste", {"text": "  一行  \n\n", "files": [{"name": "a.txt", "data": b64(b"a")}]}, token=self.token)
        self.paste_dir(r"new --source me --attach (\S+)/a\.txt -- 一行")

    def test_paste_only_files(self):
        status, _, body = self.req("/api/paste", {"text": "", "files": [{"name": "log.txt", "data": b64(b"x")}, {"name": "b.txt", "data": ""}]}, token=self.token)
        self.assertEqual(status, 200, body)
        self.paste_dir(r"new --source me --attach (\S+)/log\.txt --attach \S+/b\.txt -- 附件：log\.txt")

    def test_paste_with_repo(self):
        r = str(self.repo)
        status, _, body = self.req("/api/paste", {"text": "x", "repo": r, "files": [{"name": "a.png", "data": b64(b"p")}]}, token=self.token)
        self.assertEqual(status, 200, body)
        self.paste_dir(r"new --source me --repo %s --attach (\S+)/a\.png -- x" % re.escape(r))
        status, _, body = self.req("/api/paste", {"text": "x", "repo": "/tmp", "files": []}, token=self.token)
        self.assertEqual(status, 400, body)

    def test_paste_same_name_twice_keeps_both(self):
        status, _, body = self.req("/api/paste", {"text": "a\nb", "files": [{"name": "paste.md", "data": b64(b"mine")}, {"name": "paste.md", "data": b64(b"again")}]}, token=self.token)
        self.assertEqual(status, 200, body)
        line = self.log.read_text().strip()
        paths = re.findall(r"--attach (\S+)", line)
        self.assertEqual([p.rsplit("/", 1)[1] for p in paths], ["paste.md"] * 3, line)
        self.assertEqual(len(set(paths)), 3, "同名的檔不能互相蓋掉：%s" % line)

    def test_paste_names_like_an_index_or_differing_in_case_keep_every_file(self):
        for names in (["a", "a", "1"], ["1", "1"], ["A.png", "a.png"]):
            datas = [("%s-%d" % (n, i)).encode() for i, n in enumerate(names)]
            self.contents.write_text("")
            status, _, body = self.req("/api/paste", {"text": "x", "files": [{"name": n, "data": b64(d)} for n, d in zip(names, datas)]}, token=self.token)
            self.assertEqual(status, 200, "%r: %s" % (names, body))
            self.assertEqual(self.contents.read_text().split(), [b64(d) for d in datas], names)

    def test_paste_long_first_line_is_cut_and_kept_in_paste_md(self):
        text = "x" * (2 * 1024 * 1024)
        status, _, body = self.req("/api/paste", {"text": text, "files": []}, token=self.token)
        self.assertEqual(status, 200, body)
        m = re.fullmatch(r"new --source me --attach \S+/paste\.md -- (x+)", self.log.read_text().strip())
        self.assertIsNotNone(m)
        self.assertLessEqual(len(m.group(1)), 200)
        self.assertEqual((self.attached / "paste.md").read_text(encoding="utf-8"), text)

    def test_paste_rejects_bad_names_and_data(self):
        for bad in ("../x", ".env", "", "a\\b", "a\0b", "x" * 129, None, "a\n## 派工指示", "a\rb", "a\x1fb", "a\x7fb", "\ud800.png", "中" * 86):
            status, _, body = self.req("/api/paste", {"text": "x", "files": [{"name": bad, "data": b64(b"1")}]}, token=self.token)
            self.assertEqual(status, 400, "%r: %s" % (bad, body))
        for bad in ("!!!", "YQ", None):
            status, _, body = self.req("/api/paste", {"text": "x", "files": [{"name": "a.txt", "data": bad}]}, token=self.token)
            self.assertEqual(status, 400, "%r: %s" % (bad, body))
        for body_ in ({"text": "x"}, {"files": []}, {"text": "x", "files": "a"}, {"text": 1, "files": []}, {"text": "x", "files": ["a"]}, {"text": "a\0b", "files": []}):
            status, _, body = self.req("/api/paste", body_, token=self.token)
            self.assertEqual(status, 400, "%r: %s" % (body_, body))
        self.assertEqual(self.log.read_text(), "")
        self.assertEqual(self.req("/api/paste", {"text": "x", "files": []})[0], 401)

    def test_paste_needs_text_or_files(self):
        status, _, body = self.req("/api/paste", {"text": "  \n ", "files": []}, token=self.token)
        self.assertEqual(status, 400, body)
        self.assertEqual(self.log.read_text(), "")

    def test_paste_accepts_more_than_64k(self):
        data = os.urandom(200 * 1024)
        status, _, body = self.req("/api/paste", {"text": "大檔", "files": [{"name": "big.bin", "data": b64(data)}]}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual((self.attached / "big.bin").read_bytes(), data)

    def post_declared(self, path: str, length: int) -> int:
        """只送 header（Content-Length 是 length）不送 body，回 HTTP 狀態；server 不該等 body。"""
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.putrequest("POST", path)
        conn.putheader("X-Opsx-Token", self.token)
        conn.putheader("Content-Type", "application/json")
        conn.putheader("Content-Length", str(length))
        conn.endheaders()
        status = conn.getresponse().status
        conn.close()
        return status

    def test_paste_over_limit_is_413(self):
        self.assertEqual(self.post_declared("/api/paste", 64 * 1024 * 1024 + 1), 413)
        self.assertEqual(self.log.read_text(), "")

    def test_other_endpoints_keep_64k_limit(self):
        self.assertEqual(self.post_declared("/api/new", 64 * 1024 + 1), 400)
        self.assertEqual(self.log.read_text(), "")

    def test_binds_loopback_only(self):
        self.assertEqual(self.host, "127.0.0.1")

    def test_index_is_html(self):
        status, ctype, body = self.req("/")
        self.assertEqual(status, 200)
        self.assertIn("text/html", ctype)
        self.assertIn("<title>", body)

    def test_dispatch_dialog_has_two_modes(self):
        _, _, body = self.req("/")
        self.assertEqual(re.findall(r'name="md" value="([a-z]+)"', body), ["interactive", "autopilot"])

    def test_token_is_generated_and_required(self):
        self.assertGreaterEqual(len(self.token), 32)
        status, _, _ = self.req("/api/collect")
        self.assertEqual(status, 401)
        status, _, _ = self.req("/api/collect", token="wrong-" + self.token)
        self.assertEqual(status, 401)

    def test_collect_returns_fixture(self):
        status, ctype, body = self.req("/api/collect", token=self.token)
        self.assertEqual(status, 200)
        self.assertIn("application/json", ctype)
        self.assertEqual(json.loads(body)["cards"][0]["slug"], "x")
        self.assertEqual(self.log.read_text(), "", "--collect 給了檔就不呼叫 opsx collect")

    def test_answer_forwards_to_opsx(self):
        r = str(self.repo)
        status, _, body = self.req("/api/answer", {"slug": "x", "gate": "g1", "grant": "repo", "text": "允許", "repo": r}, token=self.token)
        self.assertEqual(status, 200)
        out = json.loads(body)
        self.assertTrue(out["ok"], out)
        self.assertEqual(self.log.read_text().strip(), "answer x --gate g1 --grant repo --repo %s -- 允許" % r)
        self.assertIn("ok: answer", out["stdout"])

    def test_answer_forwards_sub(self):
        status, _, body = self.req("/api/answer", {"slug": "bt", "sub": "as", "gate": "g1", "text": "ok"}, token=self.token)
        self.assertEqual(status, 200)
        self.assertTrue(json.loads(body)["ok"], body)
        self.assertEqual(self.log.read_text().strip(), "answer bt --sub as --gate g1 -- ok")

    def test_answer_rejects_bad_sub(self):
        status, _, _ = self.req("/api/answer", {"slug": "bt", "sub": "../x", "gate": "g1", "text": "ok"}, token=self.token)
        self.assertEqual(status, 400)
        self.assertEqual(self.log.read_text(), "")

    def test_merge_and_stop_and_dispatch(self):
        r = str(self.repo)
        self.req("/api/merge", {"slug": "x", "repo": r}, token=self.token)
        self.req("/api/stop", {"slug": "x"}, token=self.token)
        self.req("/api/dispatch", {"slug": "x", "agent": "claude", "model": "claude-opus-5-5", "mode": "autopilot", "kind": "dev", "repo": r}, token=self.token)
        lines = self.log.read_text().strip().split("\n")
        self.assertEqual(lines[0], "merge x --repo %s" % r)
        self.assertEqual(lines[1], "stop x")
        self.assertEqual(lines[2], "dispatch x --agent claude --model claude-opus-5-5 --mode autopilot --kind dev --repo %s" % r)

    def test_new_without_and_with_repo(self):
        r = str(self.repo)
        status, _, body = self.req("/api/new", {"text": "試試看"}, token=self.token)
        self.assertEqual(status, 200, body)
        status, _, body = self.req("/api/new", {"text": "試試看", "repo": r}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.log.read_text().strip().split("\n"), ["new --source me -- 試試看", "new --source me --repo %s -- 試試看" % r])

    def test_new_and_paste_run_outside_any_worktree(self):
        # server 可能從 agent worktree 啟動；opsx new 在 dispatch 的 worktree 裡會拒絕 --source me，所以看板的 new 與 paste 要在 state 目錄跑
        status, _, body = self.req("/api/new", {"text": "試試看"}, token=self.token)
        self.assertEqual(status, 200, body)
        status, _, body = self.req("/api/paste", {"text": "貼上", "files": []}, token=self.token)
        self.assertEqual(status, 200, body)
        want = str(self.state.resolve())
        self.assertEqual(self.cwd_log.read_text().split("\n")[:-1], [want, want])

    def test_relative_state_dir_reaches_opsx_as_absolute_path(self):
        # opsx new 的 cwd 是 state 目錄；state 給相對路徑時 OPSX_STATE_DIR 要先解成絕對路徑，不然 opsx 會在 state 底下再解析一次
        base = self.tmp / "rel"
        (base / "st").mkdir(parents=True)
        env = dict(os.environ, HERDR_ENV="1", OPSX_STATE_DIR="st", OPSX_TEST_OPSX=str(self.tmp / "bin" / "opsx"), PATH=f"{self.tmp / 'bin'}:{os.environ['PATH']}")
        proc, _, port = start_server(env, self.fixture, cwd=base)
        try:
            token = (base / "st" / "board-token").read_text().strip()
            r = urllib.request.Request("http://127.0.0.1:%d/api/new" % port, data=json.dumps({"text": "相對 state"}).encode(), method="POST")
            r.add_header("Content-Type", "application/json")
            r.add_header("X-Opsx-Token", token)
            with urllib.request.urlopen(r, timeout=5) as resp:
                self.assertEqual(resp.status, 200)
        finally:
            proc.kill()
            proc.wait()
        self.assertEqual(self.env_log.read_text().split("\n")[-2], "OPSX_STATE_DIR=%s" % (base / "st").resolve())

    def test_new_rejects_empty_or_multiline_text(self):
        for text in ("", "a\nb"):
            status, _, body = self.req("/api/new", {"text": text}, token=self.token)
            self.assertEqual(status, 400, body)
        self.assertEqual(self.log.read_text(), "")

    def test_note_forwards_to_opsx(self):
        r = str(self.repo)
        status, _, body = self.req("/api/note", {"slug": "x", "text": "先跑 lint", "repo": r}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertTrue(json.loads(body)["ok"], body)
        status, _, body = self.req("/api/note", {"slug": "x", "text": "-v 也要跑"}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.log.read_text().strip().split("\n"), ["note x --repo %s -- 先跑 lint" % r, "note x -- -v 也要跑"])

    def test_note_rejects_missing_empty_or_multiline_text(self):
        for body_ in ({"slug": "x"}, {"slug": "x", "text": "   "}, {"slug": "x", "text": "第一行\nsource: evil"}, {"text": "沒有 slug"}):
            status, _, body = self.req("/api/note", body_, token=self.token)
            self.assertEqual(status, 400, (body_, body))
        self.assertEqual(self.log.read_text(), "")

    def test_dispatch_forwards_note(self):
        self.req("/api/dispatch", {"slug": "x", "mode": "autopilot", "note": "先跑 lint"}, token=self.token)
        self.req("/api/dispatch", {"slug": "x", "mode": "autopilot", "note": ""}, token=self.token)
        self.req("/api/dispatch", {"slug": "x", "mode": "autopilot"}, token=self.token)
        self.assertEqual(self.log.read_text().strip().split("\n"),
                         ["dispatch x --mode autopilot --note 先跑 lint", "dispatch x --mode autopilot", "dispatch x --mode autopilot"])

    def test_dispatch_rejects_multiline_or_huge_note(self):
        for note in ("第一行\nsource: evil", "a\rb", "a\0b", "x" * 2001):
            status, _, body = self.req("/api/dispatch", {"slug": "x", "note": note}, token=self.token)
            self.assertEqual(status, 400, body)
        self.assertEqual(self.log.read_text(), "")

    def test_file_needs_slug_and_repo(self):
        r = str(self.repo)
        status, _, body = self.req("/api/file", {"slug": "me-1", "repo": r}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.log.read_text().strip(), "file me-1 --repo %s" % r)
        status, _, body = self.req("/api/file", {"slug": "me-1"}, token=self.token)
        self.assertEqual(status, 400, body)

    def test_file_then_drop(self):
        r = str(self.repo)
        self.req("/api/file", {"slug": "me-1", "repo": r}, token=self.token)
        status, _, body = self.req("/api/drop", {"slug": "x", "repo": r, "text": "重複"}, token=self.token)
        self.assertEqual(status, 200, body)
        status, _, body = self.req("/api/drop", {"slug": "me-2", "text": "不需要"}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.log.read_text().strip().split("\n"),
                         ["file me-1 --repo %s" % r, "drop x --repo %s -- 重複" % r, "drop me-2 -- 不需要"])
        status, _, body = self.req("/api/drop", {"slug": "x", "repo": r}, token=self.token)
        self.assertEqual(status, 400, "理由必填：%s" % body)

    def test_merge_card_forwards_to_opsx(self):
        # specs/board-web「server 轉呼叫 merge-card」
        r = str(self.repo)
        status, _, body = self.req("/api/merge-card", {"slug": "x", "into": "y", "repo": r}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertTrue(json.loads(body)["ok"], body)
        self.assertEqual(self.log.read_text().strip(), "merge-card x --into y --repo %s" % r)

    def test_merge_card_rejects_bad_fields(self):
        # specs/board-web「merge-card 缺 into」
        r = str(self.repo)
        for b in ({"slug": "x", "repo": r}, {"slug": "x", "into": "../y", "repo": r},
                  {"slug": "x", "into": "a/y", "repo": r}, {"slug": "x", "into": ""},
                  {"slug": "x", "into": "y"}, {"into": "y", "repo": r},
                  {"slug": "x", "into": "y", "repo": "/nonexistent-opsx-repo"}):
            status, _, body = self.req("/api/merge-card", b, token=self.token)
            self.assertEqual(status, 400, "%r: %s" % (b, body))
        self.assertEqual(self.log.read_text(), "")

    def test_sync_with_and_without_source(self):
        status, _, body = self.req("/api/sync", {}, token=self.token)
        self.assertEqual(status, 200, body)
        status, _, body = self.req("/api/sync", {"source": "debt"}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.log.read_text().strip().split("\n"), ["sync", "sync --source debt"])

    def test_sync_obsidian(self):
        status, _, body = self.req("/api/sync", {"source": "obsidian"}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.log.read_text().strip().split("\n"), ["sync --source obsidian"])

    def test_sync_rejects_unknown_source(self):
        status, _, body = self.req("/api/sync", {"source": "customer"}, token=self.token)
        self.assertEqual(status, 400, body)
        self.assertEqual(self.log.read_text(), "")

    def test_sync_in_progress_is_409(self):
        self.rc_file.write_text("3")
        status, _, body = self.req("/api/sync", {}, token=self.token)
        self.assertEqual(status, 409, body)
        self.rc_file.write_text("3")
        status, _, body = self.req("/api/merge", {"slug": "x"}, token=self.token)
        self.assertEqual(status, 200, "只有 sync 的退出碼 3 是 409：%s" % body)

    def test_priority_forwards_to_opsx(self):
        # specs/board-web「改等級轉呼叫 opsx」
        r = str(self.repo)
        status, _, body = self.req("/api/priority", {"repo": r, "slug": "card-a", "level": "P0", "reason": "客戶明天上線"}, token=self.token)
        self.assertEqual(status, 200, body)
        out = json.loads(body)
        self.assertTrue(out["ok"], out)
        self.assertEqual(self.log.read_text().strip(), "priority card-a --set P0 --reason 客戶明天上線 --repo %s" % r)
        self.assertIn("ok: priority", out["stdout"])

    def test_priority_needs_reason(self):
        # specs/board-web「沒有理由」
        for reason in ("", "   ", None):
            status, _, body = self.req("/api/priority", {"repo": str(self.repo), "slug": "card-a", "level": "P0", "reason": reason}, token=self.token)
            self.assertEqual(status, 400, "%r: %s" % (reason, body))
        self.assertEqual(self.log.read_text(), "")

    def test_priority_rejects_unknown_level(self):
        # specs/board-web「不合格的等級」
        for level in ("P3", "p0", "", None):
            status, _, body = self.req("/api/priority", {"repo": str(self.repo), "slug": "card-a", "level": level, "reason": "x"}, token=self.token)
            self.assertEqual(status, 400, "%r: %s" % (level, body))
        self.assertEqual(self.log.read_text(), "")

    def test_priority_needs_token_and_real_repo(self):
        status, _, _ = self.req("/api/priority", {"repo": str(self.repo), "slug": "card-a", "level": "P0", "reason": "x"})
        self.assertEqual(status, 401)
        for repo in ("/tmp", None):
            status, _, body = self.req("/api/priority", {"repo": repo, "slug": "card-a", "level": "P0", "reason": "x"}, token=self.token)
            self.assertEqual(status, 400, "%r: %s" % (repo, body))
        self.assertEqual(self.log.read_text(), "")

    def test_index_has_the_orphan_row_and_its_buttons(self):
        _, _, body = self.req("/")
        for needle in ("孤兒 pane", 'data-act="reap"', 'data-act="reap-all"', "api.post('reap'"):
            self.assertIn(needle, body)

    def test_reap_one_pane_or_all(self):
        status, _, body = self.req("/api/reap", {"pane": "w1:p3"}, token=self.token)
        self.assertEqual(status, 200, body)
        status, _, body = self.req("/api/reap", {}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.log.read_text().strip().split("\n"), ["reap --pane w1:p3", "reap"])

    def test_reap_rejects_a_pane_that_looks_like_a_flag(self):
        status, _, body = self.req("/api/reap", {"pane": "--all"}, token=self.token)
        self.assertEqual(status, 400, body)
        self.assertEqual(self.log.read_text(), "")

    def test_reap_not_an_orphan_is_422(self):
        self.rc_file.write_text("2")
        status, _, body = self.req("/api/reap", {"pane": "w9:p1"}, token=self.token)
        self.assertEqual(status, 422, body)
        self.rc_file.write_text("2")
        status, _, body = self.req("/api/merge", {"slug": "x"}, token=self.token)
        self.assertEqual(status, 200, "只有 reap 的退出碼 2 是 422：%s" % body)

    def test_repo_must_be_an_opsx_root_and_text_single_line(self):
        status, _, body = self.req("/api/merge", {"slug": "x", "repo": "/tmp"}, token=self.token)
        self.assertEqual(status, 400, body)
        status, _, body = self.req("/api/answer", {"slug": "x", "gate": "g1", "text": "ok\nstatus: open"}, token=self.token)
        self.assertEqual(status, 400, body)
        self.assertEqual(self.log.read_text(), "")

    def test_state_dir_reaches_opsx(self):
        self.req("/api/stop", {"slug": "x"}, token=self.token)
        self.assertIn("OPSX_STATE_DIR=%s" % self.state, self.env_log.read_text())

    def test_collect_is_cached_and_single_flight(self):
        for _ in range(3):
            status, _, _ = self.req("/api/collect", token=self.token)
            self.assertEqual(status, 200)
        self.assertEqual(self.log.read_text(), "", "--collect 固定檔時不叫 opsx")

    def test_log_forwards_to_timeline(self):
        status, _, body = self.req("/api/log", token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(json.loads(body)["events"], [])
        self.assertEqual(self.log.read_text().strip(), "timeline")
        self.log.write_text("")
        status, _, body = self.req("/api/log?since=2026-11-06T09%3A00%3A00%2B08%3A00", token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.log.read_text().strip(), "timeline --since 2026-11-06T09:00:00+08:00")

    def test_log_needs_token_and_a_real_since(self):
        status, _, _ = self.req("/api/log")
        self.assertEqual(status, 401)
        status, _, body = self.req("/api/log?since=%E6%98%A8%E5%A4%A9", token=self.token)
        self.assertEqual(status, 400, body)
        status, _, body = self.req("/api/log?since=2026-11-06T09:00:00", token=self.token)
        self.assertEqual(status, 400, "沒有時區的時間要拒絕：%s" % body)
        self.assertEqual(self.log.read_text(), "")

    def test_seen_writes_last_seen(self):
        status, _, body = self.req("/api/seen", {"at": "2026-11-06T13:00:00+08:00"}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertTrue(json.loads(body)["ok"])
        self.assertEqual((self.state / "last-seen").read_text().strip(), "2026-11-06T13:00:00+08:00")

    def test_seen_rejects_bad_time_and_needs_token(self):
        (self.state / "last-seen").write_text("2026-11-06T09:00:00+08:00\n")
        for bad in ("昨天", "2026-11-06T13:00:00", "", None):
            status, _, body = self.req("/api/seen", {"at": bad}, token=self.token)
            self.assertEqual(status, 400, "%r: %s" % (bad, body))
        status, _, _ = self.req("/api/seen", {"at": "2026-11-06T13:00:00+08:00"})
        self.assertEqual(status, 401)
        self.assertEqual((self.state / "last-seen").read_text().strip(), "2026-11-06T09:00:00+08:00")

    def test_output_reads_agent_terminal(self):
        self.herdr_log.write_text("")
        status, _, body = self.req("/api/output?pane=w5%3ApH", token=self.token)
        self.assertEqual(status, 200, body)
        out = json.loads(body)
        self.assertEqual((out["ok"], out["text"]), (True, "line 1\nline 2\n"), out)
        self.assertEqual(self.herdr_log.read_text().strip(), "agent read w5:pH --lines 10 --format text")

    def test_output_rejects_bad_pane_and_reports_herdr_failure(self):
        self.herdr_log.write_text("")
        for bad in ("w1;rm", "", "w1:p2%20--lines%201000", "--help", "-x"):
            status, _, body = self.req("/api/output?pane=" + bad, token=self.token)
            self.assertEqual(status, 400, "%r: %s" % (bad, body))
        status, _, _ = self.req("/api/output")
        self.assertEqual(status, 401)
        self.assertEqual(self.herdr_log.read_text(), "", "壞參數不能叫到 herdr")
        status, _, body = self.req("/api/output?pane=w9%3Ap9", token=self.token)
        self.assertEqual(status, 200, body)
        out = json.loads(body)
        self.assertFalse(out["ok"])
        self.assertIn("pane not found", out["error"])

    def test_focus_runs_herdr(self):
        status, _, body = self.req("/api/focus", {"agent": "retry-backoff"}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.herdr_log.read_text().strip(), "agent focus retry-backoff")
        status, _, _ = self.req("/api/focus", {"agent": "retry-backoff; rm -rf /"}, token=self.token)
        self.assertEqual(status, 400)
        status, _, _ = self.req("/api/focus", {"pane": "w1:p4"}, token=self.token)   # 舊欄位：herdr pane focus 不收 id，拒絕
        self.assertEqual(status, 400)

    def focus(self, agent="retry-backoff"):
        status, _, body = self.req("/api/focus", {"agent": agent}, token=self.token)
        self.assertEqual(status, 200, body)
        return json.loads(body)

    def test_focus_raises_terminal_app(self):
        self.config.write_text('terminal_app = "Warp"\n')
        out = self.focus()
        self.assertTrue(out["ok"])
        self.assertEqual(self.open_log.read_text().strip(), "-a Warp")
        self.assertNotIn("hint", out)

    def test_focus_without_terminal_app_hints(self):
        out = self.focus()
        self.assertTrue(out["ok"])
        self.assertEqual(self.open_log.read_text(), "", "沒設就不能叫 open")
        self.assertIn("請切到", out["hint"])
        self.assertIn("config.toml", out["hint"])

    def test_focus_app_launch_fails_hints(self):
        self.config.write_text('terminal_app = "Nope"\n')
        out = self.focus()
        self.assertTrue(out["ok"], "ok 只反映 herdr")
        self.assertIn("請切到 Nope", out["hint"])
        self.assertIn("Unable to find application", out["hint"])

    def test_focus_broken_config_hints(self):
        self.config.write_text("terminal_app = \n")
        out = self.focus()
        self.assertTrue(out["ok"])
        self.assertEqual(self.open_log.read_text(), "")
        self.assertIn("config.toml", out["hint"])
        self.assertIn("壞", out["hint"])

    def test_focus_unreadable_config_hints(self):
        self.config.write_bytes(b"\xff\xfe")   # 不是 UTF-8
        out = self.focus()
        self.assertTrue(out["ok"])
        self.assertIn("config.toml", out["hint"])
        self.config.unlink()
        self.config.mkdir()   # 是目錄：read_text 丟 IsADirectoryError
        try:
            out = self.focus()
        finally:
            self.config.rmdir()
        self.assertTrue(out["ok"])
        self.assertIn("config.toml", out["hint"])
        self.assertEqual(self.open_log.read_text(), "")

    def test_focus_config_without_usable_terminal_app_hints(self):
        for text in ('# terminal_app = "Warp"\n', 'other = 1\n', 'terminal_app = ""\n', 'terminal_app = 1\n', 'terminal_app = "War\\u0000p"\n'):
            self.config.write_text(text)
            out = self.focus()
            self.assertTrue(out["ok"], text)
            self.assertIn("請切到", out["hint"], text)
            self.assertEqual(self.open_log.read_text(), "", text)

    def test_focus_herdr_failure_does_not_raise_app(self):
        self.config.write_text('terminal_app = "Warp"\n')
        out = self.focus("gone")
        self.assertFalse(out["ok"])
        self.assertEqual(self.open_log.read_text(), "", "herdr 失敗不叫 open")

    def test_opsx_failure_is_reported_not_500(self):
        self.fail_flag.write_text("1")
        status, _, body = self.req("/api/merge", {"slug": "x"}, token=self.token)
        self.assertEqual(status, 200)
        out = json.loads(body)
        self.assertFalse(out["ok"])
        self.assertIn("假的失敗", out["stderr"])

    def test_post_needs_token_and_valid_slug(self):
        status, _, _ = self.req("/api/merge", {"slug": "x"})
        self.assertEqual(status, 401)
        status, _, body = self.req("/api/merge", {"slug": "../etc"}, token=self.token)
        self.assertEqual(status, 400, body)
        self.assertEqual(self.log.read_text(), "")
        status, _, _ = self.req("/api/answer", {"slug": "x", "text": "沒有 gate"}, token=self.token)
        self.assertEqual(status, 400)

    def test_unknown_action_404(self):
        status, _, _ = self.req("/api/nuke", {"slug": "x"}, token=self.token)
        self.assertEqual(status, 404)
        status, _, _ = self.req("/api/collect", {"slug": "x"}, token=self.token)
        self.assertEqual(status, 405)

    def test_healthz_needs_no_token(self):
        status, _, body = self.req("/healthz")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["ok"], True)


class NoHerdrTest(unittest.TestCase):
    """server 不在 herdr pane 裡（HERDR_ENV 沒設）：最後輸出照樣叫 herdr（specs/board-log「server 不在 herdr pane 裡」）。"""

    @classmethod
    def setUpClass(cls):
        cls.tmp = pathlib.Path(tempfile.mkdtemp(prefix="opsx-server-noherdr."))
        state = cls.tmp / "state"
        state.mkdir()
        shim_dir = cls.tmp / "bin"
        shim_dir.mkdir()
        cls.herdr_log = cls.tmp / "herdr.log"
        herdr = shim_dir / "herdr"
        herdr.write_text("#!/usr/bin/env bash\n" f'printf "%s\\n" "$*" >> "{cls.herdr_log}"\n' 'printf "line\\n"\n')
        herdr.chmod(0o755)
        fixture = cls.tmp / "collect.json"
        fixture.write_text(json.dumps({"generated_at": "t", "scopes": [], "cards": [], "unmatched_agents": [], "errors": []}))
        env = {k: v for k, v in os.environ.items() if k != "HERDR_ENV"}
        env.update(OPSX_STATE_DIR=str(state), PATH=f"{shim_dir}:{os.environ['PATH']}")
        cls.proc, _, port = start_server(env, fixture)
        cls.base = "http://127.0.0.1:%d" % port
        cls.token = (state / "board-token").read_text().strip()

    @classmethod
    def tearDownClass(cls):
        cls.proc.kill()
        cls.proc.wait()

    def test_output_outside_herdr(self):
        r = urllib.request.Request(self.base + "/api/output?pane=w5%3ApH")
        r.add_header("X-Opsx-Token", self.token)
        with urllib.request.urlopen(r, timeout=5) as resp:
            self.assertEqual(resp.status, 200)
            out = json.loads(resp.read().decode())
        self.assertTrue(out["ok"], out)
        self.assertEqual(out["text"], "line\n")
        self.assertIn("agent read w5:pH --lines 10 --format text", self.herdr_log.read_text())


class CacheInvalidationTest(unittest.TestCase):
    """不帶 --collect：動作後的 collect 不用舊快取（specs/board-web「動作後的 collect 不用舊快取」）。

    每個測試起一支新 server，快取從空的開始。shim 每次 collect 開始時記一行到 collect.begun、結束時記一行到 collect.log；
    collect 一開始就建 collect.started（測試等它，不靠固定的 sleep 猜 server 什麼時候開始跑）；
    有 collect.sleep 檔就先睡檔裡的秒數；有 collect.rc 檔就往 stderr 寫一行、以檔裡的退出碼結束；
    有 collect.out 檔就印它，沒有就印固定的空看板；有 opsx.fail 檔就讓 collect 以外的子命令退出 2；
    有 action.sleep 檔就讓 collect 以外的子命令先建 action.started、再睡檔裡的秒數。
    """

    @classmethod
    def setUpClass(cls):
        cls.tmp = pathlib.Path(tempfile.mkdtemp(prefix="opsx-server-cache."))
        cls.state = cls.tmp / "state"
        cls.state.mkdir()
        cls.collect_log = cls.tmp / "collect.log"
        cls.sleep_file = cls.tmp / "collect.sleep"
        cls.started = cls.tmp / "collect.started"
        cls.begun_log = cls.tmp / "collect.begun"
        cls.rc_file = cls.tmp / "collect.rc"
        cls.out_file = cls.tmp / "collect.out"
        cls.bad_bytes = cls.tmp / "collect.bad"
        cls.fail_flag = cls.tmp / "opsx.fail"
        cls.action_sleep = cls.tmp / "action.sleep"
        cls.action_started = cls.tmp / "action.started"
        cls.repo = cls.tmp / "repo"
        (cls.repo / "openspec" / "changes").mkdir(parents=True)
        shim = cls.tmp / "opsx"
        shim.write_text(
            "#!/usr/bin/env bash\n"
            'if [ "$1" = collect ]; then\n'
            f'  echo collect >> "{cls.begun_log}"\n'
            f'  : > "{cls.started}"\n'
            f'  if [ -f "{cls.sleep_file}" ]; then sleep "$(cat "{cls.sleep_file}")"; fi\n'
            f'  echo collect >> "{cls.collect_log}"\n'
            f'  if [ -f "{cls.bad_bytes}" ]; then printf \'collect: \\377 壞掉的位元組\\n\' >&2; exit 1; fi\n'
            f'  if [ -f "{cls.rc_file}" ]; then echo "collect: 假的失敗" >&2; exit "$(cat "{cls.rc_file}")"; fi\n'
            f'  if [ -f "{cls.out_file}" ]; then cat "{cls.out_file}"; exit 0; fi\n'
            '  echo \'{"generated_at": "g", "scopes": [], "cards": [], "unmatched_agents": [], "errors": []}\'\n'
            "  exit 0\n"
            "fi\n"
            f'if [ -f "{cls.action_sleep}" ]; then : > "{cls.action_started}"; sleep "$(cat "{cls.action_sleep}")"; fi\n'
            f'if [ -f "{cls.fail_flag}" ]; then echo "opsx: 假的失敗" >&2; exit 2; fi\n'
            'echo "ok: $1"\n'
        )
        shim.chmod(0o755)
        cls.env = dict(os.environ, OPSX_STATE_DIR=str(cls.state), OPSX_TEST_OPSX=str(shim))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def setUp(self):
        self.collect_log.write_text("")
        self.begun_log.write_text("")
        for f in (self.sleep_file, self.fail_flag, self.started, self.action_sleep, self.action_started,
                  self.rc_file, self.out_file, self.bad_bytes):
            if f.exists():
                f.unlink()
        self.proc, _, port = start_server(self.env, None)
        self.base = "http://127.0.0.1:%d" % port
        self.token = (self.state / "board-token").read_text().strip()

    def tearDown(self):
        self.proc.kill()
        self.proc.wait()
        self.proc.stdout.close()
        self.proc.stderr.close()
        # collect 跑在自己的 session，server 被殺後還會跑完；等它寫完 log，免得算進下一個測試
        self.wait_lines(self.collect_log, self.begun())

    def req(self, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        r = urllib.request.Request(self.base + path, data=data, method="POST" if data else "GET")
        r.add_header("Content-Type", "application/json")
        r.add_header("X-Opsx-Token", self.token)
        try:
            with urllib.request.urlopen(r, timeout=10) as resp:
                return resp.status
        except urllib.error.HTTPError as e:
            return e.code

    def collects(self) -> int:
        return len(self.collect_log.read_text().splitlines())

    def get_into(self, results: list) -> None:
        results.append(self.req("/api/collect"))

    def stop_into(self, results: list) -> None:
        results.append(self.req("/api/stop", {"slug": "x"}))

    def wait_for(self, path: pathlib.Path) -> None:
        deadline = time.monotonic() + 10
        while not path.exists():
            if time.monotonic() > deadline:
                raise AssertionError("10 秒內沒等到 %s" % path)
            time.sleep(0.02)

    def wait_lines(self, path: pathlib.Path, n: int) -> None:
        deadline = time.monotonic() + 10
        while len(path.read_text().splitlines()) < n:
            if time.monotonic() > deadline:
                raise AssertionError("10 秒內 %s 沒到 %d 行" % (path, n))
            time.sleep(0.02)

    def get_json(self) -> tuple[int, dict, float]:
        """GET /api/collect，回 (status, body, 花了幾秒)。"""
        r = urllib.request.Request(self.base + "/api/collect")
        r.add_header("X-Opsx-Token", self.token)
        t0 = time.monotonic()
        try:
            with urllib.request.urlopen(r, timeout=10) as resp:
                return resp.status, json.loads(resp.read().decode()), time.monotonic() - t0
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode()), time.monotonic() - t0

    def get_until_changed(self, old: dict) -> tuple[int, dict]:
        """shim 寫完 log 到 server 寫進快取之間有一小段，輪詢到回的內容不再是 old。"""
        deadline = time.monotonic() + 10
        while True:
            status, body, _ = self.get_json()
            if body != old:
                return status, body
            if time.monotonic() > deadline:
                raise AssertionError("10 秒內 GET 一直回 %r" % old)
            time.sleep(0.02)

    def begun(self) -> int:
        return len(self.begun_log.read_text().splitlines())

    def test_first_get_waits_for_collect(self):
        self.sleep_file.write_text("1")
        self.out_file.write_text('{"n": 1}')
        status, body, took = self.get_json()
        self.assertEqual((status, body), (200, {"n": 1}))
        self.assertGreaterEqual(took, 0.9, "server 還沒有結果時，第一個 GET 要等 collect 跑完")

    def test_later_get_serves_last_result_and_refreshes_in_background(self):
        self.out_file.write_text('{"n": 1}')
        self.assertEqual(self.get_json()[:2], (200, {"n": 1}))
        time.sleep(3.2)   # 超過 CACHE_S
        self.sleep_file.write_text("1")
        self.out_file.write_text('{"n": 2}')
        status, body, took = self.get_json()
        self.assertEqual((status, body), (200, {"n": 1}), "有結果可回就回上一份，不等 collect")
        self.assertLess(took, 0.5)
        self.wait_lines(self.begun_log, 2)
        for _ in range(5):
            status, body, took = self.get_json()
            self.assertEqual((status, body), (200, {"n": 1}))
            self.assertLess(took, 0.5)
        self.assertEqual(self.begun(), 2, "背景刷新同一時間只跑一支")
        self.assertEqual(self.get_until_changed({"n": 1}), (200, {"n": 2}), "背景跑完後的 GET 拿到新結果")
        self.assertEqual(self.begun(), 2)

    def test_failed_background_collect_is_502_on_next_get(self):
        status, ok_body, _ = self.get_json()
        self.assertEqual(status, 200)
        time.sleep(3.2)
        self.rc_file.write_text("1")
        self.assertEqual(self.get_json()[:2], (200, ok_body), "背景刷新開跑時先回上一份成功的結果")
        status, body = self.get_until_changed(ok_body)
        self.assertEqual(status, 502, "背景刷新失敗後不能再回之前那份成功的結果")
        self.assertIn("error", body)
        self.assertIn("collect: 假的失敗", body["stderr"])

    def test_collect_output_that_is_not_utf8_is_502_and_does_not_wedge(self):
        self.bad_bytes.write_text("")
        status, body, _ = self.get_json()
        self.assertEqual(status, 502, "collect 的輸出解不開也要回錯誤，不能讓 GET 卡住")
        self.assertIn("壞掉的位元組", body["stderr"])
        self.bad_bytes.unlink()
        self.out_file.write_text('{"n": 1}')
        self.assertEqual(self.req("/api/stop", {"slug": "x"}), 200)
        self.assertEqual(self.get_json()[:2], (200, {"n": 1}), "之後的 collect 照常跑，動作後的 GET 不卡")

    def test_no_requests_no_collect(self):
        self.assertEqual(self.get_json()[0], 200)
        time.sleep(10)
        self.assertEqual(self.begun(), 1, "沒有請求時 server 不自己跑 collect")

    def test_action_starts_a_collect_in_background(self):
        self.assertEqual(self.get_json()[0], 200)
        self.assertEqual(self.req("/api/stop", {"slug": "x"}), 200)
        self.wait_lines(self.begun_log, 2)

    def test_action_during_a_collect_starts_another_after_it(self):
        self.sleep_file.write_text("1")
        results = []
        t = threading.Thread(target=self.get_into, args=(results,))
        t.start()
        self.wait_for(self.started)
        self.assertEqual(self.req("/api/stop", {"slug": "x"}), 200)
        t.join()
        self.assertEqual(results, [200])
        self.wait_lines(self.begun_log, 2)

    def test_get_right_after_action_gets_post_action_result(self):
        self.out_file.write_text('{"n": 1}')
        self.assertEqual(self.get_json()[:2], (200, {"n": 1}))
        self.out_file.write_text('{"n": 2}')
        self.assertEqual(self.req("/api/stop", {"slug": "x"}), 200)
        self.assertEqual(self.get_json()[:2], (200, {"n": 2}))

    def test_get_after_action_reruns_collect(self):
        self.assertEqual(self.req("/api/collect"), 200)
        self.assertEqual(self.req("/api/collect"), 200)
        self.assertEqual(self.collects(), 1, "沒有動作的 GET 共用快取")
        self.assertEqual(self.req("/api/stop", {"slug": "x"}), 200)
        self.assertEqual(self.req("/api/collect"), 200)
        self.assertEqual(self.collects(), 2)

    def test_failed_opsx_still_invalidates(self):
        self.req("/api/collect")
        self.fail_flag.write_text("1")
        self.assertEqual(self.req("/api/answer", {"slug": "x", "gate": "g1", "text": "好"}), 200)
        self.req("/api/collect")
        self.assertEqual(self.collects(), 2)

    def test_priority_invalidates(self):
        self.req("/api/collect")
        body = {"slug": "x", "level": "P1", "reason": "測試", "repo": str(self.repo)}
        self.assertEqual(self.req("/api/priority", body), 200)
        self.req("/api/collect")
        self.assertEqual(self.collects(), 2)

    def test_paste_invalidates(self):
        self.req("/api/collect")
        self.assertEqual(self.req("/api/paste", {"text": "第一行\n第二行", "files": []}), 200)
        self.req("/api/collect")
        self.assertEqual(self.collects(), 2, "貼上建卡也是動作，之後的 GET 要重跑 collect")

    def test_validation_failure_does_not_invalidate(self):
        self.req("/api/collect")
        self.assertEqual(self.req("/api/note", {"slug": "x"}), 400)
        self.assertEqual(self.req("/api/priority", {"slug": "x", "level": "P9"}), 400)
        self.req("/api/collect")
        self.assertEqual(self.collects(), 1)

    def test_seen_does_not_invalidate(self):
        self.req("/api/collect")
        self.assertEqual(self.req("/api/seen", {"at": "2026-11-10T00:00:00+08:00"}), 200)
        self.req("/api/collect")
        self.assertEqual(self.collects(), 1)

    def test_collect_started_before_action_is_not_fresh_cache(self):
        self.sleep_file.write_text("1")
        results = []
        t = threading.Thread(target=self.get_into, args=(results,))
        t.start()
        self.wait_for(self.started)
        self.assertEqual(self.req("/api/stop", {"slug": "x"}), 200)
        t.join()
        self.assertEqual(results, [200], "動作前送出的 GET 照樣拿到它等的那次結果")
        self.assertEqual(self.collects(), 1)
        self.sleep_file.unlink()
        self.req("/api/collect")
        self.assertEqual(self.collects(), 2, "第二個 GET 要重跑，不能拿動作前開始的那次")

    def test_collect_started_during_action_is_not_fresh_cache(self):
        # 作廢時間點要在 opsx 跑完之後記：動作跑到一半開始的 collect 可能還沒看到動作寫的檔
        self.action_sleep.write_text("1")
        results = []
        t = threading.Thread(target=self.stop_into, args=(results,))
        t.start()
        self.wait_for(self.action_started)
        self.assertEqual(self.req("/api/collect"), 200)
        self.assertEqual(self.collects(), 1, "動作進行中的 GET 跑了一次 collect")
        t.join()
        self.assertEqual(results, [200])
        self.req("/api/collect")
        self.assertEqual(self.collects(), 2, "動作結束後的 GET 要重跑，不能拿動作進行中開始的那次")


if __name__ == "__main__":
    unittest.main()
