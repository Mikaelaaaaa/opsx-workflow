#!/usr/bin/env python3
"""opsx 看板的本機 server（herdr-board D1）。python3 標準庫，零依賴（要 3.11+，tomllib）。

    server.py [--port N] [--collect <json 檔>] [--state <dir>]

GET /            回 web/index.html。
GET /healthz     回 {"ok": true, "app": "opsx-board"}，不用 token，給 open-board.sh 探活，app 欄讓它認得是我們的。
GET /api/collect 回 `opsx collect` 的輸出；--collect 給了檔就回那個檔（測試用）。同一時間只跑一支 collect，其他請求等它，
                 結果快取 CACHE_S 秒；頁面每 5 秒拉而 ThreadingHTTPServer 每個請求一個 thread，沒有這個會疊成十幾支 collect。
POST /api/{answer,dispatch,merge,stop} 轉呼叫對應的 `opsx` 子命令，POST /api/focus 跑 herdr pane focus；都回 {ok, stdout, stderr}。

/api/* 要 header X-Opsx-Token 等於 <state>/board-token（第一次啟動時產生，之後重用）。只聽 127.0.0.1。
opsx 用 plugin 自己的 bin/opsx（不靠 PATH），並把 --state 透過 OPSX_STATE_DIR 傳下去，兩邊讀同一份狀態。
動作本身在 bin/lib/{answer,merge,dispatch,stop}.sh，這裡只做參數對應與驗證。
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import secrets
import signal
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
OPSX = pathlib.Path(os.environ.get("OPSX_TEST_OPSX") or HERE.parent / "bin" / "opsx")   # 測試換成假的 opsx
INDEX = HERE / "web" / "index.html"
SLUG_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{32,}$")
COLLECT_TIMEOUT = 60
ACTION_TIMEOUT = 120
CACHE_S = 3
MAX_BODY = 64 * 1024

# 每個動作：必填欄位、選填 flag、尾端文字。slug 永遠第一個位置參數。
ACTIONS = {
    "answer": {"required": ("slug", "gate", "text"), "flags": ("gate", "grant", "repo"), "trailing": "text"},
    "merge": {"required": ("slug",), "flags": ("repo",), "trailing": None},
    "stop": {"required": ("slug",), "flags": ("repo",), "trailing": None},
    "dispatch": {"required": ("slug",), "flags": ("agent", "model", "mode", "kind", "repo"), "trailing": None},
}
FLAG_RE = {
    "gate": re.compile(r"^[A-Za-z0-9_.-]{1,64}$"),
    "grant": re.compile(r"^(this|card|repo)$"),
    "agent": re.compile(r"^(claude|codex)$"),
    "model": re.compile(r"^[A-Za-z0-9_.:-]{1,64}$"),
    "mode": re.compile(r"^(interactive|autopilot|drive)$"),
    "kind": re.compile(r"^(dev|bug-fix|refactoring|perf|experiment|ops|chore)$"),
    "repo": re.compile(r"^/[^\0]{1,1024}$"),
}
PANE_RE = re.compile(r"^[A-Za-z0-9:_-]{1,32}$")


class Config:
    def __init__(self, state: pathlib.Path, collect_file: pathlib.Path | None):
        self.state = state
        self.collect_file = collect_file
        self.token = load_token(state / "board-token")
        self.lock = threading.Lock()
        self.cached: tuple[float, int, dict] = (0.0, 0, {})   # (at, status, payload)


def load_token(path: pathlib.Path) -> str:
    try:
        existing = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        existing = ""
    if TOKEN_RE.match(existing):
        return existing
    token = secrets.token_urlsafe(32)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)   # 一開始就 0600，沒有 0644 的窗口
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(token + "\n")
    os.replace(tmp, path)
    return token


def repo_ok(path: str) -> bool:
    """repo 只接受真的 repo 根（有 openspec/changes 的目錄），不是任意絕對路徑。"""
    p = pathlib.Path(path)
    return p.is_absolute() and (p / "openspec" / "changes").is_dir()


def build_args(action: str, body: dict) -> list[str]:
    """把 POST body 對成 opsx 的參數。欄位不合格就 raise ValueError，呼叫端回 400。"""
    spec = ACTIONS[action]
    for k in spec["required"]:
        if not isinstance(body.get(k), str) or not body[k].strip():
            raise ValueError("缺 %s" % k)
    slug = body["slug"]
    if not SLUG_RE.match(slug):
        raise ValueError("slug 不合格：%r" % slug)
    args = [action, slug]
    for flag in spec["flags"]:
        v = body.get(flag)
        if v is None or v == "":
            continue
        if not isinstance(v, str) or not FLAG_RE[flag].match(v):
            raise ValueError("%s 不合格：%r" % (flag, v))
        if flag == "repo" and not repo_ok(v):
            raise ValueError("repo 不是 opsx repo 的根目錄：%r" % v)
        args += ["--%s" % flag, v]
    if spec["trailing"]:
        text = body[spec["trailing"]]
        if "\n" in text or "\r" in text or "\0" in text:
            raise ValueError("text 不能有換行（會變成 gates.md 的新欄位）")
        args += ["--", text]   # 答案以 -- 開頭也送得進去
    return args


def run(argv: list[str], timeout: int, env: dict) -> dict:
    """跑一個子行程；逾時殺整個 process group（collect 底下掛著幾百支 stage_of / python，只殺 bash 會留孤兒）。"""
    try:
        p = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, start_new_session=True)
    except FileNotFoundError:
        return {"ok": False, "stdout": "", "stderr": "%s 不存在" % argv[0], "rc": 127}
    try:
        out, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        out, err = p.communicate()
        return {"ok": False, "stdout": out, "stderr": "%s 超過 %d 秒沒回，已整組殺掉" % (" ".join(argv[:2]), timeout), "rc": 124}
    return {"ok": p.returncode == 0, "stdout": out, "stderr": err, "rc": p.returncode}


class Handler(BaseHTTPRequestHandler):
    cfg: Config  # 由 serve() 設

    def log_message(self, fmt, *args):  # noqa: D102 - 不把 token 印進 log
        sys.stderr.write("%s %s\n" % (self.command, self.path.split("?")[0]))

    def send_json(self, status: int, obj) -> None:
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def authorised(self) -> bool:
        token = self.headers.get("X-Opsx-Token") or ""
        return bool(TOKEN_RE.match(token)) and secrets.compare_digest(token, self.cfg.token)

    def opsx_env(self) -> dict:
        return dict(os.environ, OPSX_STATE_DIR=str(self.cfg.state))

    def collect(self) -> tuple[int, dict]:
        cfg = self.cfg
        if cfg.collect_file is not None:
            try:
                return 200, json.loads(cfg.collect_file.read_text(encoding="utf-8"))
            except (FileNotFoundError, json.JSONDecodeError) as e:
                return 500, {"error": "--collect 檔讀不到或不是 JSON：%s" % e}
        with cfg.lock:   # single-flight：排隊的請求進來時快取多半已經新鮮，直接拿
            at, status, payload = cfg.cached
            if time.monotonic() - at < CACHE_S:
                return status, payload
            r = run(["bash", str(OPSX), "collect"], COLLECT_TIMEOUT, self.opsx_env())
            if not r["ok"]:
                status, payload = 502, {"error": "opsx collect 失敗", "stderr": r["stderr"]}
            else:
                try:
                    status, payload = 200, json.loads(r["stdout"])
                except json.JSONDecodeError as e:
                    status, payload = 502, {"error": "opsx collect 回的不是 JSON：%s" % e}
            cfg.cached = (time.monotonic(), status, payload)
            return status, payload

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            self.send_json(200, {"ok": True, "app": "opsx-board"}); return
        if path == "/":
            try:
                data = INDEX.read_bytes()
            except FileNotFoundError:
                self.send_json(500, {"error": "web/index.html 不存在"}); return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data); return
        if path == "/api/collect":
            if not self.authorised():
                self.send_json(401, {"error": "token"}); return
            status, payload = self.collect()
            self.send_json(status, payload); return
        if path.startswith("/api/"):
            self.send_json(405 if path[5:] in ACTIONS or path[5:] == "focus" else 404, {"error": path}); return
        self.send_json(404, {"error": path})

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if not path.startswith("/api/"):
            self.send_json(404, {"error": path}); return
        if not self.authorised():
            self.send_json(401, {"error": "token"}); return
        action = path[5:]
        if action == "collect":
            self.send_json(405, {"error": "collect 是 GET"}); return
        if action not in ACTIONS and action != "focus":
            self.send_json(404, {"error": "沒有這個動作：%s" % action}); return
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if n < 0 or n > MAX_BODY:
                raise ValueError("body 大小不合理：%d" % n)
            body = json.loads(self.rfile.read(n).decode("utf-8") or "{}")
            if not isinstance(body, dict):
                raise ValueError("body 要是物件")
            if action == "focus":
                pane = body.get("pane")
                if not isinstance(pane, str) or not PANE_RE.match(pane):
                    raise ValueError("pane 不合格：%r" % pane)
                self.send_json(200, run(["herdr", "pane", "focus", pane], 10, self.opsx_env())); return
            args = build_args(action, body)
        except (ValueError, json.JSONDecodeError) as e:
            self.send_json(400, {"error": str(e)}); return
        self.send_json(200, run(["bash", str(OPSX), *args], ACTION_TIMEOUT, self.opsx_env()))


def serve(port: int, state: pathlib.Path, collect_file: pathlib.Path | None) -> None:
    Handler.cfg = Config(state, collect_file)
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.daemon_threads = True
    print("listening http://127.0.0.1:%d/" % httpd.server_address[1], flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


def main() -> None:
    ap = argparse.ArgumentParser(description="opsx 看板 server")
    ap.add_argument("--port", type=int, default=int(os.environ.get("OPSX_BOARD_PORT", "8791")))
    ap.add_argument("--collect", type=pathlib.Path, default=None, help="固定回這個 JSON 檔，不呼叫 opsx collect（測試、對照原型用）")
    ap.add_argument("--state", type=pathlib.Path, default=pathlib.Path(os.environ.get("OPSX_STATE_DIR") or pathlib.Path.home() / ".local/state/opsx"))
    a = ap.parse_args()
    serve(a.port, a.state, a.collect)


if __name__ == "__main__":
    main()
