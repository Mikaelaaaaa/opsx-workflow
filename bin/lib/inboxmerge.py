"""目標卡 inbox.md 的 `## 併入：<時間> <來源>` 段：opsx new 追加、opsx split-out 拆回獨立的卡。

用法：
    $OPSX_PY -I inboxmerge.py append <卡目錄> <基本 id> <ISO 時間> <來源> <kind_of_work> <evidence> <type> <一句話>
        追加一段，印這段拿到的 id。id 是新卡原本會拿到的 slug；目標裡已經有同一個 id 時依序加 -2、-3。
        鎖內發現目標已有 tasks.md 或已拆就不寫，退出 4。
    $OPSX_PY -I inboxmerge.py card <卡目錄> <id>
        印那一段拆回獨立卡時的 inbox.md（跟 opsx new 寫的同形）。找不到退出 2。
    $OPSX_PY -I inboxmerge.py remove <卡目錄> <id>
        刪掉那一段，其餘位元組不動。找不到退出 2。
    $OPSX_PY -I inboxmerge.py ids <卡目錄>
        一行印一個這張卡現有的併入 id（opsx drop 用來拒絕還有併入項目的卡）。
    $OPSX_PY -I inboxmerge.py split-out <卡目錄> <id> <repo 根>
        同一個卡鎖內讀那一段、用 common.sh 的 new_shell 建殼、刪那一段；印新殼 slug。找不到那段退出 2，不建殼。
    $OPSX_PY -I inboxmerge.py evidence <卡目錄> <行>
        卡鎖內把一行插進 `## 證據` 段最後一行非空內容之後（opsx merge-card）。沒有證據段退出 1。
    $OPSX_PY -I inboxmerge.py carry <目標卡目錄> <來源 inbox 檔> <來源 slug>
        來源卡的 kind_of_work / impact / evidence / priority 覆寫併進目標卡 frontmatter（opsx merge-card，來源捨棄成功之後；來源 inbox 已複製出來）：
        kind_of_work 取較高，impact 取聯集，evidence 依 " ; " 去重接在後面，priority 取較高。
    $OPSX_PY -I inboxmerge.py carry-check <目標卡目錄> <來源 inbox 檔> <來源 slug>
        同上但不寫檔：只驗欄位合格與目標有 frontmatter（opsx merge-card，捨棄來源之前）。
    $OPSX_PY -I inboxmerge.py drop <卡目錄> <理由> -- <歸檔指令…>
        卡鎖內重查併入段（有就退出 1）、寫 outcome: declined 與 ## 捨棄理由、跑歸檔指令，鎖到指令結束才放。指令失敗退出 3。
兩個 agent 可能同時併進同一張卡：鎖在卡目錄上（inbox.md 會被原子替換換掉 inode，鎖它本身擋不住），鎖內重讀再改。
一段併入從標題到下一個 `## ` 或檔尾為止。specs/card-auto-merge「同檔案併入」「拆出來」。
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import priority  # noqa: E402
import safefile  # noqa: E402

HEAD = re.compile(r"^## ")
MERGED = re.compile(r"^## 併入：")
MERGED_HEAD = re.compile(r"^## 併入：(\S+) (\S+)\s*$")
ID_LINE = re.compile(r"^- id: (\S+)\s*$")
FIELD = re.compile(r"^- (id|kind_of_work|evidence|type|area): (.*)$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}")


SPLIT_INTO = re.compile(r"^split_into:\s*(.*?)\s*(#.*)?$")
SPLIT_EMPTY = re.compile(r"^(\[ *\]|\"\"|''|~|null)?$")


class SectionNotFound(LookupError):
    pass


class TargetStarted(Exception):
    """併入目標在 opsx new 判斷之後已開工（有 tasks.md）或已拆：這段不寫，opsx new 改建殼。"""


def split_into(text: str) -> str:
    """frontmatter 的 split_into 值，空值算沒有；判斷跟 stage.sh 的 st_split_into 一致。"""
    lines = text.split("\n")
    if not lines or not lines[0].startswith("---"):
        return ""
    for line in lines[1:]:
        if line.startswith("---"):
            return ""
        m = SPLIT_INTO.match(line.rstrip("\r"))
        if m:
            return "" if SPLIT_EMPTY.match(m.group(1)) else m.group(1)
    return ""


def merged_ids(text: str) -> set:
    ids, inside = set(), False
    for line in text.split("\n"):
        if HEAD.match(line):
            inside = bool(MERGED.match(line))
            continue
        m = ID_LINE.match(line) if inside else None
        if m:
            ids.add(m.group(1))
    return ids


def free_id(base: str, taken: set) -> str:
    if base not in taken:
        return base
    n = 2
    while "%s-%d" % (base, n) in taken:
        n += 1
    return "%s-%d" % (base, n)


def section(mid: str, when: str, source: str, kind: str, evidence: str, kind_type: str, text: str) -> str:
    lines = ["## 併入：%s %s" % (when, source), "", "- id: " + mid, "- kind_of_work: " + kind]
    if evidence:
        lines.append("- evidence: " + evidence)
    lines += ["- type: " + kind_type, "", text, ""]
    return "\n".join(lines)


def append(card_dir: str, base: str, when: str, source: str, kind: str, evidence: str, kind_type: str, text: str) -> str:
    inbox = os.path.join(card_dir, "inbox.md")
    with safefile.CardLock(card_dir):
        with open(inbox, encoding="utf-8") as f:
            cur = f.read()
        # opsx new 在鎖外判斷階段，這裡鎖內再查一次，免得併進剛開工或剛拆的卡。
        # tasks.md 由 agent 用 Write 寫，取不到這把鎖；晚到的併入由 Stop hook 的 check_merged 補查（hooks/openspec-stop-gate.sh）
        if os.path.exists(os.path.join(card_dir, "tasks.md")):
            raise TargetStarted("%s 已有 tasks.md，不併" % card_dir)
        if split_into(cur):
            raise TargetStarted("%s 已拆（split_into: %s），不併" % (card_dir, split_into(cur)))
        mid = free_id(base, merged_ids(cur))
        if cur and not cur.endswith("\n"):
            cur += "\n"
        if cur and not cur.endswith("\n\n"):
            cur += "\n"
        safefile.write_atomic(inbox, cur + section(mid, when, source, kind, evidence, kind_type, text))
    return mid


def find(text: str, mid: str) -> tuple:
    """含 `- id: <mid>` 的併入段，回傳 (起始行, 結束行之後)，行號以 keepends 切行計。"""
    lines = text.splitlines(keepends=True)
    heads = [i for i, x in enumerate(lines) if HEAD.match(x)] + [len(lines)]
    hits = [(a, b) for a, b in zip(heads, heads[1:]) if MERGED.match(lines[a]) and mid in merged_ids("".join(lines[a:b]))]
    if not hits:
        raise SectionNotFound("找不到含 `- id: %s` 的 `## 併入：` 段" % mid)
    if len(hits) > 1:
        raise ValueError("有 %d 段併入的 id 都是 %s，分不出要拆哪一段" % (len(hits), mid))
    return hits[0]


def parse(block: list) -> dict:
    """一段併入的行（不含換行）照 inboxmerge.section 的形狀拆成欄位；形狀不對就 raise 指出哪一行。"""
    m = MERGED_HEAD.match(block[0])
    if not m:
        raise ValueError("併入段標題不是「## 併入：<時間> <來源>」：%s" % block[0])
    if not DATE.match(m.group(1)):
        raise ValueError("併入段標題的時間不是 ISO 日期開頭：%s" % m.group(1))
    out = {"when": m.group(1), "source": m.group(2)}
    if len(block) < 2 or block[1] != "":
        raise ValueError("併入段標題後要空一行：%s" % block[0])
    i = 2
    while i < len(block) and block[i] != "":
        f = FIELD.match(block[i])
        if not f:
            raise ValueError("併入段的欄位行看不懂：%s" % block[i])
        out[f.group(1)] = f.group(2)
        i += 1
    for key in ("id", "kind_of_work"):
        if key not in out:
            raise ValueError("併入段少了 - %s:（標題 %s）" % (key, block[0]))
    # 新段寫 - type:，舊段（自動併入看 area 的時期）寫 - area:
    if "type" not in out and "area" not in out:
        raise ValueError("併入段要有 - type: 或 - area:（標題 %s）" % block[0])
    rest = block[i + 1:]
    if not rest or rest[0] == "" or any(x != "" for x in rest[1:]):
        raise ValueError("併入段欄位後要是空行加一行一句話（id %s）" % out["id"])
    out["text"] = rest[0]
    return out


def sections(text: str) -> list:
    """每段 `## 併入：` 依檔案順序回 (標題行, parse 的結果或它丟的 ValueError)；看板列項目、報格式錯誤用。"""
    lines = [x.rstrip("\n") for x in text.splitlines(keepends=True)]
    heads = [i for i, x in enumerate(lines) if HEAD.match(x)] + [len(lines)]
    out = []
    for a, b in zip(heads, heads[1:]):
        if not MERGED.match(lines[a]):
            continue
        try:
            out.append((lines[a], parse(lines[a:b])))
        except ValueError as e:
            out.append((lines[a], e))
    return out


def card_body(fields: dict) -> str:
    kind_type = fields["type"] if "type" in fields else "待定"   # 舊段沒有 type
    lines = ["---", "type: " + kind_type, "source: " + fields["source"], "found: " + fields["when"][:10], "related:", "kind_of_work: " + fields["kind_of_work"]]
    if "evidence" in fields:
        lines.append("evidence: " + fields["evidence"])
    lines += ["---", "", "## 一句話", "", fields["text"], "", "## 證據", "", ""]
    return "\n".join(lines)


def _card_unlocked(card_dir: str, mid: str) -> str:
    with open(os.path.join(card_dir, "inbox.md"), encoding="utf-8") as f:
        cur = f.read()
    start, end = find(cur, mid)
    return card_body(parse([x.rstrip("\n") for x in cur.splitlines(keepends=True)[start:end]]))


def card(card_dir: str, mid: str) -> str:
    with safefile.CardLock(card_dir):
        return _card_unlocked(card_dir, mid)


def _remove_unlocked(card_dir: str, mid: str) -> None:
    inbox = os.path.join(card_dir, "inbox.md")
    with open(inbox, encoding="utf-8") as f:
        cur = f.read()
    start, end = find(cur, mid)
    lines = cur.splitlines(keepends=True)
    safefile.write_atomic(inbox, "".join(lines[:start] + lines[end:]))


def remove(card_dir: str, mid: str) -> None:
    with safefile.CardLock(card_dir):
        _remove_unlocked(card_dir, mid)


def split_out(card_dir: str, mid: str, top: str) -> None:
    """同一個卡鎖內讀併入段、建新殼、刪併入段。新殼建好就先印它的 slug：刪段失敗時 split-out.sh 要告訴人哪張殼已建。"""
    common = os.path.join(os.path.dirname(os.path.abspath(__file__)), "common.sh")
    with safefile.CardLock(card_dir):
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".md") as body:
            body.write(_card_unlocked(card_dir, mid))
            body.flush()
            p = subprocess.run(["bash", "-c", 'source "$1"; new_shell "$2" "$3" "$4"', "opsx-split-out", common, top, mid, body.name],
                               stdout=subprocess.PIPE, text=True)
        if p.returncode != 0:
            raise ValueError("建殼失敗：new_shell 退出 %d（上面是原因）" % p.returncode)
        print(p.stdout.strip(), flush=True)
        _remove_unlocked(card_dir, mid)


def evidence(card_dir: str, line: str) -> None:
    """在卡鎖內把 line 插在 `## 證據` 段最後一行非空內容之後（段內沒有非空行就接在標題後空一行之後，跟 sync.py 的 append_to_section 同位置）。"""
    inbox = os.path.join(card_dir, "inbox.md")
    with safefile.CardLock(card_dir):
        with open(inbox, encoding="utf-8") as f:
            lines = f.read().split("\n")
        if "## 證據" not in lines:
            raise ValueError("%s 沒有 ## 證據 段" % inbox)
        sec = lines.index("## 證據")
        last = None
        for i in range(sec + 1, len(lines)):
            if HEAD.match(lines[i]):
                break
            if lines[i].strip():
                last = i
        if last is None:
            lines[sec + 1:sec + 1] = ["", line]
        else:
            lines.insert(last + 1, line)
        safefile.write_atomic(inbox, "\n".join(lines))


def rewrite_frontmatter(text: str, updates: dict, where: str) -> str:
    """frontmatter 裡 updates 的 key 改成同一行的 key: value（原本巢狀的縮排續行一併拿掉）；原本沒有的接在結尾 --- 前。
    where 是檔案路徑，沒有 frontmatter（第一行不是 ---，或沒有結尾 ---）時訊息指名它。"""
    lines = text.split("\n")
    end = next((i for i, x in enumerate(lines[1:], 1) if x.strip() == "---"), None)
    if lines[0].strip() != "---" or end is None:
        raise ValueError("%s 沒有 frontmatter（第一行要是 ---，並且有結尾的 ---）" % where)
    out, seen, skipping = [lines[0]], set(), False
    for x in lines[1:end]:
        if x[:1] in (" ", "\t") and x.strip():
            if not skipping:
                out.append(x)
            continue
        key = x.partition(":")[0].strip()
        skipping = key in updates
        if skipping:
            out.append("%s: %s" % (key, updates[key]))
            seen.add(key)
        else:
            out.append(x)
    out += ["%s: %s" % (k, v) for k, v in updates.items() if k not in seen]
    return "\n".join(out + lines[end:])


def facts(slug: str, text: str) -> dict:
    """{kind, impact 清單, evidence, priority, reason}；欄位不合格丟 ValueError，訊息指名卡與欄位。"""
    try:
        got = priority.facts_of(slug, text)
    except priority.PriorityError as e:
        raise ValueError(str(e)) from e
    fm, nested = priority.frontmatter(text)
    ev = fm.get("evidence") or (priority.nested_impact(slug, nested["impact"])[1] if "impact" in nested else "")
    return {"kind": got["kind"], "impact": got["impact"], "evidence": ev, "priority": got["priority"], "reason": got["priority_reason"]}


def carry(target_dir: str, source_inbox: str, source_slug: str, write: bool = True) -> None:
    """來源卡的事實欄位併進目標卡 frontmatter：kind_of_work 取較高（incident 高於 planned），impact 取聯集，
    evidence 依 " ; " 分段去重後接在後面，來源的 priority 覆寫比目標高（或目標沒有）就連同理由帶過去。
    來源沒有事實（planned、沒有 impact、沒有 evidence、沒有覆寫）就在解析目標之前返回，目標一個位元組都不動。
    等級由 opsx priority 從併完的欄位算。priority 覆寫只在比目標的有效等級（目標的覆寫，沒有就用併完的 kind 與 impact 算的等級）高時才帶過去。
    shortcut: 有效等級不看 workplan 的 milestone 位置，覆寫可能壓過目標因 milestone 得到的較高等級；併卡的來源與目標都在收件匣時沒差，到進了 workplan 的卡才要升級成用 priority.levels(top)
    write=False 只驗兩張卡的欄位合格、目標有 frontmatter（opsx merge-card 在捨棄來源之前呼叫），不寫檔。"""
    inbox = os.path.join(target_dir, "inbox.md")
    with open(source_inbox, encoding="utf-8") as f:
        s = facts(source_slug, f.read())
    if s["kind"] == "planned" and not (s["impact"] or s["evidence"] or s["priority"]):
        return
    with safefile.CardLock(target_dir):
        with open(inbox, encoding="utf-8") as f:
            text = f.read()
        t = facts(os.path.basename(target_dir), text)
        updates = {}
        if s["kind"] == "incident" and t["kind"] != "incident":
            updates["kind_of_work"] = "incident"
        impact = t["impact"] + [x for x in s["impact"] if x not in t["impact"]]
        parts = [x for x in dict.fromkeys(p for e in (t["evidence"], s["evidence"]) for p in e.split(" ; ")) if x]
        evidence = " ; ".join(parts)
        if impact != t["impact"]:
            updates["impact"] = ", ".join(impact)
        if evidence != t["evidence"] or "impact" in updates:   # 目標原本用巢狀寫法時，evidence 要跟著 impact 一起改成同一行
            updates["evidence"] = evidence
        effective = t["priority"] or priority.rule_level("incident" if "kind_of_work" in updates else t["kind"], impact, None, None)[0]
        if s["priority"] and priority.LEVELS.index(s["priority"]) < priority.LEVELS.index(effective):
            updates.update({"priority": s["priority"], "priority_reason": "併自 %s：%s" % (source_slug, s["reason"])})
        new = rewrite_frontmatter(text, updates, inbox)
        if write and new != text:
            safefile.write_atomic(inbox, new)


def drop(card_dir: str, reason: str, argv: list) -> int:
    """在卡鎖內重查併入段、寫 outcome 與捨棄理由、跑 argv（歸檔），到 argv 結束才放鎖。argv 失敗回 3。"""
    inbox = os.path.join(card_dir, "inbox.md")
    with safefile.CardLock(card_dir):
        if os.path.exists(inbox):
            with open(inbox, encoding="utf-8") as f:
                ids = sorted(merged_ids(f.read()))
            if ids:
                raise ValueError("還有併入的項目（%s），先用 opsx split-out 拆出來再捨棄" % " ".join(ids))
        with safefile.open_append(os.path.join(card_dir, ".openspec.yaml")) as f:
            f.write("outcome: declined\n")
        with safefile.open_append(inbox) as f:
            f.write("\n## 捨棄理由\n\n%s\n" % reason)
        return 0 if subprocess.run(argv).returncode == 0 else 3


def main() -> None:
    args = sys.argv[1:]
    cmd = args[0] if args else ""
    want = {"append": 9, "card": 3, "remove": 3, "ids": 2, "evidence": 3, "split-out": 4, "carry": 4, "carry-check": 4}
    ok = len(args) >= 5 and args[3] == "--" if cmd == "drop" else cmd in want and len(args) == want[cmd]
    if not ok:
        sys.exit("用法：inboxmerge.py append <卡目錄> <基本 id> <ISO 時間> <來源> <kind_of_work> <evidence> <type> <一句話> | card <卡目錄> <id> | remove <卡目錄> <id> | ids <卡目錄> | evidence <卡目錄> <行> | carry <目標卡目錄> <來源 inbox 檔> <來源 slug> | carry-check <目標卡目錄> <來源 inbox 檔> <來源 slug> | split-out <卡目錄> <id> <repo 根> | drop <卡目錄> <理由> -- <歸檔指令…>")
    try:
        if cmd == "append":
            print(append(*args[1:]))
        elif cmd == "split-out":
            split_out(*args[1:])
        elif cmd == "evidence":
            evidence(*args[1:])
        elif cmd == "carry":
            carry(*args[1:])
        elif cmd == "carry-check":
            carry(*args[1:], write=False)
        elif cmd == "drop":
            sys.exit(drop(args[1], args[2], args[4:]))
        elif cmd == "card":
            sys.stdout.write(card(*args[1:]))
        elif cmd == "ids":
            with open(os.path.join(args[1], "inbox.md"), encoding="utf-8") as f:
                for mid in sorted(merged_ids(f.read())):
                    print(mid)
        else:
            remove(*args[1:])
    except FileNotFoundError as e:
        print("inboxmerge: 目標卡不見了：%s" % e, file=sys.stderr)
        sys.exit(1)
    except SectionNotFound as e:
        print("inboxmerge: %s" % e, file=sys.stderr)
        sys.exit(2)
    except TargetStarted as e:
        print("inboxmerge: %s" % e, file=sys.stderr)
        sys.exit(4)
    except (ValueError, OSError) as e:
        print("inboxmerge: %s" % e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
