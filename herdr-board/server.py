#!/usr/bin/env python3
"""opsx 看板的本機 server（herdr-board D1）。python3 標準庫，零依賴（要 3.11+，tomllib）。

    server.py [--port N] [--collect <json 檔>] [--state <dir>]

GET /            回 web/index.html。
GET /healthz     回 {"ok": true, "app": "opsx-board"}，不用 token，給 open-board.sh 探活，app 欄讓它認得是我們的。
GET /api/collect 回 `opsx collect` 的輸出；--collect 給了檔就回那個檔（測試用）。同一時間只跑一支 collect，其他請求等它，
                 結果快取 CACHE_S 秒；頁面每 5 秒拉而 ThreadingHTTPServer 每個請求一個 thread，沒有這個會疊成十幾支 collect。
                 動作 POST 呼叫過 opsx 後快取作廢，下一個 GET 拿到的是動作之後才開始的 collect。
GET /api/log[?since=<iso>] 回 `opsx timeline [--since …]` 的輸出（紀錄 tab、抽屜、banner 用，開才拉，不快取）。
GET /api/output?pane=<id> 跑 `herdr agent read <id> --lines 10 --format text`，回 {ok, text} 或 {ok: false, error}（抽屜「最後輸出」）。
POST /api/seen {at} 把 at 寫進 <state>/last-seen（banner 按「關閉」時送）。
POST /api/{answer,dispatch,merge,stop,new,file,drop,sync,note} 轉呼叫對應的 `opsx` 子命令，POST /api/focus 跑 herdr agent focus <slug>；都回 {ok, stdout, stderr}。
POST /api/priority {repo, slug, level, reason} 轉 `opsx priority <slug> --set <level> --reason <理由> --repo <repo>`；
                 level 不是 P0/P1/P2 或理由空白回 400，不叫 opsx。
POST /api/paste {text, repo?, files: [{name, data(base64)}]} 把檔寫進暫存資料夾，轉呼叫 `opsx new [--repo] --attach <檔>… -- <一句話>`，
                 跑完刪暫存。body 上限 PASTE_MAX_BODY，其他 POST 是 MAX_BODY。

/api/* 要 header X-Opsx-Token 等於 <state>/board-token（第一次啟動時產生，之後重用）。只聽 127.0.0.1。
opsx 用 plugin 自己的 bin/opsx（不靠 PATH），並把 --state 透過 OPSX_STATE_DIR 傳下去，兩邊讀同一份狀態。
動作本身在 bin/lib/{answer,merge,dispatch,stop,new,file,drop,sync,note}.sh；
sync 以退出碼 3 結束（另一支同步還在跑）回 409，這裡只做參數對應與驗證。
"""
from __future__ import annotations

import argparse
import base64
import binascii
import datetime
import json
import os
import pathlib
import re
import secrets
import signal
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

HERE = pathlib.Path(__file__).resolve().parent
OPSX = pathlib.Path(os.environ.get("OPSX_TEST_OPSX") or HERE.parent / "bin" / "opsx")   # 測試換成假的 opsx
INDEX = HERE / "web" / "index.html"
SLUG_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{32,}$")
COLLECT_TIMEOUT = 60
TIMELINE_TIMEOUT = 60
OUTPUT_TIMEOUT = 10
ACTION_TIMEOUT = 120
CACHE_S = 3
MAX_BODY = 64 * 1024
PASTE_MAX_BODY = 64 * 1024 * 1024   # base64 多三分之一，夠一次帶四個 10 MB 的檔（五個是 69.9 MB）
NAME_MAX = 128
NAME_MAX_BYTES = 255   # 多數檔案系統的單一檔名上限是 255 bytes，CJK 一字三 bytes
# 一句話會進 argv，太長的一行（壓縮過的 JSON、log）會讓 exec 回 E2BIG；全文另存在 paste.md
ONE_LINER_MAX = 200

# 每個動作：有沒有 slug（有就是第一個位置參數）、必填欄位、選填 flag、尾端文字。
ACTIONS = {
    "answer": {"slug": True, "required": ("gate", "text"), "flags": ("sub", "gate", "grant", "repo"), "trailing": "text"},
    "merge": {"slug": True, "required": (), "flags": ("repo",), "trailing": None},
    "stop": {"slug": True, "required": (), "flags": ("repo",), "trailing": None},
    "dispatch": {"slug": True, "required": (), "flags": ("agent", "model", "mode", "kind", "repo", "note"), "trailing": None},
    "new": {"slug": False, "required": ("text",), "flags": ("repo",), "trailing": "text"},
    "file": {"slug": True, "required": ("repo",), "flags": ("repo",), "trailing": None},
    "drop": {"slug": True, "required": ("text",), "flags": ("repo",), "trailing": "text"},
    "sync": {"slug": False, "required": (), "flags": ("source",), "trailing": None},
    "note": {"slug": True, "required": ("text",), "flags": ("repo",), "trailing": "text"},
    "reap": {"slug": False, "required": (), "flags": ("pane",), "trailing": None},
}
PANE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:_-]{0,31}$")   # 不能以 - 開頭，免得被 herdr 當成旗標
FLAG_RE = {
    "sub": SLUG_RE,   # 會拼進 changes/<slug>/subs/<sub> 路徑，不能有 / 或 ..
    "gate": re.compile(r"^[A-Za-z0-9_.-]{1,64}$"),
    "grant": re.compile(r"^(this|card|repo)$"),
    "agent": re.compile(r"^(claude|codex)$"),
    "model": re.compile(r"^[A-Za-z0-9_.:-]{1,64}$"),
    "mode": re.compile(r"^(interactive|autopilot|drive)$"),
    "kind": re.compile(r"^(dev|bug-fix|refactoring|perf|experiment|ops|chore)$"),
    "repo": re.compile(r"^/[^\0]{1,1024}$"),
    "source": re.compile(r"^(gitlab|github|debt|obsidian)$"),
    "note": re.compile(r"^[^\n\r\0]{1,2000}\Z"),   # \Z 不是 $：$ 會放過結尾的 \n
    "pane": PANE_RE,
}
LEVELS = ("P0", "P1", "P2")


class Config:
    def __init__(self, state: pathlib.Path, collect_file: pathlib.Path | None):
        self.state = state
        self.collect_file = collect_file
        self.token = load_token(state / "board-token")
        self.lock = threading.Lock()
        self.cached: tuple[float, float, int, dict] = (0.0, 0.0, 0, {})   # (at, started, status, payload)
        # 動作 POST 呼叫完 opsx 的時間。不拿 lock：在這之前開始的 collect 結束時仍會寫快取，靠比開始時間把它當作過期
        self.invalidated_at = 0.0


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


def write_atomic(path: pathlib.Path, text: str) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def aware_iso(value: str) -> bool:
    """帶時區的 ISO 8601。沒有時區的時間跟 decisions.tsv 的列比不出先後。"""
    try:
        return datetime.datetime.fromisoformat(value).tzinfo is not None
    except ValueError:
        return False


def build_args(action: str, body: dict) -> list[str]:
    """把 POST body 對成 opsx 的參數。欄位不合格就 raise ValueError，呼叫端回 400。"""
    spec = ACTIONS[action]
    for k in (("slug",) if spec["slug"] else ()) + spec["required"]:
        if not isinstance(body.get(k), str) or not body[k].strip():
            raise ValueError("缺 %s" % k)
    args = [action, "--source", "me"] if action == "new" else [action]   # 看板是使用者按的，不因 server 從 agent worktree 啟動就變 agent
    if spec["slug"]:
        if not SLUG_RE.match(body["slug"]):
            raise ValueError("slug 不合格：%r" % body["slug"])
        args.append(body["slug"])
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


def paste_parts(body: dict) -> tuple[list[str], list[tuple[str, bytes]], str]:
    """把 /api/paste 的 body 拆成 (--repo 參數, [(檔名, 內容)], 一句話)。欄位不合格就 raise ValueError，呼叫端回 400。"""
    text, files = body.get("text"), body.get("files")
    if not isinstance(text, str):
        raise ValueError("text 要是字串：%r" % text)
    if "\0" in text:
        raise ValueError("text 不能有 NUL")
    if not isinstance(files, list):
        raise ValueError("files 要是陣列：%r" % files)
    decoded = []
    for f in files:
        if not isinstance(f, dict):
            raise ValueError("files 的每一筆要是物件：%r" % f)
        name, data = f.get("name"), f.get("data")
        if (not isinstance(name, str) or not name or len(name) > NAME_MAX or name.startswith(".")
                or any(ch in "/\\" or ord(ch) < 0x20 or ord(ch) == 0x7f for ch in name)):
            raise ValueError("檔名不合格：%r" % name)
        try:
            name_bytes = len(name.encode("utf-8"))
        except UnicodeEncodeError as e:
            raise ValueError("檔名不是合法的 UTF-8：%r" % name) from e
        if name_bytes > NAME_MAX_BYTES:
            raise ValueError("檔名超過 %d bytes：%r" % (NAME_MAX_BYTES, name))
        if not isinstance(data, str):
            raise ValueError("%s 的 data 要是 base64 字串：%r" % (name, data))
        try:
            decoded.append((name, base64.b64decode(data, validate=True)))
        except binascii.Error as e:
            raise ValueError("%s 的 data 不是合法 base64：%s" % (name, e)) from e
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines and not decoded:
        raise ValueError("text 與 files 至少要有一個非空")
    # 多行或第一行太長時，一句話取第一行開頭，全文另存成附件，opsx new 的單行規則就不必放寬
    if len(lines) > 1 or (lines and len(lines[0]) > ONE_LINER_MAX):
        decoded.insert(0, ("paste.md", text.encode("utf-8")))
    one_liner = lines[0][:ONE_LINER_MAX] if lines else "附件：%s" % decoded[0][0]
    repo = body.get("repo")
    repo_args = []
    if repo is not None and repo != "":
        if not isinstance(repo, str) or not FLAG_RE["repo"].match(repo) or not repo_ok(repo):
            raise ValueError("repo 不是 opsx repo 的根目錄：%r" % repo)
        repo_args = ["--repo", repo]
    return repo_args, decoded, one_liner


def write_attachments(root: pathlib.Path, files: list[tuple[str, bytes]]) -> list[str]:
    """第 i 個檔寫進 root/<i>/，回 --attach 參數。同名（含只差大小寫）的檔各在自己的資料夾，opsx new 取 basename 時再改名成 -2。"""
    args = []
    for i, (name, data) in enumerate(files):
        d = root / str(i)
        d.mkdir()
        (d / name).write_bytes(data)
        args += ["--attach", str(d / name)]
    return args


def priority_args(body: dict) -> list[str]:
    """POST /api/priority 對成 `priority <slug> --set <level> --reason <理由> --repo <path>`。不合格 raise ValueError。"""
    slug, level, reason, repo = body.get("slug"), body.get("level"), body.get("reason"), body.get("repo")
    if not isinstance(slug, str) or not SLUG_RE.match(slug):
        raise ValueError("slug 不合格：%r" % slug)
    if level not in LEVELS:
        raise ValueError("level 要是 P0、P1、P2：%r" % level)
    if not isinstance(reason, str) or not reason.strip():
        raise ValueError("改等級要寫理由")
    if "\0" in reason:
        raise ValueError("reason 不能有 NUL")
    if not isinstance(repo, str) or not FLAG_RE["repo"].match(repo) or not repo_ok(repo):
        raise ValueError("repo 不是 opsx repo 的根目錄：%r" % repo)
    return ["priority", slug, "--set", level, "--reason", reason, "--repo", repo]


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


def raise_terminal(state: pathlib.Path, env: dict) -> str | None:
    """把 config.toml 的 terminal_app 帶到前景；成功回 None，帶不起來回要給人看的一句話。"""
    path = state / "config.toml"
    where = "已在 herdr 切到該 pane，"
    try:
        app = tomllib.loads(path.read_text(encoding="utf-8")).get("terminal_app")
    except FileNotFoundError:
        app = None
    except (tomllib.TOMLDecodeError, UnicodeDecodeError, OSError) as e:
        return "%s但 %s 壞了或讀不到（%s），請切到終端機" % (where, path, e)
    if not isinstance(app, str) or not app or "\0" in app:
        return '%s請切到終端機。要自動帶到前景，在 %s 寫 terminal_app = "Warp"（換成你的 app）' % (where, path)
    r = run(["open", "-a", app], 10, env)
    if not r["ok"]:
        return "%s請切到 %s（open -a 失敗：%s）" % (where, app, r["stderr"].strip())
    return None


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
            at, started, status, payload = cfg.cached
            if time.monotonic() - at < CACHE_S and started > cfg.invalidated_at:
                return status, payload
            started = time.monotonic()
            r = run(["bash", str(OPSX), "collect"], COLLECT_TIMEOUT, self.opsx_env())
            if not r["ok"]:
                status, payload = 502, {"error": "opsx collect 失敗", "stderr": r["stderr"]}
            else:
                try:
                    status, payload = 200, json.loads(r["stdout"])
                except json.JSONDecodeError as e:
                    status, payload = 502, {"error": "opsx collect 回的不是 JSON：%s" % e}
            cfg.cached = (time.monotonic(), started, status, payload)
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
        if path == "/api/output":
            if not self.authorised():
                self.send_json(401, {"error": "token"}); return
            pane = parse_qs(self.path.split("?", 1)[1] if "?" in self.path else "").get("pane", [""])[0]
            if not PANE_RE.match(pane):
                self.send_json(400, {"error": "pane 不合格：%r" % pane}); return
            r = run(["herdr", "agent", "read", pane, "--lines", "10", "--format", "text"], OUTPUT_TIMEOUT, self.opsx_env())
            if not r["ok"]:
                self.send_json(200, {"ok": False, "error": (r["stderr"] or r["stdout"]).strip() or "herdr agent read 失敗"}); return
            self.send_json(200, {"ok": True, "text": r["stdout"]}); return
        if path == "/api/log":
            if not self.authorised():
                self.send_json(401, {"error": "token"}); return
            query = parse_qs(self.path.split("?", 1)[1] if "?" in self.path else "")
            args = ["bash", str(OPSX), "timeline"]
            if "since" in query:
                since = query["since"][0]
                if not aware_iso(since):
                    self.send_json(400, {"error": "since 要是帶時區的 ISO 8601：%r" % since}); return
                args += ["--since", since]
            r = run(args, TIMELINE_TIMEOUT, self.opsx_env())
            if not r["ok"]:
                self.send_json(502, {"error": "opsx timeline 失敗", "stderr": r["stderr"]}); return
            try:
                payload = json.loads(r["stdout"])
            except json.JSONDecodeError as e:
                self.send_json(502, {"error": "opsx timeline 回的不是 JSON：%s" % e}); return
            self.send_json(200, payload); return
        if path.startswith("/api/"):
            self.send_json(405 if path[5:] in ACTIONS or path[5:] in ("focus", "paste") else 404, {"error": path}); return
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
        if action not in ACTIONS and action not in ("focus", "seen", "priority", "paste"):
            self.send_json(404, {"error": "沒有這個動作：%s" % action}); return
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if action == "paste" and n > PASTE_MAX_BODY:
                self.send_json(413, {"error": "body 超過 %d bytes：%d" % (PASTE_MAX_BODY, n)}); return
            if n < 0 or n > (PASTE_MAX_BODY if action == "paste" else MAX_BODY):
                raise ValueError("body 大小不合理：%d" % n)
            body = json.loads(self.rfile.read(n).decode("utf-8") or "{}")
            if not isinstance(body, dict):
                raise ValueError("body 要是物件")
            if action == "seen":
                at = body.get("at")
                if not isinstance(at, str) or not aware_iso(at):
                    raise ValueError("at 要是帶時區的 ISO 8601：%r" % at)
                write_atomic(self.cfg.state / "last-seen", at + "\n")
                self.send_json(200, {"ok": True}); return
            if action == "focus":
                # herdr pane focus 只收 --direction；跳到某個 agent 用 agent focus <name>，agent 名 = slug
                agent = body.get("agent")
                if not isinstance(agent, str) or not SLUG_RE.match(agent):
                    raise ValueError("agent 不合格：%r" % agent)
                r = run(["herdr", "agent", "focus", agent], 10, self.opsx_env())
                if r["ok"]:
                    hint = raise_terminal(self.cfg.state, self.opsx_env())
                    if hint:
                        r["hint"] = hint
                self.send_json(200, r); return
            if action == "paste":
                repo_args, files, one_liner = paste_parts(body)
            else:
                args = priority_args(body) if action == "priority" else build_args(action, body)
        except (ValueError, json.JSONDecodeError) as e:
            self.send_json(400, {"error": str(e)}); return
        if action == "paste":
            with tempfile.TemporaryDirectory(prefix="opsx-paste.") as d:
                attach = write_attachments(pathlib.Path(d), files)
                r = run(["bash", str(OPSX), "new", "--source", "me", *repo_args, *attach, "--", one_liner], ACTION_TIMEOUT, self.opsx_env())
            self.cfg.invalidated_at = time.monotonic()
            self.send_json(200, r); return
        r = run(["bash", str(OPSX), *args], ACTION_TIMEOUT, self.opsx_env())
        self.cfg.invalidated_at = time.monotonic()
        # sync 的退出碼 3 是已有一支在跑；reap 的退出碼 2 是指定的 pane 不是孤兒
        self.send_json(409 if action == "sync" and r["rc"] == 3 else 422 if action == "reap" and r["rc"] == 2 else 200, r)


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
