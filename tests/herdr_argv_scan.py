"""找原始碼裡第一個元素是字串 "herdr" 的 list 或 tuple 字面值；有不准的就印出來、以 1 結束。

給 runtime-py-callers*.test.sh 用：herdr argv 要由 bin/lib/runtime.py 產生，呼叫者不該自己寫。
用 ast 而不是 grep，單引號、跨行、tuple 都抓得到，`x == "herdr"` 這種比較不會誤報。
只抓字面值：把 "herdr" 綁到名字再放進 list、或寫成 shell 字串，這裡看不到。
用法：python3 -I herdr_argv_scan.py [--allow <檔名>=<字面值>]... <檔案>...
  --allow 准一筆：檔名（basename）與 ast.unparse 後的字面值都要相同，而且剛好出現一次。
  讀不到或 parse 不了的檔案直接丟例外，結束碼非 0。
"""
import argparse
import ast
import os
import sys


def hits(path):
    with open(path, encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)
    for node in ast.walk(tree):
        if isinstance(node, (ast.List, ast.Tuple)) and node.elts:
            first = node.elts[0]
            if isinstance(first, ast.Constant) and first.value == "herdr":
                yield node.lineno, ast.unparse(node)


def parse_allow(text):
    name, sep, literal = text.partition("=")
    if not sep or not name or not literal:
        raise argparse.ArgumentTypeError("--allow 要寫成 <檔名>=<字面值>，收到：%r" % text)
    return name, literal


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--allow", type=parse_allow, action="append", default=[])
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()
    seen = {a: 0 for a in args.allow}
    bad = []
    for p in args.files:
        for lineno, src in hits(p):
            key = (os.path.basename(p), src)
            if key in seen:
                seen[key] += 1
            else:
                bad.append("%s:%d: %s" % (p, lineno, src))
    for (name, literal), n in seen.items():
        if n != 1:
            bad.append("允許的 %s 裡 %s 要剛好一筆，找到 %d 筆" % (name, literal, n))
    for line in bad:
        print(line)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
