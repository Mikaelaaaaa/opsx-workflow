"""opsx chain 的判斷：父卡合併後，workplan 裡哪幾張子卡可以接著做。

用法：python3 -I chain.py children <top> <repo> <父卡 slug> <dispatch.json>
印一行 `skip\t<原因>`（不接），或每張可接的子卡一行 `child\t<slug>\t<branch>\t<kind>`。
python3 -I chain.py fan-out <dispatch.json>：寫代管條目（register_fan_out），印父卡原本的 mode。
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


def children(top: str, repo: str, parent: str, dispatch_path: str) -> list:
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
    prs = [pr for f in load_workplan(wp_path).get("features") or [] for pr in f.get("prs") or []]
    mine = [pr for pr in prs if any(c.get("name") == parent for c in pr.get("changes") or [])]
    if not mine:
        return [("skip", "workplan 裡沒有 %s" % parent)]
    status = {pr.get("name"): pr.get("status") for pr in prs}
    out = []
    for pr in prs:
        deps = pr.get("depends-on") or []
        if mine[0].get("name") not in deps or pr.get("status") == "merged":
            continue
        if any(status.get(dep) != "merged" for dep in deps):
            continue
        todo = [c.get("name") for c in pr.get("changes") or [] if c.get("status") != "done"]
        if not todo:
            continue
        slug = todo[0]   # 一個 PR 一條 branch；同 PR 的其他 change 由接手的 agent 依序做
        card = os.path.join(top, "openspec", "changes", slug)
        if not os.path.exists(os.path.join(card, "tasks.md")):
            continue
        entry = dispatch.get("%s/%s" % (repo, slug))
        if entry and entry.get("mode") != "stopped":
            continue
        out.append(("child", slug, pr.get("branch") or "", _kind(card)))
    return out or [("skip", "沒有可以接的子卡")]


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
        d["%s/%s" % (repo, slug)] = {
            "workspace": me.get("workspace"), "workspace_id": me.get("workspace_id"), "tab": me.get("tab"), "pane": me.get("pane"),
            "agent": me.get("agent"), "model": model, "mode": mode, "kind": kind, "worktree": None, "branch": branch,
            "grants": [], "once": [], "started_at": e["OPSX_AT"], "drive_pid": None,
            "via": e["OPSX_PARENT"], "herdr_name": me.get("herdr_name") or e["OPSX_PARENT"]}
    me["handed_to"] = kids
    me["handed_at"] = e["OPSX_AT"]


if __name__ == "__main__":
    if len(sys.argv) == 6 and sys.argv[1] == "children":
        for row in children(*sys.argv[2:]):
            print("\t".join(row))
    elif len(sys.argv) == 3 and sys.argv[1] == "fan-out":
        print(jsonfile.load(sys.argv[2])[os.environ["OPSX_KEY"]].get("mode"))
        jsonfile.update(sys.argv[2], register_fan_out)
    else:
        sys.exit("用法：chain.py children <top> <repo> <父卡 slug> <dispatch.json> | chain.py fan-out <dispatch.json>")
