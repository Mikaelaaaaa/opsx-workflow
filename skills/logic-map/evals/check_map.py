"""Mechanically check a logic map against the code it describes.

Usage: python3 -I check_map.py <repo> <head> <logic-map.md>

Exits 1 and prints one line per problem on stderr when a position line does not
exist at <head>, a position line is not a judgment line, a feature's flowchart
and condition table do not name the same D nodes, or a flowchart is Mermaid.
Exits 2 on bad arguments. Whether a condition is faithful is left to the grader.
"""

import os
import re
import subprocess
import sys

JUDGMENT_PREFIXES = ("if ", "elif ", "case ", "[[", "while ", "until ")
JUDGMENT_PARTS = ("grep -q", "&&", "||")
TERNARY = re.compile(r"\sif\s.+\selse\s")
NODE = re.compile(r"(?<![A-Za-z0-9_])D(\d+)(?!\d)")
POSITION = re.compile(r"([\w./-]+)?:(\d+)")
MERMAID = re.compile(r"^```\s*mermaid", re.M)
FEATURE = re.compile(r"^## 功能", re.M)
SUBSECTION = re.compile(r"^### (.+)$", re.M)


def is_judgment(line):
    s = line.strip()
    if s.startswith(JUDGMENT_PREFIXES):
        return True
    if any(p in s for p in JUDGMENT_PARTS):
        return True
    return TERNARY.search(s) is not None


def subsections(feature):
    """Map each `### <title>` in a feature to its body."""
    heads = list(SUBSECTION.finditer(feature))
    out = {}
    for i, h in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(feature)
        out[h.group(1).strip()] = feature[h.end():end]
    return out


def table_rows(body):
    """Condition-table rows as (node, position cell). Conditions may hold unescaped pipes, so only the first and last cells are trusted."""
    rows = []
    for line in body.splitlines():
        cells = line.strip().split("|")
        if len(cells) < 3 or not line.strip().startswith("|"):
            continue
        node = cells[1].strip()
        if re.fullmatch(r"D\d+", node):
            rows.append((node, cells[-2].strip()))
    return rows


class Source:
    """File contents at one commit, read once per path."""

    def __init__(self, repo, head):
        self.repo = repo
        self.head = head
        self.cache = {}

    def lines(self, path):
        if path not in self.cache:
            r = subprocess.run(["git", "-C", self.repo, "show", "%s:%s" % (self.head, path)],
                               capture_output=True, text=True)
            self.cache[path] = r.stdout.splitlines() if r.returncode == 0 else None
        return self.cache[path]


def check_positions(src, label, node, cell):
    problems = []
    found = list(POSITION.finditer(cell))
    if not found:
        return ["%s %s 的位置沒有 path:line：%r" % (label, node, cell)]
    path = None
    for m in found:
        path = m.group(1) or path
        n = int(m.group(2))
        if path is None:
            problems.append("%s %s 的位置 :%d 前面沒有檔名" % (label, node, n))
            continue
        lines = src.lines(path)
        if lines is None:
            problems.append("%s:%d 不存在（head 沒有這個檔）" % (path, n))
        elif n < 1 or n > len(lines):
            problems.append("%s:%d 不存在（檔案只有 %d 行）" % (path, n, len(lines)))
        elif not is_judgment(lines[n - 1]):
            problems.append("%s:%d 不是判斷行：%s" % (path, n, lines[n - 1].strip()))
    return problems


def check_feature(src, label, feature):
    parts = subsections(feature)
    for need in ("流程圖", "條件表"):
        if need not in parts:
            return ["%s 沒有 ### %s" % (label, need)]
    flow = {"D" + d for d in NODE.findall(parts["流程圖"])}
    rows = table_rows(parts["條件表"])
    table = {node for node, _ in rows}
    problems = ["%s %s 在流程圖、不在條件表" % (label, d) for d in sorted(flow - table)]
    problems += ["%s %s 在條件表、不在流程圖" % (label, d) for d in sorted(table - flow)]
    for node, cell in rows:
        problems += check_positions(src, label, node, cell)
    return problems


def check(repo, head, text):
    problems = []
    if MERMAID.search(text):
        problems.append("流程圖是 mermaid 區塊，要純文字")
    starts = [m.start() for m in FEATURE.finditer(text)]
    if not starts:
        return problems + ["沒有任何 ## 功能 段"]
    src = Source(repo, head)
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(text)
        feature = text[start:end]
        label = feature.splitlines()[0].lstrip("# ").split("：")[0]
        problems += check_feature(src, label, feature)
    return problems


def main(argv):
    if len(argv) != 4:
        print("usage: check_map.py <repo> <head> <logic-map.md>", file=sys.stderr)
        return 2
    repo, head, path = argv[1:]
    if not os.path.isfile(path):
        print("logic map not found: %s" % path, file=sys.stderr)
        return 2
    r = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "-q", head + "^{commit}"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("head %r is not a commit in %s" % (head, repo), file=sys.stderr)
        return 2
    with open(path, encoding="utf-8") as f:
        problems = check(repo, head, f.read())
    for p in problems:
        print(p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
