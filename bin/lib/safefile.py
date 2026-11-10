"""沙盒外的 opsx 寫沙盒可寫目錄裡的檔案時用的開檔與換名：不跟 symlink，暫存檔名隨機。specs/symlink-safe-writes/spec.md。

用法（bash 內嵌 python）：
    sys.path.insert(0, os.environ["OPSX_LIB"]); import safefile
    safefile.open_append(path)      # 附加寫入的 log、TOML、gates.md
    safefile.open_lock(path)        # flock 用的鎖檔與標記檔；不截斷
    safefile.write_atomic(path, s)  # 同目錄隨機暫存檔，再 os.replace；保留原檔權限

shell 與 hooks 走 CLI：`<python> -I safefile.py append|replace <path>`，內容從 stdin 來。
路徑是 symlink（含 dangling）時丟 SymlinkRefused，CLI 退出 2。O_NOFOLLOW 只管最後一段路徑。
"""
from __future__ import annotations

import errno
import os
import stat
import sys
import tempfile


class SymlinkRefused(OSError):
    pass


def _open_nofollow(path: str, flags: int) -> int:
    try:
        return os.open(path, flags | os.O_CREAT | os.O_NOFOLLOW, 0o666)
    except OSError as e:
        if e.errno == errno.ELOOP:
            raise SymlinkRefused("refuse to write through symlink: %s" % path) from e
        raise


def open_append(path: str):
    return os.fdopen(_open_nofollow(path, os.O_WRONLY | os.O_APPEND), "a", encoding="utf-8")


def open_lock(path: str):
    return os.fdopen(_open_nofollow(path, os.O_WRONLY), "w", encoding="utf-8")


def _target_mode(path: str) -> int:
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        st = None
    if st is not None and stat.S_ISREG(st.st_mode):
        return stat.S_IMODE(st.st_mode)
    umask = os.umask(0)
    os.umask(umask)
    return 0o666 & ~umask


def write_atomic(path: str, text: str) -> None:
    mode = _target_mode(path)
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + ".", suffix=".tmp", dir=os.path.dirname(path) or ".")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            os.fchmod(f.fileno(), mode)
            f.write(text)
        os.replace(tmp, path)
    except (OSError, UnicodeError):
        os.unlink(tmp)
        raise


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in ("append", "replace"):
        print("usage: safefile.py append|replace <path>（內容從 stdin）", file=sys.stderr)
        return 64
    cmd, path = argv[1], argv[2]
    text = sys.stdin.buffer.read().decode("utf-8")
    try:
        if cmd == "append":
            with open_append(path) as f:
                f.write(text)
        else:
            write_atomic(path, text)
    except SymlinkRefused as e:
        print("opsx: %s" % e, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
