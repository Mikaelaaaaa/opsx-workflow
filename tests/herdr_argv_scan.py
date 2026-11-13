"""印出原始碼裡第一個元素是字串 "herdr" 的 list 或 tuple 字面值，一行一筆：<檔案>:<行>: <字面值>。

給 runtime-py-callers*.test.sh 用：herdr argv 要由 bin/lib/runtime.py 產生，呼叫者不該自己寫。
用 ast 而不是 grep，單引號、跨行、tuple 都抓得到，`x == "herdr"` 這種比較不會誤報。
用法：python3 -I herdr_argv_scan.py <檔案>...
"""
import ast
import sys


def hits(path):
    with open(path, encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)
    for node in ast.walk(tree):
        if isinstance(node, (ast.List, ast.Tuple)) and node.elts:
            first = node.elts[0]
            if isinstance(first, ast.Constant) and first.value == "herdr":
                yield node.lineno, ast.unparse(node)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        for lineno, src in hits(p):
            print("%s:%d: %s" % (p, lineno, src))
