"""opsx reap：關掉 opsx collect 列出的孤兒 pane。規則見 openspec/specs/opsx-reap/spec.md。

孤兒的判定只在 collect 算一次（orphans[]）；這裡只決定「這一個現在能不能關」：
agent 要 idle，而且 pane 上不能還有活著的卡（代管卡與兄弟卡、fan-out 的父子卡共用 pane）。
用法：reap.py <state dir> <opsx 入口> [--root <dir>] [--pane <id>] [--dry]
"""
import datetime
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonfile  # noqa: E402


class ReapError(Exception):
    """這一輪讀不到該讀的狀態，不關任何 pane。"""


class MarkReaped:
    """jsonfile.update 的 mutate：給這一條補 reaped_at，條目保留。"""

    def __init__(self, key, at):
        self.key = key
        self.at = at

    def __call__(self, d):
        d[self.key]["reaped_at"] = self.at


def now_iso():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def cell(text):
    return text.replace("\t", " ").replace("\n", " ").replace("\r", " ")


def run(args):
    p = subprocess.run(args, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def parse(argv):
    opts = {"root": None, "pane": None, "dry": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--dry":
            opts["dry"] = True
        elif a in ("--root", "--pane"):
            if i + 1 >= len(argv):
                raise ReapError("%s 要接一個值" % a)
            opts[a[2:]] = argv[i + 1]
            i += 1
        else:
            raise ReapError("reap: 不認得的參數 %s" % a)
        i += 1
    return opts


def collect(opsx, root):
    rc, out, err = run(["bash", opsx, "collect"] + (["--root", root] if root else []))
    if rc != 0:
        raise ReapError("opsx collect 失敗（rc %d）：%s" % (rc, err[:300]))
    try:
        data = json.loads(out)
    except json.JSONDecodeError as e:
        raise ReapError("opsx collect 的輸出不是 JSON：%s" % e) from e
    herdr = [e["message"] for e in data["errors"] if e["source"] == "herdr"]
    if herdr:
        raise ReapError("herdr 讀不到，agent 狀態不可得，不關任何 pane：%s" % "；".join(herdr))
    return data


def protected_panes(cards, dispatch):
    """還有活卡的 pane。活卡：沒歸檔、不是 split、dispatch.json 不是 stopped。代管卡（via）的活也算協調它的那個 pane。"""
    live = {"%s/%s" % (c["repo"], c["slug"]) for c in cards if not c["archived"] and c["stage"] != "split"}
    panes = set()
    for key, e in dispatch.items():
        if key not in live or e.get("mode") == "stopped":
            continue
        panes.add(str(e.get("pane")))
        if e.get("via"):
            panes.add(str(dispatch.get("%s/%s" % (key.split("/", 1)[0], e["via"]), {}).get("pane")))
    return panes


class Reaper:
    def __init__(self, state, opsx, dry, repo_paths):
        self.state = state
        self.opsx = opsx
        self.dry = dry
        self.repo_paths = repo_paths
        self.dispatch_path = os.path.join(state, "dispatch.json")

    def note(self, o, text):
        """沒關的原因，或卡目錄不在時關掉的紀錄：<state>/reap.log。"""
        os.makedirs(self.state, exist_ok=True)
        with open(os.path.join(self.state, "reap.log"), "a", encoding="utf-8") as f:
            f.write("%s\t%s\t%s\n" % (now_iso(), cell("%s/%s %s" % (o["repo"], o["slug"], o["pane"])), cell(text)))

    def skip(self, o, text):
        if self.dry:
            print("DRY %s" % text)
        else:
            self.note(o, text)

    def close(self, o):
        text = "孤兒 pane %s 關掉（%s）" % (o["pane"], o["reason"])
        if self.dry:
            print("DRY herdr pane close %s（%s/%s，%s）" % (o["pane"], o["repo"], o["slug"], o["reason"]))
            return
        rc, _, err = run(["herdr", "pane", "close", o["pane"]])
        if rc != 0:
            # shortcut: 任何失敗都當 pane 已不在，spec 這樣定；錯誤文字留在 log，之後若出現關不掉的真錯誤再分碼
            text += "；herdr 回錯，當作 pane 已不在：%s" % err[:120]
        key = "%s/%s" % (o["repo"], o["slug"])
        jsonfile.update(self.dispatch_path, MarkReaped(key, now_iso()))
        card = os.path.join(self.repo_paths[o["repo"]], "openspec", "changes", o["slug"])
        if os.path.isdir(card):
            rc, _, err = run(["bash", self.opsx, "log", o["slug"], "reaper", "已停止", text, "", "--repo", self.repo_paths[o["repo"]]])
            if rc != 0:
                raise ReapError("opsx log 寫不進 %s：%s" % (card, err[:200]))
        else:
            self.note(o, text)
        print("reap: %s" % text)


def main():
    state, opsx = sys.argv[1], sys.argv[2]
    try:
        opts = parse(sys.argv[3:])
        data = collect(opsx, opts["root"])
    except ReapError as e:
        print("opsx: %s" % e, file=sys.stderr)
        sys.exit(1)
    orphans = data["orphans"]
    if opts["pane"]:
        orphans = [o for o in orphans if o["pane"] == opts["pane"]]
        if not orphans:
            print("opsx: reap: pane %s 不是孤兒（孤兒：%s）" % (opts["pane"], "、".join(o["pane"] for o in data["orphans"]) or "沒有"), file=sys.stderr)
            sys.exit(2)
    r = Reaper(state, opsx, opts["dry"], data["repo_paths"])
    protected = protected_panes(data["cards"], jsonfile.load(r.dispatch_path))
    try:
        for o in orphans:
            if o["pane"] in protected:
                r.skip(o, "pane %s 上還有活著的卡，不關" % o["pane"])
            elif o["agent_status"] != "idle":
                r.skip(o, "pane %s 的 agent 是 %s，這輪不關" % (o["pane"], o["agent_status"]))
            else:
                r.close(o)
    except ReapError as e:
        print("opsx: %s" % e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
