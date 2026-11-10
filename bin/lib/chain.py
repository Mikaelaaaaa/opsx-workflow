"""opsx chain 的判斷：父卡合併後，workplan 裡哪幾張子卡可以接著做。

用法：$OPSX_PY -I chain.py children <top> <repo> <父卡 slug> <dispatch.json>
印一行 `skip\t<原因>`（不接），或每張可接的子卡一行 `child\t<slug>\t<branch>\t<kind>`。
$OPSX_PY -I chain.py continue <dispatch.json>：單一子卡接手（register_continue），印父卡原本的 herdr 名和 mode。
$OPSX_PY -I chain.py fan-out <dispatch.json>：寫代管條目（register_fan_out），印父卡原本的 mode。
specs/opsx-chain/spec.md「找出可以續接的子卡」。
"""
from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfile  # noqa: E402


def _scalar(v: str):
    v = v.strip()
    if v.startswith("[") and v.endswith("]"):
        return [_scalar(x) for x in v[1:-1].split(",") if x.strip()]
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def _lines(path: str) -> list:
    out = []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            s = raw.rstrip("\n")
            if not s.strip() or s.lstrip().startswith("#"):
                continue
            if '"' not in s and "'" not in s:
                s = re.sub(r"\s+#.*$", "", s)
            out.append([len(s) - len(s.lstrip(" ")), s.strip()])
    return out


def _block(lines: list, i: int, ind: int):
    """從 lines[i] 起解析縮排為 ind 的 block（mapping 或 `- ` 開頭的 list），回 (值, 下一行的 index)。"""
    if lines[i][1].startswith("- "):
        items = []
        while i < len(lines) and lines[i][0] == ind and lines[i][1].startswith("- "):
            body = lines[i][1][2:]
            if ":" not in body:
                items.append(_scalar(body)); i += 1; continue
            lines[i] = [ind + 2, body]   # "- k: v" 是縮排 ind+2 的 mapping 的第一行
            val, i = _block(lines, i, ind + 2)
            items.append(val)
        return items, i
    m = {}
    while i < len(lines) and lines[i][0] == ind and not lines[i][1].startswith("- "):
        k, _, v = lines[i][1].partition(":")
        i += 1
        if v.strip():
            m[k.strip()] = _scalar(v)
        elif i < len(lines) and lines[i][0] > ind:
            m[k.strip()], i = _block(lines, i, lines[i][0])
        else:
            m[k.strip()] = None
    return m, i


def load_workplan(path: str) -> dict:
    """workplan.yaml 用到的 YAML 子集：block mapping、block list、[a, b]、引號字串、# 註解。不依賴 pyyaml。"""
    lines = _lines(path)
    return _block(lines, 0, lines[0][0])[0] if lines else {}


def _kind(card_dir: str) -> str:
    try:
        with open(os.path.join(card_dir, ".openspec.yaml"), encoding="utf-8") as f:
            m = re.search(r"^kind:\s*(\S+)", f.read(), re.M)
    except FileNotFoundError:
        return "dev"
    return m.group(1) if m else "dev"


def find_pr(prs: list, slug: str):
    """slug 是 PR 名（主 change 的殼名）或 PR 底下的 change 名，回它所屬的 PR；workplan 裡沒有回 None。"""
    for pr in prs:
        if pr.get("name") == slug:
            return pr
    for pr in prs:
        if any(c.get("name") == slug for c in pr.get("changes") or []):
            return pr
    return None


def card_of(top: str, pr: dict, todo: list) -> str:
    """PR 對到的卡：PR 名不是自己底下的 change 名、且 openspec/changes/<PR 名>/ 在，就是主殼；
    否則是舊卡（PR 名可能等於第一個 change 名），取第一個還沒 done 的 change。"""
    own = [c.get("name") for c in pr.get("changes") or []]
    if pr["name"] not in own and os.path.isdir(os.path.join(top, "openspec", "changes", pr["name"])):
        return pr["name"]
    return todo[0]   # 一個 PR 一條 branch；同 PR 的其他 change 由接手的 agent 依序做


def children(top: str, repo: str, parent: str, dispatch_path: str) -> list:
    """父卡的條目有 feature（一個 session 代管整個 feature）時，同 feature 的主 change 印 session 行，
    別的 feature、以及有自己 depends-on 的 feature，由 coordinate 依 feature 的 depends-on 派，這裡不接。"""
    dispatch = jsonfile.load(dispatch_path)
    me = dispatch.get("%s/%s" % (repo, parent))
    if not me:
        return [("skip", "%s/%s 不在 dispatch.json（人手動開的 pane），不續接" % (repo, parent))]
    if me.get("mode") == "stopped":
        return [("skip", "%s/%s 已經停止，不續接" % (repo, parent))]
    if me.get("handed_to"):
        return [("skip", "%s/%s 已經交接給 %s" % (repo, parent, "、".join(me["handed_to"])))]
    wp_path = os.path.join(top, "openspec", "workplan.yaml")
    if not os.path.exists(wp_path):
        return [("skip", "沒有 openspec/workplan.yaml，不知道誰依賴 %s" % parent)]
    features = load_workplan(wp_path).get("features") or []
    prs = [pr for f in features for pr in f.get("prs") or []]
    feature_of = {pr.get("name"): f.get("name") for f in features for pr in f.get("prs") or []}
    mine = find_pr(prs, parent)
    if mine is None:
        return [("skip", "workplan 裡沒有 %s" % parent)]
    session = me.get("feature")
    gated = {f.get("name") for f in features if f.get("depends-on")}   # 有自己依賴的 feature，由 coordinate 照 feature 依賴派
    status = {pr.get("name"): pr.get("status") for pr in prs}
    out = []
    for pr in prs:
        deps = pr.get("depends-on") or []
        if mine.get("name") not in deps or pr.get("status") == "merged":
            continue
        owner = feature_of.get(pr.get("name"))
        if (session or owner in gated) and owner != session:
            continue
        if any(status.get(dep) != "merged" for dep in deps):
            continue
        todo = [c.get("name") for c in pr.get("changes") or [] if c.get("status") != "done"]
        if not todo:
            continue
        slug = card_of(top, pr, todo)
        card = os.path.join(top, "openspec", "changes", slug)
        if not os.path.exists(os.path.join(card, "tasks.md")):
            continue
        entry = dispatch.get("%s/%s" % (repo, slug))
        if entry and entry.get("mode") != "stopped":
            continue
        if not pr.get("branch"):
            sys.exit("chain: workplan 的 PR「%s」沒有 branch，續接不知道要開哪條 branch；在 workplan 補上 branch" % pr.get("name"))
        out.append(("session" if session else "child", slug, pr["branch"], _kind(card)))
    return out or [("skip", "沒有可以接的子卡")]


def feature_plan(top: str, feature: str) -> list:
    """opsx dispatch --feature：feature 底下現在能開工的主 change，(卡名, branch, kind) 依 workplan 順序。
    能開工 = PR 沒合、depends-on 都合了、還有沒 done 的 change、卡有 tasks.md。沒有這個 feature 或一個都不能開工就 exit。"""
    wp_path = os.path.join(top, "openspec", "workplan.yaml")
    features = load_workplan(wp_path).get("features") if os.path.exists(wp_path) else []
    hit = [f for f in features or [] if f.get("name") == feature]
    if not hit:
        sys.exit("dispatch: workplan 沒有 feature「%s」" % feature)
    status = {pr.get("name"): pr.get("status") for f in features for pr in f.get("prs") or []}
    out = []
    for pr in hit[0].get("prs") or []:
        if pr.get("status") == "merged" or any(status.get(d) != "merged" for d in pr.get("depends-on") or []):
            continue
        todo = [c.get("name") for c in pr.get("changes") or [] if c.get("status") != "done"]
        if not todo:
            continue
        slug = card_of(top, pr, todo)
        card = os.path.join(top, "openspec", "changes", slug)
        if not os.path.exists(os.path.join(card, "tasks.md")):
            continue
        if not pr.get("branch"):
            sys.exit("dispatch: workplan 的 PR「%s」沒有 branch" % pr.get("name"))
        out.append((slug, pr["branch"], _kind(card)))
    if not out:
        sys.exit("dispatch: feature「%s」現在沒有能開工的主 change（都合了、依賴沒合，或還沒 propose）" % feature)
    return out


def session_siblings(top: str, repo: str, slug: str, dispatch_path: str) -> list:
    """opsx next：<slug> 的條目帶 feature 時，同 feature、沒停掉的其他卡，依 workplan 的 PR 順序；不是 session 代管回空。"""
    dispatch = jsonfile.load(dispatch_path)
    feature = (dispatch.get("%s/%s" % (repo, slug)) or {}).get("feature")
    if not feature:
        return []
    cards = [k.split("/", 1)[1] for k, v in dispatch.items()
             if k.startswith(repo + "/") and k != "%s/%s" % (repo, slug) and v.get("feature") == feature and v.get("mode") != "stopped"
             and os.path.isdir(os.path.join(top, "openspec", "changes", k.split("/", 1)[1]))]   # 已歸檔的卡不算
    wp_path = os.path.join(top, "openspec", "workplan.yaml")
    prs = [pr for f in load_workplan(wp_path).get("features") or [] for pr in f.get("prs") or []] if os.path.exists(wp_path) else []
    order = [pr.get("name") for pr in prs]
    rank = {}
    for c in cards:
        pr = find_pr(prs, c)
        rank[c] = order.index(pr["name"]) if pr else len(order)   # workplan 裡沒有的排最後
    return sorted(cards, key=rank.__getitem__)


def sub_deps(top: str, main: str, sub: str) -> list:
    """opsx stack：主 change <main> 的 PR 底下子 change <sub> 的 depends-on。workplan 沒有這個 PR 或子 change 就 exit。"""
    wp_path = os.path.join(top, "openspec", "workplan.yaml")
    prs = [pr for f in load_workplan(wp_path).get("features") or [] for pr in f.get("prs") or []] if os.path.exists(wp_path) else []
    pr = next((p for p in prs if p.get("name") == main), None)
    if pr is None:
        sys.exit("stack: workplan 沒有主 change（PR）「%s」" % main)
    hit = [c for c in pr.get("changes") or [] if c.get("name") == sub]
    if not hit:
        sys.exit("stack: workplan 的 PR「%s」底下沒有子 change「%s」" % (main, sub))
    return hit[0].get("depends-on") or []


def _child_entry(me: dict, slug: str, branch: str, kind: str, model: str, mode: str, worktree, now: str) -> dict:
    return {"workspace": me.get("workspace"), "workspace_id": me.get("workspace_id"), "tab": me.get("tab"), "pane": me.get("pane"),
            "agent": me.get("agent"), "model": model, "mode": mode, "kind": kind, "worktree": worktree, "branch": branch,
            "grants": [], "once": [], "started_at": now, "drive_pid": None}


def register_continue(d: dict) -> None:
    """jsonfile.update 的 mutate：單一子卡接手父卡的 pane。父卡的 herdr agent 會被改名成子卡，herdr_name 跟著改。"""
    e = os.environ
    me = d[e["OPSX_KEY"]]
    repo = e["OPSX_KEY"].split("/", 1)[0]
    slug, branch, kind, model = e["OPSX_PLAN"].split("\t")
    entry = _child_entry(me, slug, branch, kind, model, me.get("mode"), e["OPSX_WT"], e["OPSX_AT"])
    entry["herdr_name"] = slug
    d["%s/%s" % (repo, slug)] = entry
    me["handed_to"] = [slug]
    me["handed_at"] = e["OPSX_AT"]
    me["herdr_name"] = slug


def register_session(d: dict) -> None:
    """jsonfile.update 的 mutate：feature session 接下一個主 change。pane、herdr 名、feature 沿用父主 change 的條目，父主 change 不記交接。"""
    e = os.environ
    me = d[e["OPSX_KEY"]]
    repo = e["OPSX_KEY"].split("/", 1)[0]
    slug, branch, kind, model = e["OPSX_PLAN"].split("\t")
    entry = _child_entry(me, slug, branch, kind, model, me.get("mode"), me.get("worktree"), e["OPSX_AT"])
    entry["herdr_name"] = entry["via"] = entry["feature"] = me["feature"]
    d["%s/%s" % (repo, slug)] = entry


def register_fan_out(d: dict) -> None:
    """jsonfile.update 的 mutate：替每張子卡寫代管條目，父卡記交接。參數走環境變數（OPSX_KEY、OPSX_PARENT、OPSX_PLAN、OPSX_AT）。"""
    e = os.environ
    me = d[e["OPSX_KEY"]]
    repo = e["OPSX_KEY"].split("/", 1)[0]
    mode = "autopilot" if me.get("mode") == "drive" else me.get("mode")
    kids = []
    for line in e["OPSX_PLAN"].splitlines():
        slug, branch, kind, model = line.split("\t")
        kids.append(slug)
        entry = _child_entry(me, slug, branch, kind, model, mode, None, e["OPSX_AT"])
        entry["via"] = e["OPSX_PARENT"]
        entry["herdr_name"] = me.get("herdr_name") or e["OPSX_PARENT"]
        d["%s/%s" % (repo, slug)] = entry
    me["handed_to"] = kids
    me["handed_at"] = e["OPSX_AT"]


if __name__ == "__main__":
    if len(sys.argv) == 6 and sys.argv[1] == "children":
        for row in children(*sys.argv[2:]):
            print("\t".join(row))
    elif len(sys.argv) == 3 and sys.argv[1] == "continue":
        me = jsonfile.load(sys.argv[2])[os.environ["OPSX_KEY"]]
        old_name, mode = me.get("herdr_name") or os.environ["OPSX_PARENT"], me.get("mode")
        jsonfile.update(sys.argv[2], register_continue)
        print(old_name, mode)   # 寫成功才印：chain.sh 靠退出碼判斷寫入成敗
    elif len(sys.argv) == 6 and sys.argv[1] == "siblings":
        print("\n".join(session_siblings(*sys.argv[2:])))
    elif len(sys.argv) == 5 and sys.argv[1] == "deps":
        print("\n".join(sub_deps(*sys.argv[2:])))
    elif len(sys.argv) == 4 and sys.argv[1] == "feature":
        for row in feature_plan(sys.argv[2], sys.argv[3]):
            print("\t".join(row))
    elif len(sys.argv) == 3 and sys.argv[1] == "session":
        jsonfile.update(sys.argv[2], register_session)
        print(jsonfile.load(sys.argv[2])[os.environ["OPSX_KEY"]]["feature"])
    elif len(sys.argv) == 3 and sys.argv[1] == "fan-out":
        print(jsonfile.load(sys.argv[2])[os.environ["OPSX_KEY"]].get("mode"))
        jsonfile.update(sys.argv[2], register_fan_out)
    else:
        sys.exit("用法：chain.py children <top> <repo> <父卡 slug> <dispatch.json> | chain.py feature <top> <feature> | chain.py deps <top> <主> <子> | chain.py continue|session|fan-out <dispatch.json>")
