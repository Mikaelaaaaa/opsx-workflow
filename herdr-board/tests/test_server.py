"""herdr-board/server.py：本機 server。驗收：specs/board-web/spec.md「本機 server」四個 Scenario（herdr-board 4.1）。

起一支真的 server（--port 0 隨機 port、--collect 固定 JSON），PATH 前置一個記錄參數的 opsx shim，用 urllib 打。
跑法：python3 -I herdr-board/tests/test_server.py（目錄名有連字號，不能用 -m unittest 的模組路徑），或 bash tests/run.sh（它會叫這支）。
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
SERVER = ROOT / "herdr-board" / "server.py"


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = pathlib.Path(tempfile.mkdtemp(prefix="opsx-server."))
        cls.state = cls.tmp / "state"
        cls.state.mkdir()
        cls.log = cls.tmp / "opsx.log"
        cls.fail_flag = cls.tmp / "opsx.fail"
        shim_dir = cls.tmp / "bin"
        shim_dir.mkdir()
        cls.env_log = cls.tmp / "env.log"
        cls.herdr_log = cls.tmp / "herdr.log"
        # server 跑的是 plugin 自己的 bin/opsx，不靠 PATH；測試用 OPSX_TEST_OPSX 指到這支假的
        shim = shim_dir / "opsx"
        shim.write_text(
            "#!/usr/bin/env bash\n"
            f'printf "%s\\n" "$*" >> "{cls.log}"\n'
            f'printf "OPSX_STATE_DIR=%s\\n" "${{OPSX_STATE_DIR:-}}" >> "{cls.env_log}"\n'
            f'if [ -f "{cls.fail_flag}" ]; then echo "opsx: 假的失敗" >&2; exit 2; fi\n'
            'echo "ok: $1"\n'
        )
        shim.chmod(0o755)
        herdr = shim_dir / "herdr"
        herdr.write_text("#!/usr/bin/env bash\n" f'printf "%s\\n" "$*" >> "{cls.herdr_log}"\n' 'echo "{}"\n')
        herdr.chmod(0o755)
        cls.repo = cls.tmp / "repo"
        (cls.repo / "openspec" / "changes").mkdir(parents=True)   # --repo 只收真的 opsx repo 根
        cls.fixture = cls.tmp / "collect.json"
        cls.fixture.write_text(json.dumps({"generated_at": "t", "scopes": [], "cards": [{"slug": "x"}], "unmatched_agents": [], "errors": []}))
        env = dict(os.environ, OPSX_STATE_DIR=str(cls.state), OPSX_TEST_OPSX=str(shim), PATH=f"{shim_dir}:{os.environ['PATH']}")
        cls.proc = subprocess.Popen(
            [sys.executable, "-I", str(SERVER), "--port", "0", "--collect", str(cls.fixture)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True,
        )
        line = cls.proc.stdout.readline()
        m = re.search(r"http://(127\.0\.0\.1):(\d+)/", line)
        if not m:
            cls.proc.kill()
            raise AssertionError("server 沒印出監聽位址：%r %s" % (line, cls.proc.stderr.read()))
        cls.host, cls.port = m.group(1), int(m.group(2))
        cls.base = "http://127.0.0.1:%d" % cls.port
        for _ in range(50):
            try:
                urllib.request.urlopen(cls.base + "/healthz", timeout=1); break
            except (urllib.error.URLError, ConnectionError):
                time.sleep(0.05)
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
        if self.fail_flag.exists():
            self.fail_flag.unlink()

    def test_binds_loopback_only(self):
        self.assertEqual(self.host, "127.0.0.1")

    def test_index_is_html(self):
        status, ctype, body = self.req("/")
        self.assertEqual(status, 200)
        self.assertIn("text/html", ctype)
        self.assertIn("<title>", body)

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

    def test_merge_and_stop_and_dispatch(self):
        r = str(self.repo)
        self.req("/api/merge", {"slug": "x", "repo": r}, token=self.token)
        self.req("/api/stop", {"slug": "x"}, token=self.token)
        self.req("/api/dispatch", {"slug": "x", "agent": "claude", "model": "claude-opus-5-5", "mode": "autopilot", "kind": "dev", "repo": r}, token=self.token)
        lines = self.log.read_text().strip().split("\n")
        self.assertEqual(lines[0], "merge x --repo %s" % r)
        self.assertEqual(lines[1], "stop x")
        self.assertEqual(lines[2], "dispatch x --agent claude --model claude-opus-5-5 --mode autopilot --kind dev --repo %s" % r)

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

    def test_focus_runs_herdr(self):
        status, _, body = self.req("/api/focus", {"pane": "w1:p4"}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.herdr_log.read_text().strip(), "pane focus w1:p4")
        status, _, _ = self.req("/api/focus", {"pane": "w1:p4; rm -rf /"}, token=self.token)
        self.assertEqual(status, 400)

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


if __name__ == "__main__":
    unittest.main()
