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

MAX_DISPATCH = 6
REDISPATCH_MINUTES = 10
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
            self.plans[top] = read_workplan(os.path.join(top, "openspec", "workplan.yaml"))
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

    def clean_up(self, top, merged):
        self.act(["git", "-C", top, "checkout", "-q", "main"])
        self.act(["git", "-C", top, "pull", "-q"])
        for c in merged:
            key = card_key(c)
            self.log("++ %s 已合併，收尾" % key)
            entry = self.dispatch_file.get(key)
            if entry:
                self.act(["opsx", "stop", c["slug"], "--repo", top])
            self.act(["openspec", "archive", c["slug"], "-y"], cwd=top)
            wt = os.path.join(top, ".claude", "worktrees", c["slug"])
            if os.path.isdir(wt):
                self.act(["git", "-C", top, "worktree", "remove", "--force", wt])
            if entry and entry.get("branch"):
                self.act(["git", "-C", top, "branch", "-D", entry["branch"]])
            else:
                self.log("?? %s dispatch.json 沒記分支，分支沒刪" % key)
            self.memo["_approved"].pop(key, None)
        self.act(["git", "-C", top, "worktree", "prune"])

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
                self.memo["_parked"][key] = self.now.isoformat(timespec="seconds")
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

    def dispatch_new(self, cards, repo_paths, merged_this_round):
        n = 0
        for c in cards:
            if c["section"] != "待指派" or c["archived"]:
                continue
            key, top = card_key(c), repo_paths[c["repo"]]
            entry = self.dispatch_file.get(key)
            parked = key in self.memo["_parked"]
            if entry and entry.get("mode") == "stopped" and not parked:
                continue   # 人在板上停掉的
            if parked and not merged_this_round:
                continue
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


def read_workplan(path):
    """workplan.yaml 的 PR 名 → (status, depends-on)。格式固定、沒有 pyyaml，用正則讀。沒有檔就是沒有依賴。"""
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out = {}
    for block in re.split(r"\n      - name: ", text)[1:]:
        name = block.split("\n", 1)[0].strip()
        st = re.search(r"^\s+status:\s*(\S+)", block, re.M)
        deps = re.search(r"depends-on:\s*\[([^\]]*)\]", block)
        out[name] = (st.group(1) if st else "", [d.strip() for d in (deps.group(1) if deps else "").split(",") if d.strip()])
    return out


def deps_unmerged(slug, plan):
    if slug not in plan:
        return []
    return [d for d in plan[slug][1] if d not in plan or plan[d][0] != "merged"]


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
    if c["archived"]:
        return False
    if c["mr"] and c["mr"].get("merged_at"):
        return True
    return c["stage"] == "archive" and bool(c["dispatch"])


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
    for c in cards:
        if c not in merged and c["mr"] and c["mr"]["state"] == "ready":
            r.approve_merge(c, repo_paths[c["repo"]])
    for repo in sorted({c["repo"] for c in merged}):
        r.clean_up(repo_paths[repo], [c for c in merged if c["repo"] == repo])
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
    r.dispatch_new(live, repo_paths, bool(merged))
    r.save()
    r.log("== 結束：%d 張卡，收尾 %d 張" % (len(live), len(merged)))


if __name__ == "__main__":
    main()
