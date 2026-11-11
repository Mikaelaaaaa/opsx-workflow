"""指令骨架（hooks/cmd-skeleton.pl 的輸出）的兩種拆法，給 hooks/opsx-grant-gate.sh 用。

    cmdsegments.py split    stdin 一條骨架，每一段印一行。段以 &&、||、;、|、& 與換行分隔；
                            重導向裡的 &（2>&1、>&2、&>file）不算分隔。
    cmdsegments.py writes   stdin 一條骨架，每個寫檔目標印一行：重導向 >、>>，tee，cp 與 mv 的最後一個參數，git mv 的最後一個參數。

骨架已經把引號內的字串去掉，所以這裡看到的運算子都是真的。
shortcut: 只認 >、>>、tee、cp、mv、git mv 的目的地；install、ln、rsync、sed -i、cp -t 與直譯器自己開檔寫入認不得，等真的有人用這些繞過再補。
"""
from __future__ import annotations

import re
import sys

REDIRECT_AMP = re.compile(r"\d*>&\d*-?|&>>?|\d*<&\d*-?")
SPLIT = re.compile(r"&&|\|\||;|\||&|\n")
REDIRECT = re.compile(r"(?:\d*|&)>>?(.*)")
PLACEHOLDER = "\0"


def split_segments(skeleton: str) -> list[str]:
    protected = REDIRECT_AMP.sub(lambda m: m.group(0).replace("&", PLACEHOLDER), skeleton)
    return [p.replace(PLACEHOLDER, "&").strip() for p in SPLIT.split(protected) if p.strip()]


def positional(tokens: list[str]) -> list[str]:
    return [t for t in tokens if not t.startswith("-")]


def git_subcommand_args(tokens: list[str]) -> tuple[str, list[str]]:
    """git 之後略過全域選項（-C、-c 帶一個值），回 (子命令, 子命令之後的 token)。"""
    i = 1
    while i < len(tokens) and tokens[i].startswith("-"):
        i += 2 if tokens[i] in ("-C", "-c") else 1
    if i >= len(tokens):
        return "", []
    return tokens[i], tokens[i + 1:]


def segment_writes(segment: str) -> list[str]:
    # 骨架裡引號內有空白或 $ 的字串已換成 ""、沒有空白的已去掉引號，所以照空白切就是 token；
    # 留在 token 裡的 "" 代表那一塊被拿掉了，呼叫者看到引號就知道這個路徑讀不全
    tokens = segment.split()
    out = []
    for i, tok in enumerate(tokens):
        m = REDIRECT.fullmatch(tok)
        if not m or m.group(1).startswith("&"):
            continue
        target = m.group(1) or (tokens[i + 1] if i + 1 < len(tokens) else "")
        if not target:
            raise ValueError("重導向 %r 後面沒有目標：%r" % (tok, segment))
        out.append(target)
    if not tokens:
        return out
    if tokens[0] == "tee":
        out += positional(tokens[1:])
    elif tokens[0] in ("cp", "mv"):
        args = positional(tokens[1:])
        if len(args) >= 2:
            out.append(args[-1])
    elif tokens[0] == "git":
        sub, rest = git_subcommand_args(tokens)
        args = positional(rest)
        if sub == "mv" and len(args) >= 2:
            out.append(args[-1])
    return out


def main(mode: str, skeleton: str) -> int:
    try:
        if mode == "split":
            lines = split_segments(skeleton)
        elif mode == "writes":
            lines = [t for seg in split_segments(skeleton) for t in segment_writes(seg)]
        else:
            print("cmdsegments: 不認得的模式 %r（split 或 writes）" % mode, file=sys.stderr)
            return 2
    except ValueError as e:
        print("cmdsegments: %s" % e, file=sys.stderr)
        return 2
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("用法：cmdsegments.py split|writes（stdin 一條指令骨架）", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.stdin.read()))
