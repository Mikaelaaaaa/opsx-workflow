"""指令骨架（hooks/cmd-skeleton.pl 的輸出）的兩種拆法，給 hooks/opsx-grant-gate.sh 用。

    cmdsegments.py split    stdin 一條骨架，每一段印一行。段以 &&、||、;、|、&、換行與子 shell 括號分隔；
                            重導向裡的 &（2>&1、>&2、&>file）不算分隔；$(…)、反引號、<(…) 的內容拆成自己的段，
                            餵給 cat、python 等的 heredoc 本體不算指令（餵給 bash、sh、eval 的才算）。
    cmdsegments.py writes   stdin 一條骨架，每個寫檔目標印一行：重導向 >、>>，tee，cp 與 mv 的最後一個參數，git mv 的最後一個參數；命令字前的 NAME=值、command、env、sudo 與路徑前綴不算。

骨架已經把引號內的字串去掉，所以這裡看到的運算子都是真的。
shortcut: 只認 >、>>、tee、cp、mv、git mv 的目的地；install、ln、rsync、sed -i、cp -t 與直譯器自己開檔寫入認不得，等真的有人用這些繞過再補。
"""
from __future__ import annotations

import re
import sys

REDIRECT_AMP = re.compile(r"\d*>&\d*-?|&>>?|\d*<&\d*-?")
SPLIT = re.compile(r"&&|\|\||;|\||&|\n|\(|\)")
REDIRECT = re.compile(r"(?:\d*|&)>>?\|?\s*([^\s<>&|;()]+)")
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?")
SHELLS = ("bash", "sh", "zsh", "dash", "ksh", "eval", "source")
PLACEHOLDER = "\0"
SPLIT_SUBST = " X "     # 切段時外層留一個獨立的 token
WRITE_SUBST = "$S"      # 找寫檔目標時黏在路徑上：$S/a.test.ts 的目錄含 $，呼叫者會當成讀不到


def matching_paren(text: str, open_index: int) -> int:
    """text[open_index] 是 (，回與它配對的 ) 的位置；沒配對到回最後一個字元。"""
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return len(text) - 1


def lift_substitutions(text: str, repl: str) -> tuple[str, list[str]]:
    """把 $(…)、反引號、<(…)、>(…) 的內容拆出來，外層換成 repl；$((…)) 算術不是指令，整塊換成 repl。回 (外層, 內層文字們)。"""
    outer, inner, i = [], [], 0
    while i < len(text):
        if text.startswith("$((", i):
            i = matching_paren(text, i + 1) + 1
            outer.append(repl)
        elif text.startswith("$(", i) or text.startswith("<(", i) or text.startswith(">(", i):
            end = matching_paren(text, i + 1)
            inner.append(text[i + 2:end])
            outer.append(repl)
            i = end + 1
        elif text[i] == "`":
            end = text.find("`", i + 1)
            end = len(text) if end < 0 else end
            inner.append(text[i + 1:end])
            outer.append(repl)
            i = end + 1
        else:
            outer.append(text[i])
            i += 1
    return "".join(outer), inner


def drop_data_heredocs(text: str) -> str:
    """heredoc 本體餵給 bash、sh、eval 這類直譯 shell 的才是 shell 指令，留著；餵給 cat、python 等的是資料或別的語言，拿掉。"""
    out, delim, keep = [], None, False
    for line in text.split("\n"):
        if delim is not None:
            if line.strip() == delim:
                delim = None
            elif keep:
                out.append(line)
            continue
        out.append(line)
        m = HEREDOC.search(line)
        if m:
            delim = m.group(1)
            words = line[:m.start()].split()
            keep = bool(words) and words[0].rsplit("/", 1)[-1] in SHELLS
    return "\n".join(out)


def split_text(text: str, repl: str) -> list[str]:
    outer, inner = lift_substitutions(text, repl)
    protected = REDIRECT_AMP.sub(lambda m: m.group(0).replace("&", PLACEHOLDER), outer)
    segments = [p.replace(PLACEHOLDER, "&").strip() for p in SPLIT.split(protected) if p.strip()]
    for body in inner:
        segments += split_text(body, repl)
    return segments


def split_segments(skeleton: str, repl: str = SPLIT_SUBST) -> list[str]:
    return split_text(drop_data_heredocs(skeleton), repl)


def positional(tokens: list[str]) -> list[str]:
    return [t for t in tokens if not t.startswith("-")]


def git_subcommand_args(tokens: list[str]) -> tuple[str, list[str]]:
    """git 之後略過全域選項（-C、-c 帶一個值），回 (子命令, 子命令之後的 token)。"""
    i = 1
    while i < len(tokens) and tokens[i].startswith("-"):
        i += 2 if tokens[i] in GIT_VALUED else 1
    if i >= len(tokens):
        return "", []
    return tokens[i], tokens[i + 1:]


COMMAND_PREFIXES = ("command", "env", "sudo", "exec", "nohup", "time")
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
GIT_VALUED = ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env", "--exec-path")


def segment_writes(segment: str) -> list[str]:
    # 骨架裡引號內有空白或 $ 的字串已換成 ""、沒有空白的已去掉引號，所以照空白切就是 token；
    # 留在 token 裡的 "" 代表那一塊被拿掉了，呼叫者看到引號就知道這個路徑讀不全
    out = [m.group(1) for m in REDIRECT.finditer(segment)]
    tokens = segment.split()
    while tokens and (ASSIGNMENT.match(tokens[0]) or tokens[0] in COMMAND_PREFIXES):
        tokens = tokens[1:]
    if not tokens:
        return out
    word = tokens[0].rsplit("/", 1)[-1]
    if word == "tee":
        out += positional(tokens[1:])
    elif word in ("cp", "mv"):
        args = positional(tokens[1:])
        if len(args) >= 2:
            out.append(args[-1])
    elif word == "git":
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
            lines = [t for seg in split_segments(skeleton, WRITE_SUBST) for t in segment_writes(seg)]
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
