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


def start_server(env: dict, fixture: pathlib.Path) -> tuple[subprocess.Popen, str, int]:
    """起一支 server（--port 0），回 (proc, host, port)；等到 /healthz 回應。"""
    proc = subprocess.Popen(
        [sys.executable, "-I", str(SERVER), "--port", "0", "--collect", str(fixture)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True,
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
        cls.herdr_log = cls.tmp / "herdr.log"
        # server 跑的是 plugin 自己的 bin/opsx，不靠 PATH；測試用 OPSX_TEST_OPSX 指到這支假的
        shim = shim_dir / "opsx"
        shim.write_text(
            "#!/usr/bin/env bash\n"
            f'printf "%s\\n" "$*" >> "{cls.log}"\n'
            f'printf "OPSX_STATE_DIR=%s\\n" "${{OPSX_STATE_DIR:-}}" >> "{cls.env_log}"\n'
            f'if [ -f "{cls.fail_flag}" ]; then echo "opsx: 假的失敗" >&2; exit 2; fi\n'
            f'if [ -f "{cls.rc_file}" ]; then echo "opsx: 假的退出碼" >&2; exit "$(cat "{cls.rc_file}")"; fi\n'
            'if [ "$1" = timeline ]; then echo \'{"generated_at": "g", "last_seen": null, "events": [], "errors": []}\'; exit 0; fi\n'
            'echo "ok: $1"\n'
        )
        shim.chmod(0o755)
        herdr = shim_dir / "herdr"
        herdr.write_text("#!/usr/bin/env bash\n" f'printf "%s\\n" "$*" >> "{cls.herdr_log}"\n'
                         'if [ "$3" = "w9:p9" ]; then echo "pane not found" >&2; exit 1; fi\n'
                         'if [ "$1 $2" = "agent read" ]; then printf "line 1\\nline 2\\n"; exit 0; fi\n'
                         'echo "{}"\n')
        herdr.chmod(0o755)
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
        if self.fail_flag.exists():
            self.fail_flag.unlink()
        if self.rc_file.exists():
            self.rc_file.unlink()

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
        self.assertEqual(self.log.read_text().strip().split("\n"), ["new -- 試試看", "new --repo %s -- 試試看" % r])

    def test_new_rejects_empty_or_multiline_text(self):
        for text in ("", "a\nb"):
            status, _, body = self.req("/api/new", {"text": text}, token=self.token)
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

    def test_sync_with_and_without_source(self):
        status, _, body = self.req("/api/sync", {}, token=self.token)
        self.assertEqual(status, 200, body)
        status, _, body = self.req("/api/sync", {"source": "debt"}, token=self.token)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.log.read_text().strip().split("\n"), ["sync", "sync --source debt"])

    def test_sync_rejects_unknown_source(self):
        status, _, body = self.req("/api/sync", {"source": "obsidian"}, token=self.token)
        self.assertEqual(status, 400, body)
        self.assertEqual(self.log.read_text(), "")

    def test_sync_in_progress_is_409(self):
        self.rc_file.write_text("3")
        status, _, body = self.req("/api/sync", {}, token=self.token)
        self.assertEqual(status, 409, body)
        self.rc_file.write_text("3")
        status, _, body = self.req("/api/merge", {"slug": "x"}, token=self.token)
        self.assertEqual(status, 200, "只有 sync 的退出碼 3 是 409：%s" % body)

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


if __name__ == "__main__":
    unittest.main()
