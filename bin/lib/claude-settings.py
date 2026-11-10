"""把標準設定與 repo 路徑合併進使用者層 Claude Code settings.json。

--template 是 plugin 的標準設定（只含物件與字串陣列，字串裡的 ${NAME} 由環境變數展開）；
--add-dir 追加 permissions.additionalDirectories。只追加不存在的元素，不動其他鍵；
有變化且原檔存在時先備份成 <file>.opsx-bak（已有就不覆蓋）。
檔案不是合法 JSON、或要寫的鍵路徑上的型別不符時直接失敗，不改檔。
成功時 stdout 印 created（原檔不存在）、changed 或 unchanged。--check 只比對不寫：缺的逐行印出，有缺 exit 3。
"""
import argparse
import json
import os
import re
import shutil
import stat
import tempfile

CHECK_MISSING = 3  # --check 有缺項時的 exit code；1 留給「檔案或範本壞了」
VAR = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


def expand(text, source):
    for name in VAR.findall(text):
        if name not in os.environ:
            raise SystemExit(f"claude-settings: {source} 用了環境變數 ${{{name}}}，但沒設")
    return os.path.expandvars(text)


def flatten(node, keys, source):
    """範本 → [(鍵路徑, 字串陣列)]。葉節點不是字串陣列就失敗。"""
    if isinstance(node, dict):
        wants = []
        for k, v in node.items():
            wants += flatten(v, keys + (k,), source)
        return wants
    if isinstance(node, list) and all(isinstance(v, str) for v in node):
        return [(keys, [expand(v, source) for v in node])]
    raise SystemExit(f"claude-settings: {source} 的 {'.'.join(keys)} 要是字串陣列，實際是 {node!r}")


def load(path):
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise SystemExit(f"claude-settings: {path} 不是合法 JSON：{e}") from e
    if not isinstance(data, dict):
        raise SystemExit(f"claude-settings: {path} 最外層要是物件，實際是 {data!r}")
    return data


def merge(data, keys, values, path):
    """把 values 追加進 data 的 keys 路徑上的陣列；回傳實際新增的元素。"""
    if not values:
        return []
    node = data
    for i, key in enumerate(keys[:-1]):
        if key not in node:
            node[key] = {}
        node = node[key]
        if not isinstance(node, dict):
            raise SystemExit(f"claude-settings: {path} 的 {'.'.join(keys[:i + 1])} 要是物件，實際是 {node!r}")
    last = keys[-1]
    if last not in node:
        node[last] = []
    arr = node[last]
    if not isinstance(arr, list):
        raise SystemExit(f"claude-settings: {path} 的 {'.'.join(keys)} 要是陣列，實際是 {arr!r}")
    added = [v for v in values if v not in arr]
    arr.extend(added)
    return added


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--file", required=True)
    p.add_argument("--template")
    p.add_argument("--add-dir", action="append", default=[])
    p.add_argument("--check", action="store_true")
    args = p.parse_args()

    wants = []
    if args.template:
        with open(args.template, encoding="utf-8") as f:
            wants += flatten(json.load(f), (), args.template)
    wants.append((("permissions", "additionalDirectories"), args.add_dir))

    exists = os.path.exists(args.file)
    data = load(args.file) if exists else {}
    added = []
    for keys, values in wants:
        added += [(keys, v) for v in merge(data, keys, values, args.file)]

    if args.check:
        for keys, v in added:
            print(f"缺 {'.'.join(keys)}: {v}")
        raise SystemExit(CHECK_MISSING if added else 0)
    if not added:
        print("unchanged")
        return

    bak = args.file + ".opsx-bak"
    if exists and not os.path.exists(bak):
        shutil.copy2(args.file, bak)
    # 寫到 symlink 指向的真檔（dotfiles），暫存檔放同一個目錄且名字唯一；沿用原檔權限，新檔 0600
    real = os.path.realpath(args.file)
    directory = os.path.dirname(real)
    os.makedirs(directory, exist_ok=True)
    mode = stat.S_IMODE(os.stat(real).st_mode) if exists else 0o600
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".settings.", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    os.chmod(tmp, mode)
    os.replace(tmp, real)
    print("changed" if exists else "created")


if __name__ == "__main__":
    main()
