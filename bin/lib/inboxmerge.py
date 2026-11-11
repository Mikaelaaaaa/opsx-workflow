"""opsx new 的自動併入：在目標卡 inbox.md 尾端追加一段 `## 併入：<時間> <來源>`，印這段拿到的 id。

用法：$OPSX_PY -I inboxmerge.py <卡目錄> <基本 id> <ISO 時間> <來源> <kind_of_work> <impact> <evidence> <area> <一句話>
id 是新卡原本會拿到的 slug；目標裡已經有同一個 id 時依序加 -2、-3。
兩個 agent 可能同時併進同一張卡：鎖在卡目錄上（inbox.md 會被原子替換換掉 inode，鎖它本身擋不住），鎖內重讀、算 id、寫入。
一段併入從標題到下一個 `## ` 或檔尾為止。specs/card-auto-merge「同 area 併入」。
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
ID_LINE = re.compile(r"^- id: (\S+)\s*$")


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
    fd = os.open(card_dir, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        with open(inbox, encoding="utf-8") as f:
            cur = f.read()
        mid = free_id(base, merged_ids(cur))
        if cur and not cur.endswith("\n"):
            cur += "\n"
        if cur and not cur.endswith("\n\n"):
            cur += "\n"
        safefile.write_atomic(inbox, cur + section(mid, when, source, kind, impact, evidence, area, text))
    finally:
        os.close(fd)
    return mid


def main() -> None:
    args = sys.argv[1:]
    if len(args) != 9:
        sys.exit("用法：inboxmerge.py <卡目錄> <基本 id> <ISO 時間> <來源> <kind_of_work> <impact> <evidence> <area> <一句話>")
    try:
        print(append(*args))
    except FileNotFoundError as e:
        print("inboxmerge: 目標卡不見了：%s" % e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
