"""目標卡 inbox.md 的 `## 併入：<時間> <來源>` 段：opsx new 追加、opsx split-out 拆回獨立的卡。

用法：
    $OPSX_PY -I inboxmerge.py append <卡目錄> <基本 id> <ISO 時間> <來源> <kind_of_work> <impact> <evidence> <area> <一句話>
        追加一段，印這段拿到的 id。id 是新卡原本會拿到的 slug；目標裡已經有同一個 id 時依序加 -2、-3。
    $OPSX_PY -I inboxmerge.py card <卡目錄> <id>
        印那一段拆回獨立卡時的 inbox.md（跟 opsx new 寫的同形）。找不到退出 2。
    $OPSX_PY -I inboxmerge.py remove <卡目錄> <id>
        刪掉那一段，其餘位元組不動。找不到退出 2。
    $OPSX_PY -I inboxmerge.py ids <卡目錄>
        一行印一個這張卡現有的併入 id（opsx drop 用來拒絕還有併入項目的卡）。
兩個 agent 可能同時併進同一張卡：鎖在卡目錄上（inbox.md 會被原子替換換掉 inode，鎖它本身擋不住），鎖內重讀再改。
一段併入從標題到下一個 `## ` 或檔尾為止。specs/card-auto-merge「同 area 併入」「拆出來」。
"""
from __future__ import annotations

import fcntl
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import safefile  # noqa: E402

HEAD = re.compile(r"^## ")
MERGED = re.compile(r"^## 併入：")
MERGED_HEAD = re.compile(r"^## 併入：(\S+) (\S+)\s*$")
ID_LINE = re.compile(r"^- id: (\S+)\s*$")
FIELD = re.compile(r"^- (id|kind_of_work|impact|evidence|area): (.*)$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}")


class SectionNotFound(LookupError):
    pass


class CardLock:
    def __init__(self, card_dir: str):
        self.card_dir = card_dir
        self.fd = -1

    def __enter__(self) -> "CardLock":
        self.fd = os.open(self.card_dir, os.O_RDONLY)
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc) -> None:
        os.close(self.fd)


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


def section(mid: str, when: str, source: str, kind: str, impact: str, evidence: str, area: str, text: str) -> str:
    lines = ["## 併入：%s %s" % (when, source), "", "- id: " + mid, "- kind_of_work: " + kind]
    if impact:
        lines.append("- impact: " + impact)
    if evidence:
        lines.append("- evidence: " + evidence)
    lines += ["- area: " + area, "", text, ""]
    return "\n".join(lines)


def append(card_dir: str, base: str, when: str, source: str, kind: str, impact: str, evidence: str, area: str, text: str) -> str:
    inbox = os.path.join(card_dir, "inbox.md")
    with CardLock(card_dir):
        with open(inbox, encoding="utf-8") as f:
            cur = f.read()
        mid = free_id(base, merged_ids(cur))
        if cur and not cur.endswith("\n"):
            cur += "\n"
        if cur and not cur.endswith("\n\n"):
            cur += "\n"
        safefile.write_atomic(inbox, cur + section(mid, when, source, kind, impact, evidence, area, text))
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
    for key in ("id", "kind_of_work", "area"):
        if key not in out:
            raise ValueError("併入段少了 - %s:（標題 %s）" % (key, block[0]))
    rest = block[i + 1:]
    if not rest or rest[0] == "" or any(x != "" for x in rest[1:]):
        raise ValueError("併入段欄位後要是空行加一行一句話（id %s）" % out["id"])
    out["text"] = rest[0]
    return out


def card_body(fields: dict) -> str:
    lines = ["---", "type: 功能", "source: " + fields["source"], "found: " + fields["when"][:10], "related:", "kind_of_work: " + fields["kind_of_work"]]
    if "impact" in fields:
        lines.append("impact: " + fields["impact"])
    if "evidence" in fields:
        lines.append("evidence: " + fields["evidence"])
    lines += ["area: " + fields["area"], "---", "", "## 一句話", "", fields["text"], "", "## 證據", "", ""]
    return "\n".join(lines)


def card(card_dir: str, mid: str) -> str:
    with CardLock(card_dir):
        with open(os.path.join(card_dir, "inbox.md"), encoding="utf-8") as f:
            cur = f.read()
    start, end = find(cur, mid)
    return card_body(parse([x.rstrip("\n") for x in cur.splitlines(keepends=True)[start:end]]))


def remove(card_dir: str, mid: str) -> None:
    inbox = os.path.join(card_dir, "inbox.md")
    with CardLock(card_dir):
        with open(inbox, encoding="utf-8") as f:
            cur = f.read()
        start, end = find(cur, mid)
        lines = cur.splitlines(keepends=True)
        safefile.write_atomic(inbox, "".join(lines[:start] + lines[end:]))


def main() -> None:
    args = sys.argv[1:]
    cmd = args[0] if args else ""
    want = {"append": 10, "card": 3, "remove": 3, "ids": 2}
    if cmd not in want or len(args) != want[cmd]:
        sys.exit("用法：inboxmerge.py append <卡目錄> <基本 id> <ISO 時間> <來源> <kind_of_work> <impact> <evidence> <area> <一句話> | card <卡目錄> <id> | remove <卡目錄> <id> | ids <卡目錄>")
    try:
        if cmd == "append":
            print(append(*args[1:]))
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
    except (ValueError, OSError) as e:
        print("inboxmerge: %s" % e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
