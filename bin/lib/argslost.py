"""判定一個 claude 行程的啟動參數有沒有丟：argv 有沒有這張卡該有的 --settings 檔。

函式（coordinate 直接 import）：
    args_lost(argv, settings_path) -> bool
        True：沒有 `--settings <settings_path>` 也沒有 `--settings=<settings_path>`（完整路徑相等；
        `--settings` 出現多次時任何一個相等就算有帶）。
        認不得的輸入 raise ValueError，訊息點名欄位與值：argv 不是 list 或含非 str、argv 空、
        argv[0] 既不是 claude 也不是 claude 的版本執行檔（<任意>/claude/versions/<版本>）、`--settings` 後面沒有值、settings_path 不是絕對路徑或含空白。

    claude_argv(info) -> list
        herdr pane process-info 的輸出裡，前景行程中唯一一筆 argv0 是 claude 的 argv。認不得 raise ValueError。

CLI（hook 用）：
    argslost.py <settings_path>                  stdin 一行 ps 輸出
    argslost.py --process-info <settings_path>   stdin 是 herdr pane process-info 的 JSON
    退出碼 0 有帶、1 遺失、2 認不得（原因寫 stderr）。
"""
from __future__ import annotations

import json
import os
import shlex
import sys

FLAG = "--settings"


def is_claude(argv0: str) -> bool:
    """檔名是 claude，或是版本執行檔 <任意>/claude/versions/<版本>（ps 顯示 symlink 指向的實檔）。"""
    if os.path.basename(argv0) == "claude":
        return True
    versions_dir, _ = os.path.split(argv0)
    claude_dir, versions = os.path.split(versions_dir)
    return versions == "versions" and os.path.basename(claude_dir) == "claude"


def args_lost(argv: list[str], settings_path: str) -> bool:
    if not isinstance(argv, list) or not all(isinstance(a, str) for a in argv):
        raise ValueError(f"argv 要是 list[str]：{argv!r}")
    if not argv:
        raise ValueError(f"argv 是空的：{argv!r}")
    if not is_claude(argv[0]):
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


def claude_argv(info) -> list:
    """不用 name 欄位：claude 那筆的 name 是版本號。"""
    try:
        procs = info["result"]["process_info"]["foreground_processes"]
    except (KeyError, TypeError) as e:
        raise ValueError("process-info 沒有 result.process_info.foreground_processes：%s" % json.dumps(info, ensure_ascii=False)[:200]) from e
    if not isinstance(procs, list) or not all(isinstance(p, dict) for p in procs):
        raise ValueError("foreground_processes 要是物件的 list：%s" % json.dumps(procs, ensure_ascii=False)[:200])
    hits = [p for p in procs if p.get("argv0") == "claude"]
    if not hits:
        raise ValueError("前景沒有 claude（argv0 是 %s）" % "、".join(str(p.get("argv0")) for p in procs))
    if len(hits) > 1:
        raise ValueError("前景有 %d 個 claude，認不出是哪一個（pid %s）" % (len(hits), "、".join(str(p.get("pid")) for p in hits)))
    if "argv" not in hits[0]:
        raise ValueError("claude 那筆前景行程沒有 argv 欄位：%s" % json.dumps(hits[0], ensure_ascii=False)[:200])
    return hits[0]["argv"]


def ps_argv(text: str) -> list:
    try:
        return shlex.split(text)
    except ValueError as e:
        raise ValueError(f"ps 輸出切不成 argv（{e}）：{text!r}") from e


def process_info_argv(text: str) -> list:
    try:
        info = json.loads(text)
    except json.JSONDecodeError as e:
        raise ValueError(f"process-info 不是 JSON（{e}）：{text[:200]!r}") from e
    return claude_argv(info)


def main(text: str, settings_path: str, to_argv) -> int:
    try:
        return 1 if args_lost(to_argv(text), settings_path) else 0
    except ValueError as e:
        print(f"argslost: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--process-info":
        sys.exit(main(sys.stdin.read(), sys.argv[2], process_info_argv))
    if len(sys.argv) == 2:
        sys.exit(main(sys.stdin.readline(), sys.argv[1], ps_argv))
    print("用法：argslost.py [--process-info] <settings_path>（stdin 一行 ps 輸出，或 process-info JSON）", file=sys.stderr)
    sys.exit(2)
