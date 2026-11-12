"""opsx sync 的本體：撈來源、以 inbox.md 的 source 去重、建殼或更新、寫 sync.log。由 bin/lib/sync.sh 叫。

每個來源產生一串 item（dict），欄位統一：source、repo、path（repo 根）、slug、type、title、body（## 內文，debt 沒有）、
evidence（## 證據）、extra（寫進 frontmatter 的欄位）。gitlab / github 由 herdr-board/sync/{gitlab,github}.sh 撈，obsidian 由 obsidian.py。
debt（code 裡的 shortcut: 註解）不開卡：debt.sh 掃到的寫成 <state>/debt.json 快照，看板只顯示各 repo 的數量與清單。
去重索引：所有 repo 的 openspec/changes/*/inbox.md 與 archive/*/inbox.md，加上 <state>/unfiled/ 與 unfiled/dropped/，source → 檔。
沒有 repo 的 item（path 為 None）不建殼，寫進待分類 <state>/unfiled/<slug>.md，等 opsx file 選 repo。
上游變動只標記不動作（board-inbox D4）：已歸檔的卡不改；issue 關閉寫 upstream: closed；
issue 內容較新時，還沒 explore 的卡重寫一句話與內文，explore 過的只在證據追加一行。
同一時間只跑一支：<state>/sync.lock 上的非阻塞 fcntl.flock，拿不到就退出 3。specs/board-sync。
"""
from __future__ import annotations

import argparse
import datetime
import fcntl
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import tomllib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import safefile  # noqa: E402

SOURCES = ("gitlab", "github", "debt", "obsidian")
CUSTOMER_NOTICE = "customer 來源尚未支援（on-hold），不會同步"
FRONTMATTER = re.compile(r"\A---\n(.*?\n)---\n", re.S)


class Tally:
    def __init__(self):
        self.created = self.updated = self.unchanged = self.errors = 0
        self.first_error = ""

    def error(self, source: str, message: str) -> None:
        self.errors += 1
        if not self.first_error:
            self.first_error = " ".join(("%s: %s" % (source, message)).split())[:300]

    def summary(self) -> str:
        """sync.log 那一列的文字；collect 的 last_sync 照這個格式解析回數字。"""
        text = "新建 %d · 更新 %d · 沒變 %d · 錯誤 %d" % (self.created, self.updated, self.unchanged, self.errors)
        return text + ("：" + self.first_error if self.first_error else "")


def fm_get(text: str, key: str) -> str | None:
    m = FRONTMATTER.match(text)
    if not m:
        return None
    hit = re.search(r"^%s:[ \t]*(.*)$" % re.escape(key), m.group(1), re.M)
    return hit.group(1).strip() if hit else None


def fm_set(text: str, key: str, value: str | None) -> str:
    """frontmatter 裡設 key（value 為 None 就刪掉那行）。inbox.md 一定有 frontmatter（模板就有），沒有就是壞檔。"""
    m = FRONTMATTER.match(text)
    if not m:
        raise ValueError("inbox.md 沒有 frontmatter，不能寫 %s" % key)
    body = m.group(1)
    line = re.compile(r"^%s:.*\n" % re.escape(key), re.M)
    if value is None:
        body = line.sub("", body)
    elif line.search(body):
        body = line.sub("%s: %s\n" % (key, value), body, count=1)
    else:
        body += "%s: %s\n" % (key, value)
    return "---\n" + body + "---\n" + text[m.end():]


def section(text: str, heading: str) -> re.Match:
    m = re.search(r"^## %s\n(.*?)(?=^## |\Z)" % re.escape(heading), text, re.S | re.M)
    if not m:
        raise ValueError("inbox.md 沒有 ## %s" % heading)
    return m


def set_section(text: str, heading: str, content: str) -> str:
    m = section(text, heading)
    return text[:m.start(1)] + "\n%s\n\n" % content.strip() + text[m.end(1):].lstrip("\n")


def append_to_section(text: str, heading: str, line: str) -> str:
    m = section(text, heading)
    kept = m.group(1).rstrip("\n")
    return text[:m.start(1)] + kept + "\n" + line + "\n" + ("\n" if m.end(1) < len(text) else "") + text[m.end(1):]


def repos_under(root: pathlib.Path) -> dict[str, pathlib.Path]:
    """root 下的 opsx repo：有 openspec/changes 而且 .git 是目錄（linked worktree 的 .git 是檔，不算）。
    repo 名取解析後路徑的 basename，跟 collect 一樣；symlink 進 root 的 repo，debt.sh 在實體目錄掃，回報的也是實體名。"""
    out = {}
    if not root.is_dir():
        return out
    for d in sorted(root.iterdir()):
        if (d / "openspec" / "changes").is_dir() and (d / ".git").is_dir():
            real = d.resolve()
            out[real.name] = real
    return out


def source_paths(state: pathlib.Path) -> list[pathlib.Path]:
    f = state / "sources.toml"
    if not f.exists():
        return []
    return [pathlib.Path(s["path"]) for s in tomllib.loads(f.read_text(encoding="utf-8")).get("source", []) if "path" in s]


def has_customer(state: pathlib.Path) -> bool:
    f = state / "sources.toml"
    return f.exists() and "customer" in tomllib.loads(f.read_text(encoding="utf-8"))


def log_sync_row(opsx_root: pathlib.Path, state: pathlib.Path, source: str, created: int, text: str) -> subprocess.CompletedProcess:
    # sync.log 的格式只在 opsx log --sync（bin/lib/log.sh）
    return subprocess.run(["bash", str(opsx_root / "bin" / "opsx"), "log", "--sync", source, str(created), text],
                          capture_output=True, text=True, env=dict(os.environ, OPSX_STATE_DIR=str(state)))


def opsx_repos(root: pathlib.Path, state: pathlib.Path) -> dict[str, pathlib.Path]:
    """跟 opsx collect 同一份 repo 清單：root 下的 repo，加上 sources.toml 登記的 path 本身（不含它的兄弟目錄）。"""
    repos = repos_under(root)
    for p in source_paths(state):
        real = p.resolve()
        if (real / "openspec" / "changes").is_dir() and (real / ".git").is_dir():
            repos.setdefault(real.name, real)
    return repos


def demote_headings(body: str) -> str:
    """issue 內文的 Markdown 標題降兩級：卡的段落靠 `## ` 切，內文裡的 `## Steps` 不能被當成下一段。"""
    return re.sub(r"(?m)^(#{1,6})(?=\s)", r"##\1", body)


def build_index(repos: dict[str, pathlib.Path], state: pathlib.Path) -> dict[str, dict]:
    files: list[tuple[pathlib.Path, bool]] = []
    for top in repos.values():
        ch = top / "openspec" / "changes"
        files += [(p, False) for p in ch.glob("*/inbox.md") if p.parent.name != "archive"]
        files += [(p, True) for p in ch.glob("archive/*/inbox.md")]
    files += [(p, True) for p in (state / "unfiled").glob("*.md")]
    files += [(p, True) for p in (state / "unfiled" / "dropped").glob("*.md")]
    index = {}
    for path, frozen in files:
        try:
            text = path.read_text(encoding="utf-8")
        except FileNotFoundError:
            continue
        src = fm_get(text, "source")
        if src:
            index.setdefault(src, {"path": path, "frozen": frozen})
    return index


def debt_snapshot(opsx_root: pathlib.Path, repos: dict[str, pathlib.Path], tally: Tally) -> tuple[dict[str, list[dict]], set[str]]:
    """對 repos 所在的每個上層目錄跑一次 herdr-board/sync/debt.sh（它一次掃一層），只留 repos 裡的 hit，依 repo 分組。
    也回這次真的掃過的 repo 名（掃失敗的 repo 保留上次的快照）。"""
    snapshot: dict[str, list[dict]] = {}
    scanned: set[str] = set()
    for root in sorted({top.parent for top in repos.values()}):
        p = subprocess.run(["bash", str(opsx_root / "herdr-board" / "sync" / "debt.sh"), str(root)], capture_output=True, text=True)
        if p.returncode != 0:
            tally.error("debt", p.stderr.strip() or "debt.sh 退出 %d" % p.returncode)
            continue
        here = {name for name, top in repos.items() if top.parent == root}
        scanned |= here
        for raw in p.stdout.splitlines():
            hit = json.loads(raw)
            if hit["repo"] not in here:
                continue
            snapshot.setdefault(hit["repo"], []).append(
                {"file": hit["file"], "line": hit["line"], "comment": hit["comment"], "limit": hit["limit"], "trigger": hit["trigger"]})
    for hits in snapshot.values():
        hits.sort(key=lambda h: (h["file"], h["line"]))
    return snapshot, scanned


def write_debt_snapshot(state: pathlib.Path, snapshot: dict[str, list[dict]], scanned: set[str], repos: dict[str, pathlib.Path]) -> None:
    """<state>/debt.json：這次掃過的 repo 用新的，沒掃到的（debt.sh 失敗）留上次的，已經不在 repos 的丟掉。看板只顯示數量與清單，不開卡。"""
    path = state / "debt.json"
    kept: dict[str, list[dict]] = {}
    if path.exists():
        try:
            old = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            old = {}   # 快照是衍生資料，壞了就整份重寫
        if isinstance(old, dict):
            kept = {r: h for r, h in old.items() if r in repos and r not in scanned}
    kept.update(snapshot)
    safefile.write_atomic(str(path), json.dumps(kept, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def issue_items(opsx_root: pathlib.Path, kind: str, state: pathlib.Path, repos: dict[str, pathlib.Path], tally: Tally) -> tuple[list[dict], dict[str, str]]:
    """跑 herdr-board/sync/<kind>.sh list；回 item 與撈成功的 {repo: project}（只有撈成功的 repo 才查關閉）。
    path 不在 repos（例如 linked worktree）的不建殼：去重索引掃不到那裡，建了每次都會多一張。"""
    roots = set(repos.values())
    toml = state / "sources.toml"
    if not toml.exists():
        return [], {}
    p = subprocess.run(["bash", str(opsx_root / "herdr-board" / "sync" / ("%s.sh" % kind)), "list", str(toml)], capture_output=True, text=True)
    if p.returncode != 0:
        tally.error(kind, p.stderr.strip() or "%s.sh 退出 %d" % (kind, p.returncode))
        return [], {}
    items, listed = [], {}
    for raw in p.stdout.split("\n"):
        if not raw:
            continue
        row = json.loads(raw)
        if "error" in row:
            tally.error("%s:%s" % (kind, row["repo"]), row["error"])
        elif "listed" in row:
            listed[row["listed"]] = row["project"]
        elif pathlib.Path(row["path"]).resolve() not in roots:
            tally.error(row["source"], "%s 不是 opsx repo 的根目錄（要有 openspec/changes 與 .git 目錄）" % row["path"])
        else:
            items.append(dict(row, path=pathlib.Path(row["path"]), body=demote_headings(row["body"]), evidence="- %s" % row["url"],
                              extra={"upstream_url": row["url"], "upstream_updated": row["updated_at"]}))
    return items, listed


def obsidian_items(opsx_root: pathlib.Path, state: pathlib.Path, tally: Tally) -> list[dict]:
    """herdr-board/sync/obsidian.py 撈 [obsidian] 收件夾；筆記沒有 repo，交給待分類出口。"""
    toml = state / "sources.toml"
    if not toml.exists():
        return []
    p = subprocess.run([sys.executable, "-I", str(opsx_root / "herdr-board" / "sync" / "obsidian.py"), str(toml)], capture_output=True, text=True)
    if p.returncode != 0:
        tally.error("obsidian", p.stderr.strip() or "obsidian.py 退出 %d" % p.returncode)
        return []
    items = []
    # 只按 \n 切：splitlines 也會在 U+2028 等字元切，筆記內文裡有就會切斷一行 JSON
    for raw in filter(None, p.stdout.split("\n")):
        row = json.loads(raw)
        if "error" in row:
            tally.error("obsidian", row["error"])
        else:
            items.append(dict(row, repo=None, path=None, type="功能", body=demote_headings(row["body"]), extra={}))
    return items


def inbox_text(item: dict, today: str) -> str:
    fm = "".join("%s: %s\n" % kv for kv in item["extra"].items())
    body = "## 內文\n\n%s\n\n" % item["body"].strip() if item["body"] is not None else ""
    return "---\ntype: %s\nsource: %s\nfound: %s\nrelated:\n%s---\n\n## 一句話\n\n%s\n\n%s## 證據\n\n%s\n" % (
        item["type"], item["source"], today, fm, item["title"], body, item["evidence"])


def create_shell(opsx_root: pathlib.Path, item: dict, today: str) -> str:
    """用 common.sh 的 new_shell 建殼（slug 撞名加 -2 的規則只有一份）。"""
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".md", delete=False) as f:
        f.write(inbox_text(item, today))
    try:
        p = subprocess.run(["bash", "-c", 'source "$1"; new_shell "$2" "$3" "$4"', "opsx-sync",
                            str(opsx_root / "bin" / "lib" / "common.sh"), str(item["path"]), item["slug"], f.name],
                           capture_output=True, text=True)
    finally:
        os.unlink(f.name)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "new_shell 退出 %d" % p.returncode)
    return p.stdout.strip()


def file_unfiled(state: pathlib.Path, item: dict, today: str) -> pathlib.Path:
    """沒有 repo 的 item 寫成 <state>/unfiled/<slug>.md；撞名規則跟 new.sh 一樣，只看 unfiled/ 這一層。"""
    unfiled = state / "unfiled"
    unfiled.mkdir(parents=True, exist_ok=True)
    text, n = inbox_text(item, today), 1
    path = unfiled / ("%s.md" % item["slug"])
    while True:
        try:
            with path.open("x", encoding="utf-8") as f:
                f.write(text)
            return path
        except FileExistsError:
            n += 1
            path = unfiled / ("%s-%d.md" % (item["slug"], n))


def update_issue(entry: dict, item: dict) -> bool:
    """回 True 表示改了檔。重開的 issue 拿掉 upstream: closed；內容較新時照 D4 改。"""
    path = entry["path"]
    with safefile.CardLock(str(path.parent)):
        old = path.read_text(encoding="utf-8")
        new = old
        if fm_get(new, "upstream") == "closed":
            new = fm_set(new, "upstream", None)
        known = fm_get(new, "upstream_updated")
        if known is None:
            raise ValueError("inbox.md 沒有 upstream_updated（%s），不知道上游是否較新，不改寫" % path)
        if item["updated_at"] > known:
            if (path.parent / "explore.md").exists():
                new = append_to_section(new, "證據", "- %s 於 %s 更新" % (item["source"], item["updated_at"][:10]))
            else:
                new = set_section(set_section(new, "一句話", item["title"]), "內文", item["body"] or "（空）")
            new = fm_set(new, "upstream_updated", item["updated_at"])
        if new == old:
            return False
        safefile.write_atomic(str(path), new)
    return True


def mark_closed(opsx_root: pathlib.Path, kind: str, index: dict, seen: set[str], listed: dict[str, str], tally: Tally) -> None:
    """list 裡少了的不一定是關閉（也可能改指派），逐筆 view 看 state，只有 closed 才標。"""
    for src, entry in index.items():
        if entry["frozen"] or src in seen or not src.startswith(kind + ":"):
            continue
        repo, _, n = src[len(kind) + 1:].rpartition("#")
        if repo not in listed:
            continue
        try:
            text = entry["path"].read_text(encoding="utf-8")
        except FileNotFoundError:
            continue
        if fm_get(text, "upstream") == "closed":
            continue
        p = subprocess.run(["bash", str(opsx_root / "herdr-board" / "sync" / ("%s.sh" % kind)), "state", listed[repo], n], capture_output=True, text=True)
        if p.returncode != 0:
            tally.error(src, p.stderr.strip() or "%s.sh state 退出 %d" % (kind, p.returncode))
            continue
        if p.stdout.strip() != "closed":
            continue
        # 網路查完才鎖；鎖內重讀，查的期間併入的段與別人標的 closed 都不蓋掉
        try:
            with safefile.CardLock(str(entry["path"].parent)):
                text = entry["path"].read_text(encoding="utf-8")
                if fm_get(text, "upstream") == "closed":
                    continue
                safefile.write_atomic(str(entry["path"]), fm_set(text, "upstream", "closed"))
        except FileNotFoundError:
            continue
        tally.updated += 1


def main() -> int:
    ap = argparse.ArgumentParser(prog="opsx sync")
    ap.add_argument("--state", type=pathlib.Path, required=True)
    ap.add_argument("--opsx-root", type=pathlib.Path, required=True)
    ap.add_argument("--root", type=pathlib.Path, default=pathlib.Path.home() / "code")
    ap.add_argument("--source", choices=SOURCES)
    a = ap.parse_args()

    a.state.mkdir(parents=True, exist_ok=True)
    lock = safefile.open_lock(a.state / "sync.lock")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("opsx sync: 同步進行中（另一支還沒跑完）", file=sys.stderr)
        return 3

    now = datetime.datetime.now().astimezone()
    today = now.date().isoformat()
    tally = Tally()
    repos = opsx_repos(a.root.resolve(), a.state)
    index = build_index(repos, a.state)

    wanted = (a.source,) if a.source else SOURCES
    items: list[dict] = []
    listed: dict[str, dict[str, str]] = {}
    for kind in ("gitlab", "github"):
        if kind in wanted:
            got, listed[kind] = issue_items(a.opsx_root, kind, a.state, repos, tally)
            items += got
    if "debt" in wanted:
        snapshot, scanned = debt_snapshot(a.opsx_root, repos, tally)
        write_debt_snapshot(a.state, snapshot, scanned, repos)
    if "obsidian" in wanted:
        items += obsidian_items(a.opsx_root, a.state, tally)

    seen: set[str] = set()
    for item in items:
        src = item["source"]
        if src in seen:
            continue
        seen.add(src)
        entry = index.get(src)
        if entry is None and item["path"] is None:
            index[src] = {"path": file_unfiled(a.state, item, today), "frozen": True}
            tally.created += 1
            continue
        if entry is None:
            try:
                slug = create_shell(a.opsx_root, item, today)
            except RuntimeError as e:
                tally.error(src, str(e)); continue
            index[src] = {"path": item["path"] / "openspec" / "changes" / slug / "inbox.md", "frozen": False}
            tally.created += 1
            continue
        # obsidian 筆記建卡後不更新（sync-obsidian D2），搬進 repo 之後也一樣
        if entry["frozen"] or src.startswith("obsidian:"):
            tally.unchanged += 1
            continue
        try:
            changed = update_issue(entry, item)
        except FileNotFoundError:
            tally.unchanged += 1
            continue
        except ValueError as e:
            tally.error(src, str(e)); continue
        if changed:
            tally.updated += 1
        else:
            tally.unchanged += 1
    for kind, got in listed.items():
        mark_closed(a.opsx_root, kind, index, seen, got, tally)

    # 一次同步一列，source 是 sync；customer 的提示是另一列，collect 只認 sync 那列
    rows = [("sync", tally.created, tally.summary())]
    if has_customer(a.state):
        print("opsx sync: " + CUSTOMER_NOTICE)
        rows.insert(0, ("customer", 0, CUSTOMER_NOTICE))
    for source, created, text in rows:
        p = log_sync_row(a.opsx_root, a.state, source, created, text)
        if p.returncode != 0:
            print("opsx sync: 寫 sync.log 失敗：%s" % p.stderr.strip(), file=sys.stderr)
            return 1
    print("opsx sync: 新建 %d · 更新 %d · 沒變 %d · 錯誤 %d%s" % (
        tally.created, tally.updated, tally.unchanged, tally.errors, "（%s）" % tally.first_error if tally.first_error else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
