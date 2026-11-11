"""判定一個 claude 行程的啟動參數有沒有丟：argv 有沒有這張卡該有的 --settings 檔。

函式（coordinate 直接 import）：
    args_lost(argv, settings_path) -> bool
        True：沒有 `--settings <settings_path>` 也沒有 `--settings=<settings_path>`（完整路徑相等；
        `--settings` 出現多次時任何一個相等就算有帶）。
        認不得的輸入 raise ValueError，訊息點名欄位與值：argv 不是 list 或含非 str、argv 空、
        basename(argv[0]) 不是 claude、`--settings` 後面沒有值、settings_path 不是絕對路徑或含空白。

CLI（hook 用）：stdin 一行 ps 輸出，參數是 settings_path。
    退出碼 0 有帶、1 遺失、2 認不得（原因寫 stderr）。
"""
from __future__ import annotations

import os
import shlex
import sys

FLAG = "--settings"


def args_lost(argv: list[str], settings_path: str) -> bool:
    if not isinstance(argv, list) or not all(isinstance(a, str) for a in argv):
        raise ValueError(f"argv 要是 list[str]：{argv!r}")
    if not argv:
        raise ValueError(f"argv 是空的：{argv!r}")
    if os.path.basename(argv[0]) != "claude":
        raise ValueError(f"argv[0] 不是 claude：{argv[0]!r}")
    if not os.path.isabs(settings_path):
        raise ValueError(f"settings_path 要是絕對路徑：{settings_path!r}")
    if any(c.isspace() for c in settings_path):
        raise ValueError(f"settings_path 含空白，ps 輸出切不回 argv：{settings_path!r}")
    given = []
    for i, a in enumerate(argv[1:], start=1):
        if a == FLAG:
            if i + 1 >= len(argv):
                raise ValueError(f"{FLAG} 後面沒有值：{argv!r}")
            given.append(argv[i + 1])
        elif a.startswith(FLAG + "="):
            given.append(a[len(FLAG) + 1:])
    return settings_path not in given


def main(line: str, settings_path: str) -> int:
    try:
        try:
            argv = shlex.split(line)
        except ValueError as e:
            raise ValueError(f"ps 輸出切不成 argv（{e}）：{line!r}") from e
        return 1 if args_lost(argv, settings_path) else 0
    except ValueError as e:
        print(f"argslost: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("用法：argslost.py <settings_path>（stdin 一行 ps 輸出）", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.stdin.readline(), sys.argv[1]))
