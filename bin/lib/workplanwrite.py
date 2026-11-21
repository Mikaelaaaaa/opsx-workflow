"""workplan.yaml 的寫入端：在 `features:`、某 feature 的 `prs:`、某 PR 的 `changes:` 尾端加一項。
只插入新行，原有的行逐字不變（註解、引號、排版都留著）；寫完用 chain.load_workplan 讀回驗證。
寫入期間持 WorkplanLock，coordinate.mark_merged 改 status 時持同一把。

用法：
    sys.path.insert(0, os.environ["OPSX_LIB"]); import workplanwrite
    workplanwrite.add_feature(top, {"name": ..., "status": "active", "depends-on": [], "prs": [{...}]})
    workplanwrite.add_pr(top, <feature 名>, {"name": ..., "branch": ..., "changes": [{...}]})
    workplanwrite.add_change(top, <PR 名>, {"name": ..., "status": "pending"})
    $OPSX_PY -I workplanwrite.py attach <top> <卡> <父卡或空字串> <分支尾巴的名字> <kind 或空字串>   新卡掛進 workplan（common.sh 的 new_shell、dispatch 呼叫）
item 的值是字串、字串清單、或 mapping 清單（巢狀項目）；照 dict 順序寫出，第一個鍵要是 name。
"""
from __future__ import annotations

import fcntl
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chain  # noqa: E402
import priority  # noqa: E402
import safefile  # noqa: E402

NAME = re.compile(r"""^ *- name:\s*(?:"([^"]*)"|'([^']*)'|([^\s#]+))""")
# 每一層的子清單鍵與子項目的種類
CHILD = {"feature": ("prs", "PR"), "PR": ("changes", "change"), "change": (None, None)}
# 分支前綴，跟 dispatch.sh 沒有 workplan 時的對照相同；沒列的 kind 是 feat
KIND_PREFIX = {"bug-fix": "fix", "refactoring": "refactor", "ops": "chore", "chore": "chore"}


class WorkplanError(ValueError):
    pass


class WorkplanLock:
    """openspec/workplan.lock 上的獨占 flock。鎖固定鎖檔而不是 workplan.yaml：write_atomic 會換 inode。"""

    def __init__(self, top: str):
        self.path = os.path.join(top, "openspec", "workplan.lock")
        self.f = None

    def __enter__(self) -> "WorkplanLock":
        self.f = safefile.open_lock(self.path)
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc) -> None:
        self.f.close()


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _header(lines: list, key: str, start: int, end: int, indent: int):
    pat = re.compile(r"^ {%d}%s:\s*(#.*)?$" % (indent, re.escape(key)))
    return next((i for i in range(start, end) if pat.match(lines[i])), None)


def _items(lines: list, h: int) -> list:
    """lines[h] 是清單頭，回每一項的 (第一行, 結束後一行, 縮排, 名字)；底下沒有項目回空清單。
    最後一項結束在清單最後一行內容之後，所以清單後面接的註解與空行不算進去。"""
    hind = _indent(lines[h])
    ind, starts, last = None, [], None
    for j in range(h + 1, len(lines)):
        if not lines[j].strip() or lines[j].lstrip().startswith("#"):
            continue
        k, dash = _indent(lines[j]), lines[j].lstrip().startswith("- ")
        if ind is None:
            if k < hind or not dash:
                break
            ind = k
        if k < ind or (k == ind and not dash):
            break
        if k == ind:
            starts.append(j)
        last = j
    return [(s, e, ind, _name(lines[s])) for s, e in zip(starts, starts[1:] + [last + 1])] if starts else []


def _name(line: str):
    m = NAME.match(line)
    return next(g for g in m.groups() if g is not None) if m else None


def _children(lines: list, item: tuple, kind: str):
    """項目底下的子清單項目；沒有子清單頭是 None。"""
    key = CHILD[kind][0]
    h = _header(lines, key, item[0], item[1], item[2] + 2)
    return None if h is None else _items(lines, h)


def _open_empty(lines: list, key: str, start: int, end: int, indent: int):
    """`<key>: []` 那一行改成 `<key>:`（之後插入第一項），回它的 index；沒有這種行回 None。"""
    pat = re.compile(r"^ {%d}%s:\s*\[\]\s*(#.*)?$" % (indent, re.escape(key)))
    i = next((i for i in range(start, end) if pat.match(lines[i])), None)
    if i is not None:
        lines[i] = re.sub(r"\[\]\s*", "", lines[i], count=1).rstrip()
    return i


def _target(lines: list, path: str, kind: str, owner):
    """新項目要插入的 (行 index, 縮排)：目標清單最後一項的最後一行之後；清單是 `[]` 或底下沒有項目時就在清單頭之後。
    清單是 `[]` 時會先把 lines 裡那一行改成區塊清單的頭。"""
    h = _header(lines, "features", 0, len(lines), 0)
    if h is None:
        e = _open_empty(lines, "features", 0, len(lines), 0) if kind == "feature" else None
        if e is None:
            raise WorkplanError("%s 沒有 features:" % path)
        return e + 1, 2
    features = _items(lines, h)
    if kind == "feature":
        return (features[-1][1], features[-1][2]) if features else (h + 1, 2)
    parent = "feature" if kind == "PR" else "PR"
    owners = features if kind == "PR" else [p for f in features for p in _children(lines, f, "feature") or []]
    for item in owners:
        if item[3] != owner:
            continue
        e = _open_empty(lines, CHILD[parent][0], item[0], item[1], item[2] + 2)
        if e is not None:
            return e + 1, item[2] + 4
        ch = _header(lines, CHILD[parent][0], item[0], item[1], item[2] + 2)
        if ch is None:
            raise WorkplanError("workplan 的 %s %s 沒有 %s:" % (parent, owner, CHILD[parent][0]))
        sibs = _items(lines, ch)
        return (sibs[-1][1], sibs[-1][2]) if sibs else (ch + 1, item[2] + 4)
    raise WorkplanError("workplan 沒有 %s %s" % (parent, owner))


def _quote(field: str, v) -> str:
    if not isinstance(v, str) or '"' in v or "\\" in v or "\n" in v:
        raise WorkplanError("workplan 欄位 %s 的值 %r 不能寫成雙引號字串" % (field, v))
    return '"%s"' % v


def _render(item: dict, ind: int) -> list:
    out = []
    for n, (k, v) in enumerate(item.items()):
        lead = " " * ind + "- " if n == 0 else " " * (ind + 2)
        if isinstance(v, list) and v and all(isinstance(x, dict) for x in v):
            out.append("%s%s:" % (lead, k))
            for sub in v:
                out += _render(sub, ind + 4)
        elif isinstance(v, list):
            out.append("%s%s: [%s]" % (lead, k, ", ".join(_quote(k, x) for x in v)))
        else:
            out.append("%s%s: %s" % (lead, k, _quote(k, v)))
    return out


def _new_names(item: dict, kind: str) -> list:
    """新項目與它底下巢狀項目的 (種類, 名字)。"""
    if next(iter(item), None) != "name" or not item["name"]:
        raise WorkplanError("新 %s 的第一個欄位要是非空的 name，拿到 %r" % (kind, item))
    key, sub = CHILD[kind]
    out = [(kind, item["name"])]
    for x in (item.get(key) or []) if key else []:
        out += _new_names(x, sub)
    return out


def _existing(wp: dict) -> set:
    features = wp.get("features") or []
    prs = [p for f in features for p in f.get("prs") or []]
    changes = [c for p in prs for c in p.get("changes") or []]
    return ({("feature", x.get("name")) for x in features} | {("PR", x.get("name")) for x in prs}
            | {("change", x.get("name")) for x in changes})


def _found(wp: dict, kind: str, owner, name: str) -> bool:
    features = wp.get("features") or []
    if kind == "feature":
        return any(f.get("name") == name for f in features)
    if kind == "PR":
        return any(p.get("name") == name for f in features if f.get("name") == owner for p in f.get("prs") or [])
    prs = [p for f in features for p in f.get("prs") or [] if p.get("name") == owner]
    return any(c.get("name") == name for p in prs for c in p.get("changes") or [])


def _add(top: str, kind: str, owner, item: dict) -> None:
    path = os.path.join(top, "openspec", "workplan.yaml")
    names = _new_names(item, kind)
    with WorkplanLock(top):
        taken = [n for n in names if n in _existing(chain.load_workplan(path))]
        if taken:
            raise WorkplanError("workplan 已經有 %s" % "、".join("%s %s" % n for n in taken))
        with open(path, encoding="utf-8") as f:
            old = f.read()
        lines = old.split("\n")
        at, ind = _target(lines, path, kind, owner)
        lines[at:at] = _render(item, ind)
        safefile.write_atomic(path, "\n".join(lines))
        if not _found(chain.load_workplan(path), kind, owner, item["name"]):
            safefile.write_atomic(path, old)
            raise WorkplanError("寫入後讀回 %s 找不到 %s %s，已還原" % (path, kind, item["name"]))


def add_feature(top: str, item: dict) -> None:
    _add(top, "feature", None, item)


def add_pr(top: str, feature: str, item: dict) -> None:
    _add(top, "PR", feature, item)


def add_change(top: str, pr: str, item: dict) -> None:
    _add(top, "change", pr, item)


def _rebranch(top: str, slug: str, kind: str) -> None:
    """卡的 PR branch 是建卡時照 type 寫的（`feat|fix/<slug>/<尾巴>`）、而且還沒建出來，就改成 kind 的前綴（workplan-attach D14）。
    其他形式的 branch 是人寫的，不動。"""
    path = os.path.join(top, "openspec", "workplan.yaml")
    with WorkplanLock(top):
        with open(path, encoding="utf-8") as f:
            old = f.read()
        lines = old.split("\n")
        h = _header(lines, "features", 0, len(lines), 0)
        prs = [p for f in (_items(lines, h) if h is not None else []) for p in _children(lines, f, "feature") or []]
        pr = next((p for p in prs if p[3] == slug), None)
        if pr is None:
            return
        pat = re.compile(r"""^ {%d}branch:\s*["']?(feat|fix)/%s/([^"'\s/]+)["']?\s*$""" % (pr[2] + 2, re.escape(slug)))
        at = next((i for i in range(pr[0], pr[1]) if pat.match(lines[i])), None)
        if at is None:
            return
        m = pat.match(lines[at])
        was, new = "%s/%s/%s" % (m[1], slug, m[2]), "%s/%s/%s" % (KIND_PREFIX.get(kind, "feat"), slug, m[2])
        if new == was or subprocess.run(["git", "-C", top, "show-ref", "--verify", "--quiet", "refs/heads/" + was]).returncode == 0:
            return
        lines[at] = '%sbranch: "%s"' % (" " * (pr[2] + 2), new)
        safefile.write_atomic(path, "\n".join(lines))
        got = priority.owners(chain.load_workplan(path).get("features") or []).get(slug)
        if got is None or got[1].get("branch") != new:
            safefile.write_atomic(path, old)
            raise WorkplanError("改寫後讀回 %s 的 %s branch 不是 %s，已還原" % (path, slug, new))


def attach(top: str, slug: str, parent: str, user: str, kind: str) -> None:
    """把已建殼的卡掛進 workplan（workplan-attach D1、D2、D7–D9、D16、D18；母卡 me-20261118-1113 D7–D9）。
    repo 沒有 workplan 就不動；卡已在 workplan 時，有給 kind（dispatch）只做 _rebranch。parent 空字串時取卡的 source: agent:<卡>，<主>--<子> 取主殼；
    父卡名不是 PR／change 名時當成 feature 名找（feature session 的 agent），都找不到當成沒有父卡。
    卡是 P2、父卡的 feature 不是 complete 就在它底下加 PR；否則（含 P0／P1 的卡）自成 feature，
    milestone 沿用父 feature 的，沒有父卡用 current_milestone。掛入前是 P2 就先寫自動的 P2 覆寫再寫 workplan，
    中間不會有一刻卡變成 P1 被協調者派走。kind 空字串時讀卡的 .openspec.yaml，還沒有 kind 就照 type 定前綴。"""
    if not os.path.exists(os.path.join(top, "openspec", "workplan.yaml")):
        return
    plan = priority.load_plan(top)
    own = priority.owners(plan["features"])
    if slug in own:
        if kind:
            _rebranch(top, slug, kind)
        return
    if not user:
        raise WorkplanError("分支尾巴沒有名字：OPSX_USER 沒設，git config user.name 是空的或占位字「Your Name」")
    inbox = os.path.join(top, "openspec", "changes", slug, "inbox.md")
    fm, _ = priority.frontmatter(priority.read_text(inbox))
    if not parent and (fm.get("source") or "").startswith("agent:"):
        parent = fm["source"][len("agent:"):]
    parent = parent.split("--")[0]
    by_feature = {f.get("name"): f for f in plan["features"]}
    owner = own[parent][0] if parent in own else by_feature.get(parent)
    got = priority.levels(top)[slug]
    if "error" in got:
        raise WorkplanError(got["error"])
    if got["level"] == "P2" and not fm.get("priority"):
        priority.set_override(inbox, "P2", "自動掛進 workplan，維持 P2", True)
    if not kind:
        m = re.search(r"^kind:\s*(\S+)", priority.read_text(os.path.join(top, "openspec", "changes", slug, ".openspec.yaml")), re.M)
        kind = m.group(1) if m else ""
    prefix = KIND_PREFIX.get(kind, "feat") if kind else ("fix" if fm.get("type") == "bug" else "feat")
    pr = {"name": slug, "branch": "%s/%s/%s" % (prefix, slug, user),
          "status": "pending", "depends-on": [], "changes": [{"name": slug, "status": "pending"}]}
    if owner is not None and owner.get("status") != "complete" and got["level"] == "P2":
        add_pr(top, owner["name"], pr)
        return
    feature = {"name": slug}
    milestone = owner.get("milestone") if owner is not None else plan["current"]
    if milestone:
        feature["milestone"] = milestone
    feature.update({"status": "active", "depends-on": [], "prs": [pr]})
    add_feature(top, feature)


if __name__ == "__main__":
    if len(sys.argv) != 7 or sys.argv[1] != "attach":
        sys.exit("用法：workplanwrite.py attach <top> <卡 slug> <父卡 slug 或空字串> <分支尾巴的名字> <kind 或空字串>")
    try:
        attach(*sys.argv[2:])
    except (WorkplanError, priority.PriorityError) as e:
        sys.exit("workplan: %s" % e)
