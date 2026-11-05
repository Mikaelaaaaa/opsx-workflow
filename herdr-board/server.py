#!/usr/bin/env python3
"""opsx 看板的本機 server（herdr-board D1）。python3 標準庫，零依賴。

    server.py [--port N] [--collect <json 檔>] [--state <dir>]

GET  /            → web/index.html
GET  /healthz     → {"ok": true}（不用 token，給 open-board.sh 探活）
GET  /api/collect → `opsx collect` 的輸出；--collect 給了檔就回那個檔（測試用）
POST /api/{answer,dispatch,merge,stop} → 轉呼叫對應的 `opsx` 子命令，回 {ok, stdout, stderr}

/api/* 要 header X-Opsx-Token 等於 <state>/board-token（第一次啟動時產生，之後重用）。
只聽 127.0.0.1；token 是防同一台機器上別的程序亂打 POST。
動作本身在 bin/lib/{answer,merge,dispatch,stop}.sh，這裡只做參數對應與驗證，不碰任何檔。
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import secrets
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
INDEX = HERE / "web" / "index.html"
SLUG_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{32,}$")
COLLECT_TIMEOUT = 60
ACTION_TIMEOUT = 120

# 每個動作：必填欄位、選填欄位、組參數的順序。slug 永遠第一個位置參數。
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


class Config:
    def __init__(self, state: pathlib.Path, collect_file: pathlib.Path | None):
        self.state = state
        self.collect_file = collect_file
        self.token = load_token(state / "board-token")


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
    tmp.write_text(token + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    return token


def build_args(action: str, body: dict) -> list[str]:
    """把 POST body 對成 opsx 的參數。欄位不合格就 raise ValueError（→ 400）。"""
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
        args += ["--%s" % flag, v]
    if spec["trailing"]:
        text = body[spec["trailing"]]
        if "\0" in text:
            raise ValueError("text 含 NUL")
        args.append(text)
    return args


def run_opsx(args: list[str], timeout: int) -> dict:
    try:
        p = subprocess.run(["opsx", *args], capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return {"ok": False, "stdout": "", "stderr": "opsx 不在 PATH（跑 opsx init --global 會裝 ~/.local/bin/opsx）", "rc": 127}
    except subprocess.TimeoutExpired:
        return {"ok": False, "stdout": "", "stderr": "opsx %s 超過 %d 秒沒回" % (args[0], timeout), "rc": 124}
    return {"ok": p.returncode == 0, "stdout": p.stdout, "stderr": p.stderr, "rc": p.returncode}


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

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            self.send_json(200, {"ok": True}); return
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
            if self.cfg.collect_file is not None:
                try:
                    payload = json.loads(self.cfg.collect_file.read_text(encoding="utf-8"))
                except (FileNotFoundError, json.JSONDecodeError) as e:
                    self.send_json(500, {"error": "--collect 檔讀不到或不是 JSON：%s" % e}); return
                self.send_json(200, payload); return
            r = run_opsx(["collect"], COLLECT_TIMEOUT)
            if not r["ok"]:
                self.send_json(502, {"error": "opsx collect 失敗", "stderr": r["stderr"]}); return
            try:
                self.send_json(200, json.loads(r["stdout"]))
            except json.JSONDecodeError as e:
                self.send_json(502, {"error": "opsx collect 回的不是 JSON：%s" % e})
            return
        if path.startswith("/api/"):
            self.send_json(405 if path[5:] in ACTIONS else 404, {"error": path}); return
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
        if action not in ACTIONS:
            self.send_json(404, {"error": "沒有這個動作：%s" % action}); return
        try:
            n = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(n).decode("utf-8") or "{}")
            if not isinstance(body, dict):
                raise ValueError("body 要是物件")
            args = build_args(action, body)
        except (ValueError, json.JSONDecodeError) as e:
            self.send_json(400, {"error": str(e)}); return
        self.send_json(200, run_opsx(args, ACTION_TIMEOUT))


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
