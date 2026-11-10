"""卡的等級：依收件卡 frontmatter 的事實與 workplan 的 milestone 算 P0 / P1 / P2，再沿依賴反向繼承。

用法：$OPSX_PY -I priority.py get <top> <slug>      印 `<level>\t<理由>`，算不出來 stderr 說明、退出 1
      $OPSX_PY -I priority.py set <inbox.md> <level> <理由>   覆寫等級，寫 frontmatter 的 priority / priority_reason
規則：references/priority.md；specs/opsx-priority/spec.md。coordinate、chain、collect import 這個模組，不另算。
"""
from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chain  # noqa: E402
import safefile  # noqa: E402

LEVELS = ("P0", "P1", "P2")
KINDS = ("incident", "planned")
IMPACT_P0 = ("security", "data", "prod_or_main")
IMPACT_P1 = ("workaround_exists", "blocks_all_agents")


class PriorityError(Exception):
    """事實欄位或 workplan 的 milestone 欄位不合格；訊息指名卡或欄位與值。"""


class WorkplanUnreadable(PriorityError):
    """workplan 本身讀不懂（不是 UTF-8、features / prs / changes 不是 mapping list）。collect 的 session 段已經記這種錯，等級段不重記。"""


def mapping_list(v, where: str) -> list:
    """key 不在或空是 []，其餘要是 mapping 的 list。"""
    v = v or []
    if not isinstance(v, list) or not all(isinstance(x, dict) for x in v):
        raise WorkplanUnreadable("workplan 的 %s 要是 mapping 的 list，收到「%s」" % (where, v))
    return v


def unquote(v: str) -> str:
    return v[1:-1] if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'" else v


def frontmatter(text: str) -> tuple:
    """檔頭兩行 `---` 之間的 `key: value`，與每個 key 底下縮排續行的 [(key, value)]（巢狀寫法）。沒有 frontmatter 回 ({}, {})。"""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, {}
    out, nested, last = {}, {}, None
    for line in lines[1:]:
        if line.strip() == "---":
            return out, nested
        k, sep, v = line.strip().partition(":")
        if line[:1] in (" ", "\t") and line.strip():
            if last:
                nested.setdefault(last, []).append((k.strip(), unquote(v.strip()) if sep else ""))
            continue
        if sep:
            last = k.strip()
            out[last] = v.strip()
    return {}, {}


def nested_impact(slug: str, children: list) -> tuple:
    """D3 字面的寫法：`impact:` 底下縮排 `<值>: true|false`，可帶一行縮排的 `evidence:`。回 (成立的 impact, evidence)。"""
    impact, evidence = [], ""
    for k, v in children:
        if k == "evidence":
            evidence = v
        elif k not in IMPACT_P0 + IMPACT_P1:
            raise PriorityError("%s：impact 不認得「%s」，要是 %s 之一" % (slug, k, "、".join(IMPACT_P0 + IMPACT_P1)))
        elif v not in ("true", "false"):
            raise PriorityError("%s：impact 的 %s 要是 true 或 false，收到「%s」" % (slug, k, v))
        elif v == "true":
            impact.append(k)
    return impact, evidence


def facts_of(slug: str, text: str) -> dict:
    fm, nested = frontmatter(text)
    for k in ("kind_of_work", "evidence", "priority", "priority_reason"):
        if k in nested:
            raise PriorityError("%s：%s 要寫成同一行的 key: value，不能用縮排的巢狀寫法" % (slug, k))
    kind = fm.get("kind_of_work") or "planned"   # 沒寫的卡是 planned（agent 開的卡預設）
    if kind not in KINDS:
        raise PriorityError("%s：kind_of_work 要是 incident 或 planned，收到「%s」" % (slug, kind))
    if "impact" in nested and fm.get("impact"):
        raise PriorityError("%s：impact 同一行有值又有縮排的巢狀寫法，只能擇一" % slug)
    if "impact" in nested:
        impact, inner_evidence = nested_impact(slug, nested["impact"])
        fm["evidence"] = fm.get("evidence") or inner_evidence
    else:
        impact = [x.strip() for x in (fm.get("impact") or "").split(",") if x.strip()]
    for x in impact:
        if x not in IMPACT_P0 + IMPACT_P1:
            raise PriorityError("%s：impact 不認得「%s」，要是 %s 之一" % (slug, x, "、".join(IMPACT_P0 + IMPACT_P1)))
    if impact and not fm.get("evidence"):
        raise PriorityError("%s：impact 有 %s 但 evidence 是空的；沒有證據不能填 impact" % (slug, "、".join(impact)))
    override = fm.get("priority")
    if override and override not in LEVELS:
        raise PriorityError("%s：priority 要是 P0、P1、P2，收到「%s」" % (slug, override))
    if override and not fm.get("priority_reason"):
        raise PriorityError("%s：priority 是 %s 但 priority_reason 是空的；改等級要寫理由（opsx priority --set … --reason …）" % (slug, override))
    return {"kind": kind, "impact": impact, "priority": override, "priority_reason": fm.get("priority_reason") or ""}


def card_dirs(top: str) -> dict:
    """slug 到殼的目錄：changes/<slug>/ 與主殼底下的 subs/<slug>/，不含 archive。"""
    base = os.path.join(top, "openspec", "changes")
    out = {}
    for name in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        d = os.path.join(base, name)
        if name == "archive" or not os.path.isdir(d):
            continue
        out[name] = d
        subs = os.path.join(d, "subs")
        for sub in sorted(os.listdir(subs)) if os.path.isdir(subs) else []:
            if os.path.isdir(os.path.join(subs, sub)):
                out.setdefault(sub, os.path.join(subs, sub))
    return out


def read_text(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def load_plan(top: str) -> dict:
    """workplan 與 milestone 欄位的驗證；沒有 workplan 等於空的。"""
    path = os.path.join(top, "openspec", "workplan.yaml")
    try:
        wp = chain.load_workplan(path) if os.path.exists(path) else {}
    except UnicodeDecodeError as e:
        raise WorkplanUnreadable("workplan 不是 UTF-8：%s（%s）" % (path, e)) from e
    features = mapping_list(wp.get("features"), "features")
    for f in features:
        for pr in mapping_list(f.get("prs"), "feature %s 的 prs" % f.get("name")):
            mapping_list(pr.get("changes"), "PR %s 的 changes" % pr.get("name"))
    for m in wp.get("milestones") or []:
        if not isinstance(m, dict) or not isinstance(m.get("name"), str) or not isinstance(m.get("goal"), str):
            raise PriorityError("workplan 的 milestones 每項要有字串 name 與 goal，收到「%s」" % (m,))
    goals = {m["name"]: m["goal"] for m in wp.get("milestones") or []}
    current = wp.get("current_milestone")
    if current is not None and not isinstance(current, str):
        raise PriorityError("workplan 的 current_milestone 要是一個名字，收到「%s」" % (current,))
    if current and current not in goals:
        raise PriorityError("workplan 的 current_milestone「%s」不在 milestones 裡（有：%s）" % (current, "、".join(goals) or "無"))
    for f in features:
        m = f.get("milestone")
        if m is not None and not isinstance(m, str):
            raise PriorityError("workplan 的 feature「%s」的 milestone 要是一個名字，收到「%s」" % (f.get("name"), m))
        if m and m not in goals:
            raise PriorityError("workplan 的 feature「%s」的 milestone「%s」不在 milestones 裡" % (f.get("name"), m))
    return {"features": features, "goals": goals, "current": current}


def owners(features: list) -> dict:
    """slug 到 (feature, pr)：change 名對到所屬 PR；PR 名本身也是一張卡（主 change 與 PR 同名）。"""
    out = {}
    for f in features:
        for pr in f.get("prs") or []:
            for c in pr.get("changes") or []:
                out.setdefault(c.get("name"), (f, pr))
    for f in features:
        for pr in f.get("prs") or []:
            out.setdefault(pr.get("name"), (f, pr))
    return out


def waiters(features: list) -> dict:
    """PR 名到「直接 depends-on 它的 PR 名」；feature 的 depends-on 算成它底下每個 PR 都依賴。"""
    out = {}
    for f in features:
        for pr in f.get("prs") or []:
            for dep in (pr.get("depends-on") or []) + (f.get("depends-on") or []):
                out.setdefault(dep, set()).add(pr.get("name"))
    return out


def base_level(slug: str, facts: dict, plan: dict, owner) -> tuple:
    if facts["priority"]:
        return facts["priority"], "%s：使用者：%s" % (facts["priority"], facts["priority_reason"]), True
    if facts["kind"] == "incident":
        hit = [x for x in facts["impact"] if x in IMPACT_P0]
        if hit:
            return "P0", "P0：%s（附證據）" % "、".join(hit), False
        hit = [x for x in facts["impact"] if x in IMPACT_P1]
        if hit:
            return "P1", "P1：%s" % "、".join(hit), False
        return "P2", "P2：incident，沒有 impact", False
    if owner is None:
        return "P2", "P2：不在 workplan", False
    m = owner[0].get("milestone")
    if not plan["current"]:
        return "P1", "P1：在 workplan 裡（沒設目前 milestone）", False
    if m == plan["current"]:
        return "P1", "P1：在 %s（%s）清單裡" % (m, plan["goals"][m]), False
    return "P2", "P2：%s，不是目前 milestone" % (("在 " + m) if m else "沒有 milestone"), False


def upstream(pr_name: str, wait: dict) -> list:
    """直接或間接在等 pr_name 的 PR 名，依走到的順序；有環就停在走過的節點。"""
    seen, todo, out = {pr_name}, [pr_name], []
    while todo:
        for nxt in sorted(wait.get(todo.pop(0), ())):
            if nxt not in seen:
                seen.add(nxt)
                todo.append(nxt)
                out.append(nxt)
    return out


def levels(top: str) -> dict:
    """一個 repo 所有卡：slug 到 {level, reason, overridden}，事實不合格的卡是 {error}。workplan 不合格 raise PriorityError。"""
    plan = load_plan(top)
    own = owners(plan["features"])
    dirs = card_dirs(top)
    slugs = sorted(set(dirs) | set(own))
    base = {}
    for s in slugs:
        try:
            facts = facts_of(s, read_text(os.path.join(dirs[s], "inbox.md")) if s in dirs else "")
        except PriorityError as e:
            base[s] = {"error": str(e)}
            continue
        lv, why, ov = base_level(s, facts, plan, own.get(s))
        base[s] = {"level": lv, "reason": why, "overridden": ov}
    cards_of = {}
    for s, (_, pr) in own.items():
        cards_of.setdefault(pr.get("name"), []).append(s)
    wait = waiters(plan["features"])
    out = {}
    for s in slugs:
        me = base[s]
        if "error" in me or me["overridden"] or s not in own:
            out[s] = me
            continue
        best = me
        for pr_name in upstream(own[s][1].get("name"), wait):
            for other in cards_of.get(pr_name, []):
                o = base[other]
                if "error" not in o and LEVELS.index(o["level"]) < LEVELS.index(best["level"]):
                    best = {"level": o["level"], "reason": "%s：%s 在等它" % (o["level"], other), "overridden": False}
        out[s] = best
    return out


def set_override(inbox: str, level: str, reason: str) -> None:
    """frontmatter 的 priority / priority_reason 改成新值（已有就取代，沒有就加在結尾 `---` 前）。"""
    if level not in LEVELS:
        raise PriorityError("等級要是 P0、P1、P2，收到「%s」" % level)
    reason = " ".join(reason.split())
    if not reason:
        raise PriorityError("改等級要寫理由")
    lines = read_text(inbox).split("\n")
    if not lines or lines[0].strip() != "---":
        raise PriorityError("%s 沒有 frontmatter" % inbox)
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        raise PriorityError("%s 的 frontmatter 沒有結尾的 ---" % inbox)
    body = [l for l in lines[1:end] if not re.match(r"^priority(_reason)?:", l)]
    new = [lines[0]] + body + ["priority: " + level, "priority_reason: " + reason] + lines[end:]
    safefile.write_atomic(inbox, "\n".join(new))


def main() -> None:
    args = sys.argv[1:]
    try:
        if len(args) == 3 and args[0] == "get":
            got = levels(args[1]).get(args[2])
            if got is None:
                raise PriorityError("沒有這張卡：%s（openspec/changes/ 與 workplan 都沒有）" % args[2])
            if "error" in got:
                raise PriorityError(got["error"])
            print("%s\t%s" % (got["level"], got["reason"]))
        elif len(args) == 4 and args[0] == "set":
            set_override(args[1], args[2], args[3])
        else:
            sys.exit("用法：priority.py get <top> <slug> | priority.py set <inbox.md> <level> <理由>")
    except PriorityError as e:
        print("priority: %s" % e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
