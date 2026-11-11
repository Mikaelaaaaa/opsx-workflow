"""指令骨架（hooks/cmd-skeleton.pl 的輸出）的三種拆法，給 hooks/opsx-grant-gate.sh 用。

    cmdsegments.py split    stdin 一條骨架，每一段印一行。段以 &&、||、;、|、&、換行與子 shell 括號分隔；
                            重導向裡的 &（2>&1、>&2、>&檔名、&>檔名）不算分隔；$(…)、反引號、<(…)、>(…) 與算術 $((…)) 裡的
                            命令替換拆成自己的段。heredoc 骨架已經處理過（非直譯器的本體與結尾行已移掉），這裡不再碰。
    cmdsegments.py writes   stdin 一條骨架，每個寫檔目標印一行：重導向 >、>>、>&檔名，tee，cp 與 mv 的最後一個參數，git mv 的最後一個參數；
                            命令字前的 NAME=值、command、env、sudo 與路徑前綴不算。
    cmdsegments.py segment  stdin 一段指令，第一行印命令種類（cp、mv、tee、git mv 印 writer，其餘印命令字的 basename），其後每行一個寫檔目標。

骨架已經把引號內的字串去掉，所以這裡看到的運算子都是真的。
shortcut: 只認 >、>>、tee、cp、mv、git mv 的目的地；install、ln、rsync、sed -i、cp -t 與直譯器自己開檔寫入認不得，等真的有人用這些繞過再補。
"""
from __future__ import annotations

import re
import sys

REDIRECT_AMP = re.compile(r"\d*>&\d*-?|&>>?|\d*<&\d*-?")
SPLIT = re.compile(r"&&|\|\||;|\||&|\n|\(|\)")
# 寫檔：>file、>>file、1>file、&>file、>|file，與 >&file（目標不是數字或 - 才是檔案，>&2 是 fd 複製）
REDIRECT = re.compile(r"(?:\d*|&)>>?\|?\s*([^\s<>&|;()]+)|>&(?!\d+(?:\s|$|[;&|)])|-)([^\s<>&|;()]+)")
PLACEHOLDER = "\0"
SPLIT_SUBST = " X "     # 切段時外層留一個獨立的 token
WRITE_SUBST = "$S"      # 找寫檔目標時黏在路徑上：$S/a.test.ts 的目錄含 $，呼叫者會當成讀不到
COMMAND_PREFIXES = ("command", "env", "sudo", "exec", "nohup", "time")
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
GIT_VALUED = ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env", "--exec-path")


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
    """把 $(…)、反引號、<(…)、>(…) 的內容拆出來，外層換成 repl。回 (外層, 內層文字們)。
    $((…)) 以 )) 結尾才是算術：本體裡的命令替換照拆，算術本身換成 repl；不以 )) 結尾的（$((cmd) )）是 $( 加子 shell，整個當命令替換。"""
    outer, inner, i = [], [], 0
    while i < len(text):
        if text.startswith("$((", i):
            end = matching_paren(text, i + 1)
            if end - 1 > i + 2 and text[end - 1] == ")":
                _, found = lift_substitutions(text[i + 3:end - 1], repl)
                inner += found
            else:
                inner.append(text[i + 2:end])
            outer.append(repl)
            i = end + 1
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


def split_text(text: str, repl: str) -> list[str]:
    outer, inner = lift_substitutions(text, repl)
    protected = REDIRECT_AMP.sub(lambda m: m.group(0).replace("&", PLACEHOLDER), outer)
    segments = [p.replace(PLACEHOLDER, "&").strip() for p in SPLIT.split(protected) if p.strip()]
    for body in inner:
        segments += split_text(body, repl)
    return segments


def positional(tokens: list[str]) -> list[str]:
    return [t for t in tokens if not t.startswith("-")]


def git_subcommand_args(tokens: list[str]) -> tuple[str, list[str]]:
    """git 之後略過全域選項（-C、-c 等帶一個值），回 (子命令, 子命令之後的 token)。"""
    i = 1
    while i < len(tokens) and tokens[i].startswith("-"):
        i += 2 if tokens[i] in GIT_VALUED else 1
    if i >= len(tokens):
        return "", []
    return tokens[i], tokens[i + 1:]


def command_tokens(segment: str) -> list[str]:
    """照空白切（骨架裡引號內有空白或 $ 的字串已換成 ""、沒有空白的已去掉引號，所以照空白切就是 token），
    去掉命令字前的 NAME=值 與 command、env、sudo 等前綴。"""
    tokens = segment.split()
    while tokens and (ASSIGNMENT.match(tokens[0]) or tokens[0] in COMMAND_PREFIXES):
        tokens = tokens[1:]
    return tokens


def segment_command(segment: str) -> tuple[str, list[str]]:
    """回 (命令種類, 寫檔目標們)。cp、mv、tee、git mv 的種類是 writer，其餘是命令字的 basename，空段是空字串。
    留在目標裡的 "" 代表骨架拿掉了一塊，呼叫者看到引號就知道這個路徑讀不全。"""
    targets = [m.group(1) or m.group(2) for m in REDIRECT.finditer(segment)]
    tokens = command_tokens(segment)
    if not tokens:
        return "", targets
    word = tokens[0].rsplit("/", 1)[-1]
    if word == "tee":
        return "writer", targets + positional(tokens[1:])
    if word in ("cp", "mv"):
        args = positional(tokens[1:])
        return "writer", targets + (args[-1:] if len(args) >= 2 else [])
    if word == "git":
        sub, rest = git_subcommand_args(tokens)
        args = positional(rest)
        if sub == "mv":
            return "writer", targets + (args[-1:] if len(args) >= 2 else [])
    return word, targets


def main(mode: str, text: str) -> int:
    if mode == "split":
        lines = split_text(text, SPLIT_SUBST)
    elif mode == "writes":
        lines = [t for seg in split_text(text, WRITE_SUBST) for t in segment_command(seg)[1]]
    elif mode == "segment":
        kind, targets = segment_command(text.strip())
        lines = [kind] + targets
    else:
        print("cmdsegments: 不認得的模式 %r（split、writes 或 segment）" % mode, file=sys.stderr)
        return 2
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("用法：cmdsegments.py split|writes|segment（stdin 一條指令骨架或一段指令）", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.stdin.read()))
