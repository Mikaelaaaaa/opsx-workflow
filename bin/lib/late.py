"""opsx late 的判斷：PR 合併後，remote 的分支比合併當下的 head 多了幾個 commit。

用法：late.py <repo top> <slug> <state dir> <open_gate 0|1>，MR 資料（mr.sh 的 mr_json）走環境變數 OPSX_LATE_MR。
退出 0：stdout `none` 或 `acked <短 sha>`；退出 1：stdout `late <N> <短 sha> <branch>` 加每個 commit 一行；
退出 2：查不出來，stderr 寫缺的欄位與值。squash 合併後分支 commit 不是 main 的祖先，所以只能比 head_sha 與 remote 現在的 head。
規則見 openspec/specs/merged-late-commits/spec.md。
"""
import datetime
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chain  # noqa: E402
import jsonfile  # noqa: E402
import safefile  # noqa: E402

GIT_TIMEOUT = int(os.environ.get("OPSX_LATE_GIT_TIMEOUT", "60"))   # absent 與預設同義：不設就是 60 秒
GATE_QUESTION ="PR 合併後分支又多了 %d 個 commit，沒進 main：要開後續 PR 帶進來嗎？"


class Unknown(Exception):
    """查不出來：不是「沒有」。message 寫缺的欄位與值。"""


def git(top, *args):
    """一個 git 指令。一個卡住的 remote 會卡住拿著 lock 的整輪 coordinate，所以有時限、不問密碼。"""
    try:
        p = subprocess.run(["git", "-C", top] + list(args), capture_output=True, text=True, timeout=GIT_TIMEOUT,
                           env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
    except subprocess.TimeoutExpired as e:
        raise Unknown("git %s 逾時（%d 秒）" % (" ".join(args[:3]), GIT_TIMEOUT)) from e
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def host_of(url):
    """URL 的 host（小寫）；本機路徑與 file:// 沒有 host，回 None。"""
    m = re.match(r"^(?:[A-Za-z+]+://)?(?:[^@/]+@)?([^/:]+)", url)
    return m.group(1).lower() if m else None


def remote_for(top, url):
    host = host_of(url)
    if host is None:
        raise Unknown("mr.url %r 取不出 host" % url)
    _, out, _ = git(top, "config", "--get-regexp", r"^remote\..*\.url$")
    found = []
    for line in out.splitlines():
        key, _, value = line.partition(" ")
        if host_of(value) == host:
            found.append(key[len("remote."):-len(".url")])
    if len(found) != 1:
        raise Unknown("mr.url 的 host %s 對到 %d 個 remote（要剛好 1 個）：%s" % (host, len(found), "、".join(found) or "無"))
    return found[0]


def branch_of(top, slug, state):
    entry = jsonfile.load(os.path.join(state, "dispatch.json")).get("%s/%s" % (os.path.basename(top), slug))
    if entry and entry.get("branch"):
        return entry["branch"]
    path = os.path.join(top, "openspec", "workplan.yaml")
    if os.path.exists(path):
        prs = [pr for f in chain.load_workplan(path).get("features") or [] for pr in f.get("prs") or []]
        pr = chain.find_pr(prs, slug)
        if pr and pr.get("branch"):
            return pr["branch"]
    raise Unknown("沒有 branch：dispatch.json 沒有 %s 的 branch，%s 也沒有對到它的 PR" % (slug, path))


def late_commits(top, remote, branch, head_sha):
    """remote 分支上、head_sha 之後的 commit，新的在前：[(完整 sha, 標題)]；分支在 remote 已刪回 []。"""
    ref = "refs/heads/%s" % branch
    rc, out, err = git(top, "ls-remote", "--heads", remote, ref)
    if rc != 0:
        raise Unknown("git ls-remote %s %s 失敗：%s" % (remote, ref, err[:200]))
    if not out:
        return []
    tracking = "refs/remotes/%s/%s" % (remote, branch)
    # tracking ref 只是這裡的快取，+ 讓被 force-push 或 rebase 過的分支也抓得下來
    rc, _, err = git(top, "fetch", "-q", remote, "+%s:%s" % (ref, tracking))
    if rc != 0:
        raise Unknown("git fetch %s %s 失敗：%s" % (remote, branch, err[:200]))
    rc, _, _ = git(top, "cat-file", "-e", head_sha + "^{commit}")
    if rc != 0:
        raise Unknown("mr.head_sha %s 不在本機" % head_sha)
    rc, out, err = git(top, "log", "--format=%H %s", "%s..%s" % (head_sha, tracking))
    if rc != 0:
        raise Unknown("git log %s..%s 失敗：%s" % (head_sha, tracking, err[:200]))
    commits = []
    for line in out.splitlines():
        sha, _, title = line.partition(" ")   # 最舊的一行標題是空的時，strip 已吃掉行尾空白
        commits.append((sha, title))
    return commits


def gate_status(gates_path, gate_id):
    """gates.md 裡 ## <gate_id> 那段的 status；沒有這段回 None。"""
    if not os.path.exists(gates_path):
        return None
    with open(gates_path, encoding="utf-8") as f:
        for part in re.split(r"(?m)^(?=## )", f.read()):
            if part.split("\n", 1)[0][3:].strip() == gate_id:
                m = re.search(r"(?m)^status:\s*(\S+)", part)
                return m.group(1) if m else ""
    return None


def open_gate(gates_path, gate_id, commits, branch, head_sha):
    lines = "\n".join("  - %s %s" % (sha[:7], title) for sha, title in commits)
    text = (
        "## %s\ntype: decision\nstatus: open\nopened_at: %s\n問題: %s\n"
        "已確認: MR 合併當下分支的 head 是 %s，remote 的 %s 現在多了：\n%s\n"
        "選項: 開後續 PR 帶進來 (Recommended) | 不要了\n建議: 不開 PR 這些 commit 不會進 main，分支一刪就沒了；不需要的才選不要了。\n"
        "證據: git log %s..<remote>/%s\n風險: 選不要了的話這些 commit 之後只存在 remote 分支上。\n預設: 不回答就不收尾、不歸檔這張卡。\n"
    ) % (gate_id, datetime.datetime.now().astimezone().isoformat(timespec="seconds"), GATE_QUESTION % len(commits),
         head_sha[:7], branch, lines, head_sha[:7], branch)
    prefix = "\n" if os.path.exists(gates_path) and os.path.getsize(gates_path) else ""
    with safefile.open_append(gates_path) as f:
        f.write(prefix + text)


def run(top, slug, state, want_gate, mr):
    if not mr.get("url"):
        raise Unknown("卡沒有 MR 連結（report.md 的 ## MR），mr.error=%s" % mr.get("error"))
    if not mr.get("head_sha"):
        raise Unknown("mr.head_sha 是空的（%s），mr.error=%s" % (mr["url"], mr.get("error")))
    if not re.fullmatch(r"[0-9a-f]{7,64}", mr["head_sha"]):
        raise Unknown("mr.head_sha %r 不是 sha（%s）" % (mr["head_sha"], mr["url"]))
    remote = remote_for(top, mr["url"])
    branch = branch_of(top, slug, state)
    commits = late_commits(top, remote, branch, mr["head_sha"])
    if not commits:
        print("none")
        return 0
    head7 = commits[0][0][:7]
    gate_id = "late-" + head7
    gates_path = os.path.join(top, "openspec", "changes", slug, "gates.md")
    status = gate_status(gates_path, gate_id)
    if status == "answered":
        print("acked " + head7)
        return 0
    print("late %d %s %s" % (len(commits), head7, branch))
    for sha, title in commits:
        print("%s %s" % (sha[:7], title))
    if want_gate and status is None:
        open_gate(gates_path, gate_id, commits, branch, mr["head_sha"])
    return 1


def main():
    top, slug, state, want_gate = sys.argv[1:5]
    try:
        return run(top, slug, state, want_gate == "1", json.loads(os.environ["OPSX_LATE_MR"]))
    except Unknown as e:
        print("opsx late: 查不出來：%s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
