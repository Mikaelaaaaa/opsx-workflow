#!/usr/bin/env bash
# 看板 server 的 slug 檢查要接受 collect 列出的長卡名，路徑穿越與超長仍然擋。
# 驗收：openspec/changes/me-20261111-1824/specs/board-long-slug/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

python3 -I - "$OPSX_ROOT/herdr-board/server.py" <<'PY' || fail "board slug 檢查不符"
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("board_server", sys.argv[1])
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


def accepted(slug):
    try:
        server.priority_args({"slug": slug, "level": "P1", "reason": "x", "repo": "/tmp"})
    except ValueError as e:
        # slug 過了之後才會檢查 repo，/tmp 不是 opsx repo 所以會停在那裡；那代表 slug 被收了
        return "slug 不合格" not in str(e)
    return True


assert accepted("notification-toast-replays-on-load"), "34 字的卡名要收"
assert accepted("a" * 64), "64 字要收"
assert not accepted("a" * 65), "65 字要擋"
assert not accepted("../etc"), "路徑穿越要擋"
assert not accepted("Upper"), "大寫要擋"
assert not accepted("a/b"), "斜線要擋"
print("board-long-slug ok")
PY
