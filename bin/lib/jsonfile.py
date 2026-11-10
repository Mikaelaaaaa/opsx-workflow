"""dispatch.json 的唯一讀寫口：dispatch / answer / merge / stop / grant-gate 五個 writer 都經這裡，才不會互相蓋掉。

用法（bash 內嵌 python）：
    sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
    d = jsonfile.load(path)                      # 讀；不存在或壞掉都回 {}，壞掉時 stderr 印一行
    jsonfile.update(path, mutate)                # 鎖住、讀、mutate(d)、寫到 tmp、os.replace、解鎖
mutate 是模組層級的函式（不要 nested def），收 dict、原地改、回傳值不看。
鎖是 <path>.lock 上的 fcntl.flock，讀寫都在鎖內；寫入先到 tmp 再 os.replace，讀的人永遠看不到半個檔。
"""
from __future__ import annotations

import fcntl
import json
import os
import sys
import tempfile

import safefile


def load(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as e:
        print("opsx: %s 不是合法 JSON（%s），當成空的" % (path, e), file=sys.stderr)
        return {}
    return d if isinstance(d, dict) else {}


def update(path: str, mutate) -> dict:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with safefile.open_lock(path + ".lock") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        d = load(path)
        mutate(d)
        fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + ".", dir=os.path.dirname(path) or ".")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, indent=1)
        os.replace(tmp, path)
    return d
