"""opsx new 自動併入的目標：新項目提到的 repo 檔案跟哪張候選卡有交集。specs/card-auto-merge「同檔案併入」。

用法：
    $OPSX_PY -I mergematch.py pick <top> <一句話> <evidence> [<候選 slug>…]
        印目標 slug，沒有就不印。候選由呼叫端先篩過階段（explore／grill／propose）並排除開卡者自己的主殼。
        排序：共同檔案數由多到少，平手取 slug 的 C locale 字母序；等級是 P0 的跳過，算不出等級的跳過並在 stderr 警告。
"""
from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import priority  # noqa: E402

TOKEN = re.compile(r"/?[A-Za-z0-9_.][A-Za-z0-9_./-]*")
HEAD = re.compile(r"^## (.*)$")
SCANNED = re.compile(r"^(一句話|證據|併入：.*)\s*$")


def files_in(top: str, text: str) -> set:
    """text 裡提到、在 <top> 底下真的存在的一般檔案，回相對路徑。行號因為 `:` 不在 token 字元集裡自然切掉。"""
    real_top = os.path.realpath(top)
    worktrees = os.path.join(real_top, ".claude", "worktrees") + os.sep
    out = set()
    for tok in TOKEN.findall(text):
        tok = tok.rstrip(".")
        if "/" not in tok and "." not in tok:
            continue
        if tok.startswith("/"):
            path = os.path.realpath(tok)
            if path.startswith(worktrees):
                rest = path[len(worktrees):].split(os.sep, 1)
                if len(rest) < 2:
                    continue
                tok = rest[1]
            elif path.startswith(real_top + os.sep):
                tok = path[len(real_top) + 1:]
            else:
                continue
        rel = os.path.normpath(tok)
        if rel.startswith("..") or os.path.isabs(rel):
            continue
        if os.path.isfile(os.path.join(real_top, rel)):
            out.add(rel)
    return out


def card_text(inbox: str) -> str:
    """卡 inbox.md 裡會拿來比對的段：frontmatter 的 evidence（opsx new --evidence 寫在這）、一句話、證據、每段併入（含它的一句話與 - evidence:）。"""
    lines = inbox.split("\n")
    keep, out, start = False, [], 0
    if lines and lines[0].startswith("---"):
        for i, line in enumerate(lines[1:], 1):
            if line.startswith("---"):
                start = i + 1
                break
            if line.startswith("evidence:"):
                out.append(line[len("evidence:"):])
    for line in lines[start:]:
        m = HEAD.match(line)
        if m:
            keep = bool(SCANNED.match(m.group(1)))
            continue
        if keep:
            out.append(line)
    return "\n".join(out)


def pick(top: str, text: str, evidence: str, candidates: list) -> str:
    mine = files_in(top, text + "\n" + evidence)
    if not mine:
        return ""
    # 併入是可有可無的，新項目不能因為別張卡讀不了而開不成：讀不了的候選跳過、等級算不了就不併
    ranked = []
    for slug in candidates:
        try:
            with open(os.path.join(top, "openspec", "changes", slug, "inbox.md"), encoding="utf-8") as f:
                body = f.read()
        except (FileNotFoundError, UnicodeDecodeError) as e:
            print("opsx: new: 讀不了 %s 的 inbox.md，不當併入目標：%s" % (slug, e), file=sys.stderr)
            continue
        shared = mine & files_in(top, card_text(body))
        if shared:
            ranked.append((-len(shared), slug))
    if not ranked:
        return ""
    try:
        lv = priority.levels(top)
    except (priority.PriorityError, UnicodeDecodeError) as e:
        print("opsx: new: 算不出目標卡的等級，不併：%s" % e, file=sys.stderr)
        return ""
    # str 依 code point 比，跟 UTF-8 位元組序（C locale）一致
    for _, slug in sorted(ranked):
        got = lv.get(slug)
        if got is None or "error" in got:
            why = got["error"] if got else "沒有這張卡"
            print("opsx: new: %s 的等級算不出來，不當併入目標：%s" % (slug, why), file=sys.stderr)
            continue
        if got["level"] == "P0":
            continue
        return slug
    return ""


def main() -> None:
    args = sys.argv[1:]
    if len(args) < 4 or args[0] != "pick":
        sys.exit("用法：mergematch.py pick <top> <一句話> <evidence> [<候選 slug>…]")
    got = pick(args[1], args[2], args[3], args[4:])
    if got:
        print(got)


if __name__ == "__main__":
    main()
