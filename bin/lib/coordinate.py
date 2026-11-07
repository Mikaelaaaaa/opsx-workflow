"""opsx coordinate 的一輪：讀 opsx collect，依序核准合併、收尾已合併的卡、答 gate、停等依賴的卡、重派死掉的卡、派新卡。

每個動作是一條外部指令（opsx / git / openspec）。推節點（送 /<stage>）是每張卡的 drive 的事，這裡不送。
規則見 openspec/specs/opsx-coordinate/spec.md。
用法：coordinate.py <state dir> [--dry]
"""
import datetime
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chain  # noqa: E402

MAX_DISPATCH = 6
REDISPATCH_MINUTES = 10
# 合併後交給卡自己的 /archive（它標 workplan merged、叫 opsx chain）；過了這麼久還沒歸檔就要人看
ARCHIVE_GRACE_MINUTES = 30
AGENT_NAME = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
VERIFY_WORDS = ("真機", "實測", "瀏覽器", "herdr 驗", "resume", "真的 claude", "真 herdr", "量測")
GRANT_WORDS = ("授權", "開 PR", "開 / 改 MR", "gh pr create", "push", "推到 origin", "rebase")
# 建議或選項裡有這些字，代表要人動手；不替人承諾
HUMAN_WORDS = ("你", "使用者", "沙盒外", "自己跑", "本人", "人工", "跑指令", "跑腳本", "錄", "貼路徑")
HUMAN_QUESTION = ("只有你能做", "誰來跑")
# 卡在等別張卡合併：不答，答了它查完又會開一個 gate
WAIT_WORDS = ("合進 main", "merge 之後", "merged 之後", "merge 之前", "之後再派", "合併後", "等它 merge", "等 .* 合")
VERIFY_ANSWER = "這個要真機跑的驗證使用者之後自己做：把它標成「等使用者驗」寫進 report.md 的 Consider，不要再開 gate，繼續做完剩下的 task 到 /review、/pr。"
GRANT_ANSWER = "允許。長期授權在 grants.toml，直接做。"


class CoordinateError(Exception):
    """這一輪讀不到該讀的狀態：寫 log、非 0 結束，不對任何卡動手。"""


class Round:
    def __init__(self, state, dry):
        self.state = state
        self.dry = dry
        self.log_path = os.path.join(state, "coordinator.log")
        self.memo_path = os.path.join(state, "coordinator-memo.json")
        self.now = datetime.datetime.now().astimezone()
        self.memo = None
        self.dispatch_file = None
        self.plans = {}

    def log(self, msg):
        line = "%s %s" % (self.now.strftime("%Y-%m-%d %H:%M:%S"), msg)
        print(line)
        with open(self.log_path, "a", encoding="utf-8") as f:
            f.write(line + "\n")

    def run(self, args, cwd=None):
        p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
        return p.returncode, p.stdout.strip(), p.stderr.strip()

    def act(self, args, cwd=None):
        if self.dry:
            self.log("DRY " + " ".join(args))
            return 0, "", ""
        rc, out, err = self.run(args, cwd)
        tail = (err or out).replace("\n", " ")[:200]
        self.log(("ok   " if rc == 0 else "rc%-2d " % rc) + " ".join(args)[:160] + (" → " + tail if tail else ""))
        return rc, out, err

    def load(self):
        rc, out, err = self.run(["opsx", "collect"])
        if rc != 0:
            raise CoordinateError("opsx collect 失敗（rc %d）：%s" % (rc, err[:300]))
        try:
            data = json.loads(out)
        except json.JSONDecodeError as e:
            raise CoordinateError("opsx collect 的輸出不是 JSON：%s" % e) from e
        herdr = [e["message"] for e in data["errors"] if e["source"] == "herdr"]
        if herdr:
            raise CoordinateError("herdr 讀不到，agent 狀態不可得，這輪不動：%s" % "；".join(herdr))
        self.memo = read_json(self.memo_path, "coordinator memo")
        for k in ("_parked", "_redispatched", "_approved"):
            self.memo.setdefault(k, {})   # 沒有這個 key 就是還沒記過任何一張
        self.dispatch_file = read_json(os.path.join(self.state, "dispatch.json"), "dispatch.json")
        return data

    def save(self):
        if self.dry:
            return
        tmp = self.memo_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.memo, f, ensure_ascii=False, indent=1)
        os.replace(tmp, self.memo_path)

    def workplan(self, top):
        if top not in self.plans:
            self.plans[top] = read_prs(os.path.join(top, "openspec", "workplan.yaml"))
        return self.plans[top]

    def approve_merge(self, c, top):
        key, mr = card_key(c), c["mr"]
        if self.memo["_approved"].get(key) == mr["head_sha"]:
            return
        rc, _, err = self.act(["opsx", "merge", c["slug"], "--repo", top])
        if rc != 0:
            self.log("?? %s 核准合併被拒：%s" % (key, err[:200]))
            return
        self.memo["_approved"][key] = mr["head_sha"]
        self.log("++ %s 五條件全綠，核准合併 %s（%s）" % (key, mr["head_sha"], mr["url"]))

    def wait_for_archive(self, c):
        """已合併但 agent 還在：歸檔、標 workplan、叫 chain 都是它自己 /archive 的事，這裡不搶。"""
        key = card_key(c)
        ago = self.now - datetime.datetime.fromisoformat(c["mr"]["merged_at"])
        if ago > datetime.timedelta(minutes=ARCHIVE_GRACE_MINUTES):
            self.log("?? %s 合併 %d 分鐘了還沒歸檔，agent 還在，要人看它卡在哪" % (key, ago.total_seconds() // 60))
        else:
            self.log("⏳ %s 已合併，等它自己 /archive" % key)

    def clean_up(self, top, merged):
        """agent 已經不在的已合併卡：代做 /archive 的事。回傳收尾成功的卡。"""
        self.update_main(top)
        done = [c for c in merged if self.archive_card(top, c)]
        self.act(["git", "-C", top, "worktree", "prune"])
        return done

    def update_main(self, top):
        """主 checkout 是別的 session 共用的：只在它本來就在 main 而且乾淨時快轉，絕不 checkout。"""
        rc1, branch, err1 = self.run(["git", "-C", top, "rev-parse", "--abbrev-ref", "HEAD"])
        rc2, dirty, err2 = self.run(["git", "-C", top, "status", "--porcelain"])
        if rc1 != 0 or rc2 != 0:
            self.log("?? %s 讀不到主 checkout 的狀態，不 pull：%s" % (top, (err1 or err2)[:200]))
        elif branch != "main":
            self.log("-- %s 主 checkout 在 %s，不 pull" % (top, branch))
        elif dirty:
            self.log("-- %s 主 checkout 有沒 commit 的改動，不 pull" % top)
        else:
            rc, _, err = self.act(["git", "-C", top, "pull", "-q", "--ff-only"])
            if rc != 0:
                self.log("?? %s 主 checkout pull --ff-only 失敗：%s" % (top, err[:200]))

    def archive_card(self, top, c):
        key = card_key(c)
        entry = self.dispatch_file.get(key)
        self.log("++ %s 已在 forge 合併、agent 不在，收尾" % key)
        if entry and entry.get("mode") != "stopped":
            self.act(["opsx", "stop", c["slug"], "--repo", top])
        if not self.mark_merged(top, c["slug"]):
            return False
        rc, _, err = self.act(["openspec", "archive", c["slug"], "-y"], cwd=top)
        if rc != 0:
            self.log("?? %s openspec archive 失敗：%s" % (key, err[:200]))
            return False
        self.memo["_approved"].pop(key, None)
        # 沒記 worktree 的是早期派的卡，當時 worktree 一律開在這裡
        wt = entry["worktree"] if entry and entry.get("worktree") else os.path.join(top, ".claude", "worktrees", c["slug"])
        if os.path.isdir(wt):
            rc, _, err = self.act(["git", "-C", top, "worktree", "remove", "--force", wt])
            if rc != 0:
                self.log("?? %s worktree %s 刪不掉，分支也不刪：%s" % (key, wt, err[:200]))
                return True
        if not entry or not entry.get("branch"):
            self.log("?? %s dispatch.json 沒記分支，分支沒刪" % key)
            return True
        rc, _, err = self.act(["git", "-C", top, "branch", "-D", entry["branch"]])
        if rc != 0:
            self.log("?? %s 分支 %s 刪不掉：%s" % (key, entry["branch"], err[:200]))
        return True

    def mark_merged(self, top, slug):
        """把 workplan 裡含這個 change 的 PR 標成 merged，依賴它的卡這輪就派得出去。不在 workplan 裡的卡沒東西要標。"""
        path = os.path.join(top, "openspec", "workplan.yaml")
        pr = pr_of(self.workplan(top), slug)
        if pr is None:
            self.log("-- %s 不在 %s，沒有 PR 要標 merged" % (slug, path))
            return True
        if self.dry:
            self.log("DRY workplan %s 的 PR %s 標 merged" % (path, pr["name"]))
            return True
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        i = status_line(lines, pr["name"])
        if i is None:
            self.log("?? %s 找不到 PR %s 的 status 行，不收尾" % (path, pr["name"]))
            return False
        lines[i] = re.sub(r"status:.*$", "status: merged", lines[i])
        tmp = path + ".coordinate.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        os.replace(tmp, path)
        self.plans.pop(top, None)
        self.log("ok   workplan 的 PR %s 標 merged" % pr["name"])
        return True

    def answer(self, c, top, gate, text, grant=False):
        args = ["opsx", "answer", c["slug"], "--gate", gate] + (["--grant", "this"] if grant else []) + ["--repo", top, "--", text]
        rc, out, err = self.act(args)
        if "agent_not_found" in out + err:
            self.redispatch(c, top, "answer 送不到")
        elif rc != 0:
            self.log("?? %s gate %s 回不了：%s" % (card_key(c), gate, err[:200]))

    def handle_gate(self, c, top):
        """派出去的卡的第一個 open gate，照固定規則答、停、或留給人。"""
        w, key = c["waiting"], card_key(c)
        if w["type"] == "等待授權":
            if w["action"] == "merge":   # 合併只走 approve_merge 的五條件、綁 sha 核准；這裡給「這次」會繞過它
                self.log("?? %s gate %s 要合併授權，不代答：合併由 opsx merge 核准" % (key, w["gate_id"]))
                return
            self.answer(c, top, w["gate_id"], "允許", grant=True)
            return
        if w["type"] == "終端機等待輸入":
            self.log("?? %s 在 pane %s 等終端機輸入（autopilot 不該問 pane），要人看" % (key, c["dispatch"].get("pane")))
            return
        q = w.get("question") or ""
        pick = w.get("recommended") or (w.get("options") or [None])[0]
        if any(k in q for k in VERIFY_WORDS):
            self.answer(c, top, w["gate_id"], VERIFY_ANSWER)
            return
        if any(k in q for k in GRANT_WORDS):
            self.answer(c, top, w["gate_id"], GRANT_ANSWER)
            return
        if any(re.search(k, q + " " + (pick or "")) for k in WAIT_WORDS):
            self.log("⏳ %s gate %s 在等別張卡，先停 pane，有卡合進 main 那輪再派：%s" % (key, w["gate_id"], q[:100]))
            rc, _, _ = self.act(["opsx", "stop", c["slug"], "--repo", top])
            if rc == 0:
                self.memo["_parked"][key] = {"at": self.now.isoformat(timespec="seconds"), "gate": w["gate_id"],
                                             "merged": merged_prs(self.workplan(top))}
            return
        if not pick:
            self.log("?? %s gate %s 沒有選項也沒有建議，要人看：%s" % (key, w["gate_id"], q[:120]))
            return
        if any(k in pick for k in HUMAN_WORDS) or any(k in q for k in HUMAN_QUESTION):
            self.log("?? %s gate %s 要人動手，不代答：%s → %s" % (key, w["gate_id"], q[:100], pick[:60]))
            return
        self.answer(c, top, w["gate_id"], pick)

    def redispatch(self, c, top, why):
        key = card_key(c)
        last = self.memo["_redispatched"].get(key)
        if last and self.now - datetime.datetime.fromisoformat(last) < datetime.timedelta(minutes=REDISPATCH_MINUTES):
            self.log("-- %s %s，%d 分鐘內重派過，這輪不再派" % (key, why, REDISPATCH_MINUTES))
            return
        if "agent" not in c["dispatch"]:
            self.log("?? %s %s，但 dispatch.json 沒記 agent，不知道派給誰" % (key, why))
            return
        self.log("!! %s %s，stop 後重派" % (key, why))
        self.act(["opsx", "stop", c["slug"], "--repo", top])
        self.act(["opsx", "dispatch", c["slug"], "--agent", c["dispatch"]["agent"], "--mode", "autopilot", "--kind", c["kind"], "--repo", top])
        self.memo["_redispatched"][key] = self.now.isoformat(timespec="seconds")

    def dispatch_new(self, cards, repo_paths):
        n = 0
        for c in cards:
            key, top = card_key(c), repo_paths[c["repo"]]
            entry = self.dispatch_file.get(key)
            parked = self.memo["_parked"].get(key)
            newly = []
            if parked:
                # 等的 gate 還開著，collect 把它放在「待處理」。停下之後 workplan 多了 merged 的 PR 才重派：
                # 不管是卡自己 /archive 標的，還是這裡收尾時標的
                newly = [p for p in merged_prs(self.workplan(top)) if p not in parked["merged"]]
                if not newly or c["dispatch"] or c["section"] not in ("待指派", "待處理"):
                    continue
            elif c["section"] != "待指派":
                continue
            elif entry and entry.get("mode") == "stopped":
                continue   # 人在板上停掉的
            if not os.path.isfile(os.path.join(c["path"], "tasks.md")) or c["mr"]:
                continue
            missing = deps_unmerged(c["slug"], self.workplan(top))
            if missing:
                self.log("⏳ %s 等 %s merged 才派" % (key, "、".join(missing)))
                continue
            if not AGENT_NAME.match(c["slug"]):
                self.log("-- %s 不是合法的 agent 名，跳過" % key)
                continue
            if n >= MAX_DISPATCH:
                self.log("-- 這輪派滿 %d 張，%s 下輪" % (MAX_DISPATCH, key))
                continue
            if parked:
                text = "停下之後合進 main 的 PR：%s。照最新的 main 繼續；你等的那張還沒合就再開 gate。" % "、".join(newly)
                rc, _, err = self.act(["opsx", "answer", c["slug"], "--gate", parked["gate"], "--repo", top, "--", text])
                if rc != 0:
                    self.log("?? %s parked 的 gate %s 回不了，不重派：%s" % (key, parked["gate"], err[:200]))
                    continue
            agent = entry["agent"] if entry and "agent" in entry else "claude"
            rc, _, err = self.act(["opsx", "dispatch", c["slug"], "--agent", agent, "--mode", "autopilot", "--kind", c["kind"], "--repo", top])
            n += 1
            if rc != 0:
                self.log("?? %s 派不出去：%s" % (key, err[:200]))
                continue
            self.memo["_parked"].pop(key, None)


def card_key(c):
    return "%s/%s" % (c["repo"], c["slug"])


def read_json(path, what):
    """不存在等於空的；存在但讀不懂就失敗，不當成空的（parked 會無聲消失）。"""
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        text = f.read()
    try:
        return json.loads(text or "{}")
    except json.JSONDecodeError as e:
        raise CoordinateError("%s（%s）不是合法 JSON：%s" % (what, path, e)) from e


def read_prs(path):
    """workplan.yaml 所有 feature 底下的 PR，用 chain.py 同一個 parser。沒有檔就是沒有 PR、沒有依賴。"""
    if not os.path.exists(path):
        return []
    return [pr for f in chain.load_workplan(path).get("features") or [] for pr in f.get("prs") or []]


def merged_prs(prs):
    return [p.get("name") for p in prs if p.get("status") == "merged"]


def pr_of(prs, slug):
    """change 所屬的 PR（PR 名常常跟 change 名不同）；workplan 裡沒有就是 None。"""
    for pr in prs:
        if any(c.get("name") == slug for c in pr.get("changes") or []):
            return pr
    return None


def deps_unmerged(slug, prs):
    pr = pr_of(prs, slug)
    if pr is None:
        return []
    status = {p.get("name"): p.get("status") for p in prs}
    return [d for d in pr.get("depends-on") or [] if status.get(d) != "merged"]


def status_line(lines, pr_name):
    """PR「pr_name」自己的 status 行的 index：PR 那行（prs: 底下的 `- name:`）之後、它的 changes: 之前。"""
    pr_indent = None
    for i, line in enumerate(lines):
        m = re.match(r"^( *)prs:\s*$", line)
        if m:
            pr_indent = len(m.group(1)) + 2
            continue
        if pr_indent is None or not re.match(r"^ {%d}- name:\s*%s\s*(#.*)?$" % (pr_indent, re.escape(pr_name)), line):
            continue
        for j in range(i + 1, len(lines)):
            if re.match(r"^ {%d}status:" % (pr_indent + 2), lines[j]):
                return j
            if lines[j].strip() and len(lines[j]) - len(lines[j].lstrip(" ")) <= pr_indent:
                return None
        return None
    return None


def drive_dead(disp):
    pid = disp.get("drive_pid")
    if not pid:
        return False
    try:
        os.kill(int(pid), 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    return False


def is_merged(c):
    """forge 說合了才算；只看 workplan 的 merged 不算，那可能是卡自己 /archive 做到一半。"""
    return bool(c["mr"] and c["mr"]["merged_at"])


def owner_gone(c):
    return not c["dispatch"] or c["agent_status"] == "unknown" or drive_dead(c["dispatch"])


def main():
    state = sys.argv[1]
    r = Round(state, "--dry" in sys.argv[2:])
    try:
        data = r.load()
    except CoordinateError as e:
        r.log("!! coordinator 這輪不跑：%s" % e)
        sys.exit(1)
    r.log("== coordinator 開始" + ("（dry）" if r.dry else ""))
    repo_paths = data["repo_paths"]
    cards = [c for c in data["cards"] if not c["archived"]]

    merged = [c for c in cards if is_merged(c)]
    orphans = [c for c in merged if owner_gone(c)]
    for c in merged:
        if c not in orphans:
            r.wait_for_archive(c)
    for c in cards:
        if c not in merged and c["mr"] and c["mr"]["state"] == "ready":
            r.approve_merge(c, repo_paths[c["repo"]])
    done = []
    for repo in sorted({c["repo"] for c in orphans}):
        done += r.clean_up(repo_paths[repo], [c for c in orphans if c["repo"] == repo])
    live = [c for c in cards if c not in merged]

    for c in live:
        w = c["waiting"]
        if c["dispatch"] and w and w["type"] != "可以合併":
            r.handle_gate(c, repo_paths[c["repo"]])
    for c in live:
        if not c["dispatch"] or card_key(c) in r.memo["_parked"]:
            continue
        if c["agent_status"] == "unknown":
            r.redispatch(c, repo_paths[c["repo"]], "agent 不在 herdr 裡（pane %s）" % c["dispatch"].get("pane"))
        elif drive_dead(c["dispatch"]):
            r.redispatch(c, repo_paths[c["repo"]], "drive pid %s 已經不在" % c["dispatch"]["drive_pid"])
    r.dispatch_new(live, repo_paths)
    r.save()
    r.log("== 結束：%d 張卡，收尾 %d 張" % (len(live), len(done)))


if __name__ == "__main__":
    main()
