"""opsx coordinate 的一輪：讀 opsx collect，依序收尾已合併的卡、通知等人答的 gate、停等依賴的卡、重派死掉的卡、派新卡。

每個動作是一條外部指令（opsx / git / openspec）。推節點（送 /<stage>）是每張卡的 drive 的事，這裡不送。
合併永遠由人按（板上的「合併」或 forge 網頁），這裡從不呼叫 opsx merge。
規則見 openspec/specs/opsx-coordinate/spec.md。
用法：coordinate.py <state dir> [--dry]
"""
import datetime
import fcntl
import functools
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from argslost import args_lost  # noqa: E402
import chain  # noqa: E402
import gaterule  # noqa: E402
import jsonfile  # noqa: E402
import priority  # noqa: E402
import safefile  # noqa: E402

MAX_DISPATCH = 6
# 同時 working 的卡數上限預設值；<state>/max-working 可改
DEFAULT_MAX_WORKING = 6
REDISPATCH_MINUTES = 10
# relaunch 失敗後同一個 pane 不再試的時間；跟重派同一個節流，不會每輪對壞掉的 pane 送 Esc、/exit
RELAUNCH_MINUTES = REDISPATCH_MINUTES
# relaunch.sh 寫的是當下時間，晚於現在超過這麼久的 relaunching_at 不可能是它寫的
CLOCK_SKEW_MINUTES = 1
# pid_t 是 32 位元有號整數，os.kill 收更大的值會 OverflowError
PID_MAX = 2**31 - 1
# 真實訊息是 `Usage limit reached[ again] · …`，前面只有 Claude Code 畫的 ⎿ │ 與空白；引用、清單、diff 行都不算
USAGE_LIMIT_LINE = re.compile(r"[\s⎿│]*Usage limit reached(?: again)?\s*·")
USAGE_LIMIT_STALE_MINUTES = 30
USAGE_LIMIT_WARNING = "grace allowance"   # 「還有一小段寬限」是警告，agent 還在跑，不算停下
USAGE_LIMIT_RESET = re.compile(r"(?:limit resets|continuing automatically at)\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)", re.IGNORECASE)
# 合併後交給卡自己的 /archive（它標 workplan merged、叫 opsx chain）；過了這麼久還沒歸檔就要人看
ARCHIVE_GRACE_MINUTES = 30
# 協調者 session 在 herdr 裡的 agent 名；hooks 與 common.sh 的 COORDINATOR_AGENT 是同一個名字
COORDINATOR = "opsx-coordinator"
# herdr 收不下這則 prompt 的兩種情形：沒有這個 agent、或它卡在對話框。兩種都改發桌面通知，人才收得到
COORDINATOR_UNAVAILABLE = ("agent_not_found", "agent_blocked")
AGENT_NAME = chain.AGENT_NAME
# gaterule.decide 回「留給人」時，各理由代碼寫進 log 的那行與通知標題後半
GATE_HUMAN = {
    "stuck": ("?? %(key)s gate %(gate)s 是 drive 或 Stop hook 卡住時寫的，建議欄是給人看的提示，不代答：%(q100)s", "卡住了，要你看"),
    "run": ("?? %(key)s gate %(gate)s 要人在終端機跑指令再貼結果，不代答：%(rec100)s", "要你在終端機跑指令"),
    "merge-grant": ("?? %(key)s gate %(gate)s 要合併授權，不代答：合併由人在板上按", "要合併授權"),
    "type": ("?? %(key)s gate %(gate)s 的 type 沒寫或不在 approval | decision，不代答，要人看：%(q100)s", "的 type 不明"),
    "split": ("?? %(key)s gate %(gate)s 是拆法確認，只有使用者能答，不代答、不停 pane：%(q100)s", "要你確認拆法"),
    "merge": ("?? %(key)s gate %(gate)s 是合併類決定題，不代答：%(q100)s → %(pick60)s", "是合併的決定"),
    "no-pick": ("?? %(key)s gate %(gate)s 沒有選項也沒有建議，要人看：%(q120)s", "沒有選項也沒有建議"),
    "hands": ("?? %(key)s gate %(gate)s 要人動手，不代答：%(q100)s → %(pick60)s", "要你動手"),
    "approval": ("?? %(key)s gate %(gate)s 要授權，不代答：%(q100)s", "要你授權"),
    "decision": ("?? %(key)s gate %(gate)s 要你決定，不代答：%(q100)s → %(pick60)s", "要你決定"),
}


class CoordinateError(Exception):
    """這一輪讀不到該讀的狀態：寫 log、非 0 結束，不對任何卡動手。"""


class DispatchFieldError(Exception):
    """dispatch.json 某個條目的欄位格式不合：只停那一張卡，記 ?? 並通知，這輪其他卡照跑。"""

    def __init__(self, key, field, value, reason):
        super().__init__("dispatch.json 條目 %s 的 %s=%s：%s" % (key, field, json.dumps(value, ensure_ascii=False), reason))
        self.key, self.field, self.value = key, field, value


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
        self.levels = {}
        self.level_errors = {}
        self.orders = {}
        self.redispatched_now = set()
        # 這輪已經看過、或已經動過（叫醒、重派）的 pane 根條目：check_args 不再看
        self.args_checked = set()
        self.stages = {}
        self.woken_cards = set()
        self.max_working = None
        self.woken = 0
        self.worktrees = {}

    def log(self, msg):
        line = "%s %s" % (self.now.strftime("%Y-%m-%d %H:%M:%S"), msg)
        print(line)
        with safefile.open_append(self.log_path) as f:
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
        self.max_working = read_max_working(os.path.join(self.state, "max-working"))
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
        for k in ("_parked", "_redispatched", "_notified", "_relaunched"):
            self.memo.setdefault(k, {})   # 沒有這個 key 就是還沒記過任何一張
        self.dispatch_file = read_json(os.path.join(self.state, "dispatch.json"), "dispatch.json")
        check_dispatch_entries(self.dispatch_file)
        self.stages = {card_key(c): c["stage"] for c in data["cards"]}
        return data

    def save(self):
        if self.dry:
            return
        safefile.write_atomic(self.memo_path, json.dumps(self.memo, ensure_ascii=False, indent=1))

    def workplan(self, top):
        if top not in self.plans:
            self.plans[top] = read_prs(os.path.join(top, "openspec", "workplan.yaml"))
        return self.plans[top]

    def level(self, top, slug):
        """卡的 {level, reason, overridden}，算不出來是 {error}。workplan 的 milestone 欄位不合格時那個 repo 每張卡都是 error。"""
        if top not in self.levels and top not in self.level_errors:
            try:
                self.levels[top] = priority.levels(top)
            except priority.PriorityError as e:
                self.level_errors[top] = str(e)
        if top in self.level_errors:
            return {"error": self.level_errors[top]}
        if slug not in self.levels[top]:
            return {"error": "%s 不在 openspec/changes 也不在 workplan" % slug}
        return self.levels[top][slug]

    def rank(self, c, top):
        """派工順序：(等級, 不在 workplan, milestone 位置, workplan 位置)；算不出等級的排最後，反正不派。"""
        got = self.level(top, c["slug"])
        lv = priority.LEVELS.index(got["level"]) if "level" in got else len(priority.LEVELS)
        if top not in self.orders:
            self.orders[top] = plan_order(os.path.join(top, "openspec", "workplan.yaml"))
        pos = self.orders[top].get(c["slug"])
        return (lv, 1, 0, 0) if pos is None else (lv, 0) + pos

    def nobody_archiving(self, c):
        """已合併但 agent 還在：歸檔、標 workplan、叫 chain 都是它自己 /opsx-workflow:archive 的事，這裡不搶。
        過了寬限 agent 還 idle，代表沒人會送 /opsx-workflow:archive（例如人在網頁上合併、drive 早就結束），回傳 True 由這裡收尾。"""
        key = card_key(c)
        ago = self.now - datetime.datetime.fromisoformat(c["mr"]["merged_at"])
        minutes = ago.total_seconds() // 60
        if ago <= datetime.timedelta(minutes=ARCHIVE_GRACE_MINUTES):
            self.log("⏳ %s 已合併，等它自己 /opsx-workflow:archive" % key)
            return False
        # idle 也可能是在等人回 gate，或互動模式的人暫時離開：那兩種不收，收了等於替人答 gate、關掉人的 session
        waiting_human = c["open_gates"] or self.dispatch_file[key].get("mode") == "interactive"
        if c["agent_status"] == "idle" and not waiting_human:
            self.log("-- %s 合併 %d 分鐘了 agent 還 idle，沒人會 /opsx-workflow:archive，這裡收尾" % (key, minutes))
            return True
        self.log("?? %s 合併 %d 分鐘了還沒歸檔，agent 是 %s，要人看它卡在哪" % (key, minutes, c["agent_status"]))
        return False

    def no_late_commits(self, top, c):
        """合併後分支沒有多出的 commit（或多出的已經有人答了 gate）才回 True，卡才收尾；收尾會刪分支，多出的 commit 本機就沒了。
        多出 commit 時 opsx late 已在卡上開 gate，這裡通知一次；查不出來不通知（不是人能處理的事件），下一輪再查。"""
        key = card_key(c)
        rc, out, err = self.act(["opsx", "late", c["slug"], "--repo", top, "--open-gate"])
        if rc == 0:
            return True
        m = re.match(r"late (\d+) (\w+) ", out + " ") if rc == 1 else None
        if rc == 1 and m:
            n, sha = m.groups()
            self.log("?? %s 合併後分支又多了 %s 個 commit，不收尾；卡上有 gate late-%s" % (key, n, sha))
            self.notify(c, "late", sha, "合併後分支又多了 %s 個 commit" % n, "看板：%s 的 gate late-%s" % (c["slug"], sha))
        else:
            self.log("?? %s opsx late 查不出來（rc %d），不收尾：%s" % (key, rc, (err or out).replace("\n", " ")[:200]))
        return False

    def clean_up(self, top, merged):
        """agent 已經不在的已合併卡：代做 /opsx-workflow:archive 的事。回傳收尾成功的卡。"""
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

    def unpushed(self, top, branch, head_sha=None):
        """本機分支上有只存在本機的 commit，或查不出來，回一句說明；沒有回 None。刪分支前叫它：-D 之後那些 commit 就沒了。
        排除 head_sha（MR 合併當下的分支 head）以前的 commit 與所有 remote ref 上的 commit；
        關 session 的路徑沒有 head_sha，只排除 remote ref（remote 分支被 forge 刪掉時會保守地留著分支）。"""
        args = ["git", "-C", top, "rev-list", "--count", "refs/heads/" + branch, "--not"]
        if head_sha:
            args.append(head_sha)
        rc, out, err = self.run(args + ["--remotes"])
        if rc != 0:
            return "查不出有沒有未推的 commit：%s" % err[:200]
        if not out.isdigit():
            return "rev-list --count 的輸出不是整數：%r" % out[:200]
        if int(out) != 0:
            return "有 %s 個只在本機的 commit" % out
        return None

    def archive_card(self, top, c):
        key = card_key(c)
        entry = self.dispatch_file.get(key)
        self.log("++ %s 已在 forge 合併、agent 不在，收尾" % key)
        session_key = "%s/@%s" % (c["repo"], entry["feature"]) if entry and entry.get("feature") else None
        if session_key in self.dispatch_file:
            return self.archive_member(top, c, entry, session_key)
        shared = self.session_siblings(key, top)
        # 單卡派的卡屬於 session 代管的 feature、session 還活著：依賴它的下一個主 change 要叫醒。
        # chain.children 從磁碟讀這張的條目，opsx stop 標 stopped 之前叫醒，不然它會當成人停的而不接
        owner = self.session_feature_of(top, c["slug"])
        session = self.dispatch_file.get("%s/@%s" % (c["repo"], owner)) if owner and not shared else None
        wake_session = bool(session) and chain.session_alive(session)
        stop = entry and entry.get("mode") != "stopped" and not shared
        if stop and not wake_session:
            self.act(["opsx", "stop", c["slug"], "--repo", top])
        if not self.mark_merged(top, c["slug"]):
            return False
        rc, _, err = self.act(["openspec", "archive", c["slug"], "-y"], cwd=top)
        if rc != 0:
            self.log("?? %s openspec archive 失敗：%s" % (key, err[:200]))
            return False
        if wake_session:
            self.wake(top, c, owner, session)
            if stop:
                self.act(["opsx", "stop", c["slug"], "--repo", top])
        if shared:
            # pane 與 worktree 是同 feature 的 session 共用的，它還在做 shared 這幾張：不送 opsx stop（會打到 session），
            # 只把這張的條目標 stopped，之後算「session 還有誰活著」、開新 session 撞名檢查才不會把它算進去
            self.log("-- %s 的 session %s 還在做 %s，不 stop pane、不移除 worktree，只標條目 stopped" % (key, entry["feature"], "、".join(shared)))
            entry["mode"] = "stopped"
            if self.dry:
                self.log("DRY dispatch.json %s 標 stopped" % key)
            else:
                jsonfile.update(os.path.join(self.state, "dispatch.json"), functools.partial(mark_stopped, key=key, at=self.now.isoformat(timespec="seconds")))
            return True
        # 沒記 worktree 的是早期派的卡，當時 worktree 一律開在這裡
        wt = entry["worktree"] if entry and entry.get("worktree") else os.path.join(top, ".claude", "worktrees", c["slug"])
        if entry and entry.get("branch"):
            why = self.unpushed(top, entry["branch"], c["mr"]["head_sha"])
            if why:
                self.log("?? %s 分支 %s %s，分支與 worktree 都不刪，留給人" % (key, entry["branch"], why))
                return True
        if os.path.isdir(wt):
            # 不 --force：worktree 裡有沒 commit 的東西就刪不掉，留給人
            rc, _, err = self.act(["git", "-C", top, "worktree", "remove", wt])
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

    def archive_member(self, top, c, entry, session_key):
        """有 session 條目的成員主 change。不送 opsx stop <slug>：它會把 stop 送進共用的 session。
        歸檔後把同 feature 接得上的主 change 交給 session，之後同 feature 沒有活成員就關掉 session。"""
        key, feature = card_key(c), entry["feature"]
        if not self.mark_merged(top, c["slug"]):
            return False
        rc, _, err = self.act(["openspec", "archive", c["slug"], "-y"], cwd=top)
        if rc != 0:
            self.log("?? %s openspec archive 失敗：%s" % (key, err[:200]))
            return False
        session = self.dispatch_file[session_key]
        if chain.session_alive(session):
            # chain.children 從磁碟讀這張的條目，標 stopped 之前叫醒，不然它會當成人停的而不接
            self.wake(top, c, feature, session)
        else:
            self.log("-- %s 的 session %s 不活，不叫醒下一個主 change" % (key, session_key))
        entry["mode"] = "stopped"
        if self.dry:
            self.log("DRY dispatch.json %s 標 stopped" % key)
        else:
            jsonfile.update(os.path.join(self.state, "dispatch.json"), functools.partial(mark_stopped, key=key, at=self.now.isoformat(timespec="seconds")))
        members = chain.session_members(top, c["repo"], feature, self.dispatch_file)
        if members:
            self.log("-- %s 的 session %s 還在做 %s，不關 session" % (key, session_key, "、".join(members)))
        elif session.get("mode") == "stopped":
            self.log("-- %s 是人停的，pane、worktree、分支與條目留給人" % session_key)
        else:
            self.close_session(top, c["repo"], feature)
        return True

    def wake(self, top, c, feature, session):
        """同 feature 依賴這張、依賴都合了、主殼有 tasks.md 的主 change（chain.children）：寫成員條目，直接用 herdr 送第一句。
        coordinate 在沙盒外，不寫 herdr 佇列。"""
        path = os.path.join(self.state, "dispatch.json")
        try:
            rows = chain.children(top, c["repo"], c["slug"], path, feature)
        except SystemExit as e:
            self.log("?? %s 算不出同 feature 的下一個主 change，不叫醒：%s" % (card_key(c), e))
            return
        for row in rows:
            if row[0] == "skip":
                self.log("-- %s 沒有要叫醒的主 change：%s" % (card_key(c), row[1]))
                continue
            _, slug, branch, kind = row
            child = "%s/%s" % (c["repo"], slug)
            new = chain.session_member(session, feature, slug, branch, kind, session["model"], session["mode"], self.now.isoformat(timespec="seconds"))
            if self.dry:
                self.log("DRY dispatch.json 寫 %s（via @%s）" % (child, feature))
            else:
                jsonfile.update(path, functools.partial(put_entry, key=child, entry=new))
            self.dispatch_file[child] = new
            self.woken_cards.add(child)
            rc, out, err = self.act(["herdr", "agent", "prompt", feature, "[%s] /opsx-workflow:%s %s" % (slug, self.stages[child], slug)])
            if rc != 0:
                self.log("?? %s 送不到 session %s，條目已寫，下一輪由 session 重派接手：%s" % (child, feature, (err or out)[:200]))
            else:
                self.woken += 1   # 叫醒的 session 開始做這張，同時上限要算它
                self.args_checked.add("%s/@%s" % (c["repo"], feature))

    def close_session(self, top, repo, feature):
        """同 feature 沒有活成員了：停 session、移 worktree、刪已合併成員的分支、拿掉 session 條目。哪一步失敗就停在那一步，留給人。"""
        session_key = "%s/@%s" % (repo, feature)
        self.log("-- %s 沒有活的成員了，關 session" % session_key)
        rc, _, err = self.act(["opsx", "stop", "@" + feature, "--repo", top])
        if rc != 0:
            self.log("?? %s opsx stop 失敗，worktree、分支與條目留給人：%s" % (session_key, err[:200]))
            return
        wt = self.dispatch_file[session_key]["worktree"]
        if os.path.isdir(wt):
            # 不 --force：worktree 裡有沒 commit 的東西就刪不掉，留給人
            rc, _, err = self.act(["git", "-C", top, "worktree", "remove", wt])
            if rc != 0:
                self.log("?? %s 的 worktree %s 刪不掉，分支與 session 條目留給人：%s" % (session_key, wt, err[:200]))
                return
        prs = self.workplan(top)
        for k, v in self.dispatch_file.items():
            if not k.startswith(repo + "/") or v.get("via") != "@" + feature or not v.get("branch"):
                continue
            pr = pr_of(prs, k.split("/", 1)[1])
            if pr is None or pr.get("status") != "merged":
                continue
            # 上一次關同名 session 時刪過的成員分支，條目還留著；--quiet 下退出 1 才是分支不在，其他是 git 自己出錯
            rc, _, err = self.run(["git", "-C", top, "rev-parse", "--verify", "--quiet", "refs/heads/" + v["branch"]])
            if rc == 1:
                continue
            if rc != 0:
                self.log("?? %s 查不了分支 %s，session 條目留給人：%s" % (session_key, v["branch"], err[:200]))
                return
            why = self.unpushed(top, v["branch"])
            if why:
                # session 條目要拿掉：留著它會停在 stopped，dispatch_features 當成人停的，同 feature 剩下的 PR 不再開 session
                self.log("?? %s 分支 %s %s，不刪，留給人" % (session_key, v["branch"], why))
                continue
            rc, _, err = self.act(["git", "-C", top, "branch", "-D", v["branch"]])
            if rc != 0:
                self.log("?? %s 分支 %s 刪不掉，session 條目留給人：%s" % (session_key, v["branch"], err[:200]))
                return
        if self.dry:
            self.log("DRY dispatch.json 拿掉 %s" % session_key)
            return
        jsonfile.update(os.path.join(self.state, "dispatch.json"), functools.partial(drop_entry, key=session_key))
        del self.dispatch_file[session_key]

    def mark_merged(self, top, slug):
        """workplan 裡這個 change 標 done；它的 PR 每個 change 都 done 了才標 merged，依賴它的卡這輪就派得出去。
        不在 workplan 裡的卡沒東西要標。"""
        path = os.path.join(top, "openspec", "workplan.yaml")
        pr = pr_of(self.workplan(top), slug)
        if pr is None:
            self.log("-- %s 不在 %s，沒有 PR 要標 merged" % (slug, path))
            return True
        names = [x.get("name") for x in pr.get("changes") or []]
        if slug not in names:
            # 主 change 合併：PR 標 merged，還沒 done 的子 change 一起標 done
            pending, archived = [], []
            marks = [("changes", x.get("name"), "done") for x in pr.get("changes") or [] if x.get("status") != "done"] + [("prs", pr["name"], "merged")]
        else:
            # drop 與手動 openspec archive 只搬目錄、不改 workplan；只是目錄不在的可能還沒 propose，不算
            unfinished = [x.get("name") for x in pr.get("changes") or [] if x.get("name") != slug and x.get("status") != "done"]
            archived = [n for n in unfinished if chain.is_archived(top, n)]
            pending = [n for n in unfinished if n not in archived]
            marks = [("changes", n, "done") for n in [slug] + archived] + ([] if pending else [("prs", pr["name"], "merged")])
        if self.dry:
            self.log("DRY workplan %s 標 %s" % (path, "、".join("%s %s" % (n, v) for _, n, v in marks)))
            return True
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        for key, name, value in marks:
            i = status_line(lines, key, name)
            if i is None:
                self.log("?? %s 找不到 %s 的 status 行，不收尾" % (path, name))
                return False
            lines[i] = re.sub(r"status:.*$", "status: " + value, lines[i])
        safefile.write_atomic(path, "\n".join(lines))
        self.plans.pop(top, None)
        if archived:
            self.log("ok   workplan 的 change %s 已歸檔、沒更新，跟著標 done" % "、".join(archived))
        if pending:
            self.log("ok   workplan 的 change %s 標 done；PR %s 還有 %s 沒 done，不標 merged" % (slug, pr["name"], "、".join(pending)))
        else:
            self.log("ok   workplan 的 change %s 標 done、PR %s 標 merged" % (slug, pr["name"]))
        return True

    def notify(self, c, kind, ident, event, body, scope=None):
        """這裡處理不了、要人去處理的事。每輪從狀態重算，送過的鍵記在 _notified，所以事件觸發那輪漏掉的由定時那輪補，也不會重送。
        scope 是去重鍵的前綴，預設是這張卡；feature session 的事屬於整個 session，傳 <repo>/@<feature>。
        先送協調者 session（herdr agent prompt）；它不在或卡住（COORDINATOR_UNAVAILABLE）才發桌面通知。
        herdr 的通知沒有點擊動作，內文要寫去哪裡處理。"""
        self.send_notification("%s/%s/%s" % (scope or card_key(c), kind, ident), "[%s] %s" % (card_key(c), event), body)

    def send_notification(self, key, title, body):
        if key in self.memo["_notified"]:
            return
        rc, out, err = self.act(["herdr", "agent", "prompt", COORDINATOR, "%s：%s" % (title, body)])
        if rc != 0 and any(code in out + err for code in COORDINATOR_UNAVAILABLE):
            rc, out, err = self.act(["herdr", "notification", "show", title, "--body", body, "--sound", "request"])
        if rc != 0:
            self.log("?? 通知 %s 送不出去，下一輪再送：%s" % (key, (err or out).replace("\n", " ")[:200]))
            return
        self.memo["_notified"][key] = self.now.isoformat(timespec="seconds")
        # 送出就存：這輪後面的步驟出錯時，下一輪不會把同一則再送一次
        self.save()

    def forget_waiting(self, c, live):
        """卡沒在等人了：清掉它 gate 與 blocked 的通知紀錄，同一個 pane 之後再卡、或 gate id 被重用時才會再通知。
        session 的 blocked 鍵是整個 session 的：同 session 還有卡在等那個 pane 就留著，不然下一張還卡著的卡會再送一次。"""
        prefixes = tuple("%s/%s/" % (card_key(c), kind) for kind in ("gate", "blocked"))
        for key in [k for k in self.memo["_notified"] if k.startswith(prefixes)]:
            del self.memo["_notified"][key]
        scope = session_scope(c)
        if scope:
            still = {"%s/blocked/%s" % (scope, o["dispatch"].get("pane")) for o in live
                     if session_scope(o) == scope and o["waiting"] and o["waiting"]["type"] == "終端機等待輸入"}
            for key in [k for k in self.memo["_notified"] if k.startswith(scope + "/blocked/") and k not in still]:
                del self.memo["_notified"][key]

    def notify_sub_gates(self, sessions):
        """session 裡子 change 的 open gate。子 change 由主 change 的 session 轉給 subagent，協調者不答；
        記 ?? 並通知，人才看得到（卡本身的 waiting 只帶主 change 的 gate）。"""
        for s in sessions:
            for m in s.get("mains") or []:
                for sub in m.get("subs") or []:
                    w = sub.get("waiting")
                    if not w:
                        continue
                    c = {"repo": s["repo"], "slug": "%s/%s" % (m["slug"], sub["slug"])}
                    self.log("?? %s 子 change 的 gate %s 要人看：%s" % (card_key(c), w["gate_id"], one_line(w.get("question") or "")[:100]))
                    self.notify_gate(c, w, "要人看（子 change）")

    def notify_gate(self, c, w, why):
        self.notify(c, "gate", w["gate_id"], "gate %s %s" % (w["gate_id"], why), "看板：" + one_line(w.get("question") or ""))

    def usage_limit_seen(self, live):
        """派出去、沒在 working 也不是 unknown 的 agent，畫面最後 10 行有沒有用量上限訊息。
        working 的不讀：它在跑，代表已經續上。回 (顯示訊息的 pane 清單, 最晚的重置時刻或 None)。"""
        hits, times, panes = [], [], set()
        for c in live:
            if not c["dispatch"] or c["agent_status"] in ("working", "unknown"):
                continue
            pane = c["dispatch"].get("pane")
            if not pane or pane in panes:
                continue
            panes.add(pane)
            rc, out, err = self.run(["herdr", "agent", "read", pane, "--lines", "10", "--format", "text"])
            if rc != 0:
                self.log("?? %s 的畫面讀不到，用量上限看不了：%s" % (card_key(c), err[:200]))
                continue
            hit, resets_at = parse_usage_limit(out, self.now)
            if hit:
                hits.append(pane)
                if resets_at:
                    times.append(resets_at)
        return hits, max(times) if times else None

    def usage_limit_paused(self, live):
        """用量上限到了就暫停：不派、不重派、不處理 gate。暫停到記下的重置時刻過了、而且沒有 agent 畫面還顯示訊息。
        重置時刻只在進入暫停時記一次：訊息還在時每輪重算會一直往後推（時刻過了還顯示，算出來是明天）。"""
        panes, resets_at = self.usage_limit_seen(live)
        held = self.memo.get("_usage_limit")
        if panes and not held:
            self.memo["_usage_limit"] = held = {"seen_at": self.now.isoformat(timespec="seconds"),
                                                "resets_at": resets_at.isoformat(timespec="seconds") if resets_at else None}
            if resets_at:
                self.log("!! 用量上限到了，預計 %s 恢復，暫停派卡與重派" % resets_at.strftime("%m-%d %H:%M"))
                body = "預計 %s 恢復；Claude Code 到時間會自己續跑" % resets_at.strftime("%m-%d %H:%M")
            else:
                self.log("?? 看得到用量上限訊息但讀不出重置時刻，不猜：暫停到畫面不再出現")
                body = "讀不出重置時刻，畫面不再顯示上限訊息才恢復派卡"
            self.send_notification("usage-limit/paused/" + held["seen_at"], "[usage-limit] 用量上限，暫停派卡", body)
        if panes:
            # 過了重置時刻還有 pane 顯示訊息（停在等人的 gate、parked、按過 esc 的 pane）：沒人會替它續跑，要人看
            stale_from = datetime.datetime.fromisoformat(held["resets_at"] or held["seen_at"])
            if self.now > stale_from + datetime.timedelta(minutes=USAGE_LIMIT_STALE_MINUTES):
                self.log("?? 重置時刻已過 %d 分鐘（讀不出時刻就從進入暫停起算），pane %s 還顯示上限訊息，繼續暫停" % (USAGE_LIMIT_STALE_MINUTES, "、".join(panes)))
                self.send_notification("usage-limit/stale/" + held["seen_at"], "[usage-limit] 重置時刻過了仍暫停",
                                       "pane %s 還顯示上限訊息；看過它再回板上" % "、".join(panes))
            return True
        if held and held["resets_at"] and self.now < datetime.datetime.fromisoformat(held["resets_at"]):
            return True
        if held:
            self.log("ok   用量已重置，恢復派卡與重派")
            self.send_notification("usage-limit/resumed/" + held["seen_at"], "[usage-limit] 用量已重置", "恢復派卡與重派")
            del self.memo["_usage_limit"]
        return False

    def handle_gate(self, c, top):
        """派出去的卡的第一個 open gate：照 gaterule.decide 的處置停 pane 或通知人。gate 一律由人答，這裡不答。"""
        w, key = c["waiting"], card_key(c)
        verdict = gaterule.decide(w)
        q = w.get("question") or ""
        if verdict[0] == "park" and chain.merged_into_main(top, self.workplan(top), verdict[1]):
            self.log("?? %s gate %s 等的 %s 已合進 main，不停 pane，要你回 gate：%s" % (key, w["gate_id"], verdict[1], q[:100]))
            self.notify_gate(c, w, "等的 %s 已合進 main，要你回" % verdict[1])
            return
        if verdict[0] == "park":
            self.log("⏳ %s gate %s 等 %s，先停 pane，有卡合進 main 那輪再派：%s" % (key, w["gate_id"], verdict[1], q[:100]))
            rc, _, _ = self.act(["opsx", "stop", c["slug"], "--repo", top])
            if rc == 0:
                self.memo["_parked"][key] = {"at": self.now.isoformat(timespec="seconds"), "gate": w["gate_id"],
                                             "merged": merged_prs(self.workplan(top)), "waits_on": verdict[1]}
            return
        if verdict[1] == "terminal":
            pane = c["dispatch"].get("pane")
            self.log("?? %s 在 pane %s 等終端機輸入（autopilot 不該問 pane），要人看" % (key, pane))
            self.notify(c, "blocked", pane, "在終端機等輸入", "pane %s：%s" % (pane, one_line(q)),
                        scope=session_scope(c))
            return
        pick = w.get("recommended") or (w.get("options") or [None])[0] or ""
        line, why = GATE_HUMAN[verdict[1]]
        self.log(line % {"key": key, "gate": w["gate_id"], "q100": q[:100], "q120": q[:120], "pick60": pick[:60],
                         "rec100": (w.get("recommended") or "")[:100]})
        self.notify_gate(c, w, why)

    def session_siblings(self, key, top):
        """同 feature 還活著的其他卡的 key（chain.session_siblings）。"""
        repo, slug = key.split("/", 1)
        return ["%s/%s" % (repo, s) for s in chain.session_siblings(top, repo, slug, self.dispatch_file)]

    def redispatch_feature(self, c, top, why):
        """session 的 pane 不在了：只停 session 條目 <repo>/@<feature>，再整個 feature 重派一次。memo 以同一個 key 記。
        成員條目不動：還是 stopped 的就是人停的，dispatch --feature 會跳過它。"""
        feature = c["dispatch"]["feature"]
        key = "%s/@%s" % (c["repo"], feature)
        last = self.memo["_redispatched"].get(key)
        if last and self.now - datetime.datetime.fromisoformat(last) < datetime.timedelta(minutes=REDISPATCH_MINUTES):
            self.log("-- %s %s，%d 分鐘內重派過，這輪不再派" % (key, why, REDISPATCH_MINUTES))
            # 這一輪剛重派過（同 feature 的第二張卡走到這裡）不算又掛了
            if key not in self.redispatched_now:
                self.notify(c, "dead", last, "重派後 %d 分鐘內又掛了" % REDISPATCH_MINUTES,
                            "pane %s：%s；看板上重派或停掉" % (c["dispatch"].get("pane"), why), scope=key)
            return
        if "agent" not in c["dispatch"]:
            self.log("?? %s %s，但 dispatch.json 沒記 agent，不知道派給誰" % (key, why))
            return
        try:
            plan = chain.feature_plan(top, feature)
        except SystemExit as e:
            self.log("?? %s 算不出能交給 session 的卡，不重派：%s" % (key, e))
            return
        only = self.feature_members(c["repo"], feature, plan)[1]
        if not only:
            self.log("-- %s 現在沒有能交給 session 的卡（單卡派過或人停的不算），不重派" % key)
            return
        self.log("!! %s %s，停 session 後整個 feature 重派" % (key, why))
        self.act(["opsx", "stop", "@" + feature, "--repo", top])
        rc, _, err = self.act(["opsx", "dispatch", "--feature", feature, "--only", ",".join(only), "--agent", c["dispatch"]["agent"], "--mode", "autopilot", "--repo", top])
        if rc != 0:
            self.log("?? %s 重派開不了 session：%s" % (key, err[:200]))
            return
        self.memo["_redispatched"][key] = self.now.isoformat(timespec="seconds")
        self.redispatched_now.add(key)
        self.args_checked.add(key)

    def pane_chain(self, c):
        """從卡自己的條目沿 via 往上到代管 pane 的根條目，加上 session 條目；最後一筆是根。
        fan-out 子卡 via 父卡、成員卡 via @<feature>，pane 與它的 settings 檔、relaunch 標記都屬於根。"""
        keys, k = [], card_key(c)
        while k in self.dispatch_file and k not in keys:
            keys.append(k)
            via = self.dispatch_file[k].get("via")
            if not via:
                break
            k = "%s/%s" % (c["repo"], via)
        scope = session_scope(c)
        if scope and scope not in keys:
            keys.append(scope)
        return keys or [card_key(c)]

    def relaunching(self, c):
        """opsx relaunch 正在重開這張卡的 pane：回 (條目 key, relaunching_at)，否則 None。
        過了 RELAUNCH_MINUTES 的是被 kill 的 relaunch 留下的，不算。"""
        for k in self.pane_chain(c):
            entry = self.dispatch_file.get(k) or {}
            at = parse_relaunching_at(k, entry, self.now)
            if at and self.now - at < datetime.timedelta(minutes=RELAUNCH_MINUTES):
                return k, entry["relaunching_at"]
        return None

    def bad_dispatch(self, c, e):
        """卡的 dispatch.json 欄位格式不合：這輪不對它做死了沒、在不在 relaunch、重派的判斷，記 ?? 並通知。
        同一張卡、欄位、原值只通知一次；沒有人修之前每輪都會記 ??。"""
        self.log("?? %s %s，這輪不處理這張卡" % (card_key(c), e))
        self.notify(c, "bad-dispatch", "%s/%s=%s" % (e.key, e.field, json.dumps(e.value, ensure_ascii=False)), "dispatch.json 欄位不合", one_line(str(e)))

    def redispatch(self, c, top, why):
        # relaunch 的空窗裡 claude 已經 /exit，看起來就是 agent 不在；這時收掉 pane 會打斷 relaunch
        busy = self.relaunching(c)
        if busy:
            self.log("-- %s %s，但 %s 從 %s 起在 relaunch，不重派" % (card_key(c), why, busy[0], busy[1]))
            return
        if c["dispatch"].get("feature"):
            self.redispatch_feature(c, top, why)
            return
        key = card_key(c)
        last = self.memo["_redispatched"].get(key)
        if last and self.now - datetime.datetime.fromisoformat(last) < datetime.timedelta(minutes=REDISPATCH_MINUTES):
            self.log("-- %s %s，%d 分鐘內重派過，這輪不再派" % (key, why, REDISPATCH_MINUTES))
            if key not in self.redispatched_now:
                self.notify(c, "dead", last, "重派後 %d 分鐘內又掛了" % REDISPATCH_MINUTES,
                            "pane %s：%s；看板上重派或停掉" % (c["dispatch"].get("pane"), why))
            return
        if "agent" not in c["dispatch"]:
            self.log("?? %s %s，但 dispatch.json 沒記 agent，不知道派給誰" % (key, why))
            return
        self.log("!! %s %s，stop 後重派" % (key, why))
        self.act(["opsx", "stop", c["slug"], "--repo", top])
        rc, _, err = self.act(["opsx", "dispatch", c["slug"], "--agent", c["dispatch"]["agent"], "--mode", "autopilot", "--kind", c["kind"], "--repo", top])
        if rc != 0:
            self.log("?? %s 重派開不了：%s" % (key, one_line(err)[:200]))
            self.notify(c, "dead", "dispatch-failed", "重派開不了",
                        "pane %s：%s；opsx dispatch 失敗：%s；看板上重派或停掉" % (c["dispatch"].get("pane"), why, one_line(err)[:150]))
            return
        self.memo["_redispatched"][key] = self.now.isoformat(timespec="seconds")
        self.redispatched_now.add(key)
        self.args_checked.add(self.pane_chain(c)[-1])

    def check_args(self, c, top):
        """pane 裡的 claude 丟了 dispatch 給的 --settings（herdr 還原 pane、手動 resume）就 opsx relaunch。
        只看 autopilot 或 drive 的 claude、idle 或 blocked、settings 檔在的卡；session 成員共用 pane，一輪只看一次。
        讀不到、判不了、relaunch 失敗都記 ?? 並通知，不改走 stop 加重派：那會開新 session、丟掉原本的 context。"""
        d = c["dispatch"]
        if d.get("mode") not in ("autopilot", "drive") or d.get("agent") != "claude" or c["agent_status"] not in ("idle", "blocked"):
            return
        # 這輪叫醒、重派過的 pane 已記在 args_checked：collect 的 agent_status 是動手前讀的，已經過時
        key = self.pane_chain(c)[-1]
        if key in self.args_checked:
            return
        self.args_checked.add(key)
        if self.relaunching(c):
            return
        # launch_args 用根條目的 herdr 名（單卡是 slug，session 是 feature 名）與 mode 命名 settings 檔；fan-out 會把父卡的 drive 轉成子卡的 autopilot。
        # 根條目不在 dispatch.json 時（session 條目已被拿掉），用卡自己的條目
        name = key.split("/", 1)[1].lstrip("@")
        mode = (self.dispatch_file.get(key) or d)["mode"]
        settings = os.path.join(self.state, "settings", "%s-%s-%s.json" % (c["repo"], name, mode))
        if not os.path.isfile(settings):
            return
        last = self.memo["_relaunched"].get(key)
        if last and not last["ok"] and self.now - datetime.datetime.fromisoformat(last["at"]) < datetime.timedelta(minutes=RELAUNCH_MINUTES):
            self.log("-- %s relaunch %s 失敗過，%d 分鐘內不再試" % (key, last["at"], RELAUNCH_MINUTES))
            return
        pane = d["pane"]
        rc, out, err = self.run(["herdr", "pane", "process-info", "--pane", pane])
        if rc != 0:
            self.args_unknown(c, key, pane, "unknown", "herdr pane process-info 失敗（rc %d）：%s" % (rc, (err or out).replace("\n", " ")[:200]))
            return
        try:
            lost = args_lost(claude_argv(json.loads(out)), settings)
        except (CoordinateError, ValueError) as e:
            self.args_unknown(c, key, pane, "unknown", str(e))
            return
        if not lost:
            for k in [k for k in self.memo["_notified"] if k.startswith(key + "/args/")]:
                del self.memo["_notified"][k]
            if last and last["ok"]:
                del self.memo["_relaunched"][key]
            return
        if last and last["ok"]:
            # 上一次 relaunch 回 0 卻沒把參數帶回來：再 relaunch 只會一再對 pane 送 Esc、/exit，等人看過、參數判讀正常一次才再試
            self.args_unknown(c, key, pane, "unfixed", "relaunch 後仍沒帶 --settings %s（上次 relaunch %s）" % (settings, last["at"]))
            return
        self.log("!! %s pane %s 的 claude 沒帶 --settings %s，relaunch" % (key, pane, settings))
        rc, out, err = self.act(["opsx", "relaunch", c["slug"], "--repo", top])
        at = self.now.isoformat(timespec="seconds")
        self.memo["_relaunched"][key] = {"at": at, "ok": rc == 0}
        if rc != 0:
            self.log("?? %s opsx relaunch 失敗，%d 分鐘內不再試：%s" % (key, RELAUNCH_MINUTES, (err or out).replace("\n", " ")[:200]))
            self.notify(c, "relaunch", at, "relaunch 失敗", "pane %s 留著沒關，到 pane 看；%d 分鐘後 coordinator 再試" % (pane, RELAUNCH_MINUTES),
                        scope=key)

    def args_unknown(self, c, key, pane, reason, why):
        """reason 是 unknown（判不了）或 unfixed（relaunch 沒修好），兩件事各通知一次。"""
        self.log("?? %s pane %s 的啟動參數判不了，不 relaunch：%s" % (key, pane, why))
        self.notify(c, "args", "%s/%s" % (pane, reason), "啟動參數判不了", "pane %s：%s" % (pane, one_line(why)), scope=key)

    def settle_parked(self, cards):
        """人手動重派了的 parked 卡不再由這裡管。人在板上把那個 gate 答掉了，記成已答，
        dispatch_new 照派卡規則重派：卡是 coordinator 停的，不重派就沒有 agent 讀得到答案。"""
        for c in cards:
            key = card_key(c)
            parked = self.memo["_parked"].get(key)
            if not parked:
                continue
            if c["dispatch"]:
                self.log("-- %s 已經又派出去，不再 parked" % key)
                del self.memo["_parked"][key]
            elif not parked.get("answered") and parked["gate"] not in [g["id"] for g in c["open_gates"]]:
                self.log("-- %s 等的 gate %s 被人答掉，記成已答，照派卡規則重派" % (key, parked["gate"]))
                parked["answered"] = True

    def working(self, cards):
        """這輪開始前在跑的卡，加上這輪叫醒的。"""
        return self.woken + sum(1 for c in cards if c["dispatch"] and c["agent_status"] == "working")

    def woken_by(self, key, parked, top):
        """喚醒 parked 的卡的 PR。gate 寫了 waits-on 就只認那張（卡名或 PR 名）是不是 merged，停下之前或之後合的都算；
        舊的 parked 記錄沒有 waits_on、或 waits-on 對不到 workplan 裡任何 PR 時，照停下之後任何新合併的 PR 都喚醒。"""
        prs = self.workplan(top)
        merged = merged_prs(prs)
        newly = [p for p in merged if p not in parked["merged"]]
        waits_on = parked.get("waits_on")
        if not waits_on:
            return newly
        pr = pr_of(prs, waits_on)
        if pr is None:
            if newly:
                self.log("?? %s 的 gate 等 %s，workplan 沒有這張卡或 PR，照任何新合併的 PR 喚醒" % (key, waits_on))
            return newly
        return [pr["name"]] if pr["name"] in merged else []

    def dispatch_new(self, cards, repo_paths):
        n = 0
        working = self.working(cards)
        ranked = sorted((self.rank(c, repo_paths[c["repo"]]), i, c) for i, c in enumerate(cards))
        for _, _, c in ranked:
            key, top = card_key(c), repo_paths[c["repo"]]
            entry = self.dispatch_file.get(key)
            parked = self.memo["_parked"].get(key)
            if parked:
                # gate 由人答。還沒答：等的 PR 合了（不管是卡自己 /archive 標的，還是這裡收尾時標的）就通知人，不派。
                # 人答了（settle_parked 記成已答，或上一輪派失敗）就往下照派卡規則重派
                if c["section"] not in ("待指派", "待處理"):
                    continue
                if not parked.get("answered"):
                    newly = self.woken_by(key, parked, top)
                    if newly:
                        self.log("?? %s 停下之後合進 main 的 PR：%s，等你回 gate %s 才重派" % (key, "、".join(newly), parked["gate"]))
                        self.notify(c, "gate", parked["gate"], "gate %s 等的 PR 合了，要你回" % parked["gate"],
                                    "看板：停下之後合進 main 的 PR：%s；回了這個 gate 才重派" % "、".join(newly))
                    continue
            elif c["section"] != "待指派":
                continue
            elif key in self.woken_cards:
                continue   # 這輪收尾時已交給 session；collect 是收尾前讀的，還當它待指派
            elif entry and entry.get("mode") == "stopped":
                continue   # 人在板上停掉的
            if not os.path.isfile(os.path.join(c["path"], "tasks.md")) or c["mr"]:
                continue
            # parked 的卡是這裡自己停下的，重派是接回原本那個 pane 的工作；交給 session 的話，它的 worktree 會擋住 session
            owner = None if parked else self.session_feature_of(top, c["slug"])
            if owner:
                self.log("-- %s 屬於 feature %s，由那個 session 做，不單獨派" % (key, owner))
                continue
            missing = deps_unmerged(c["slug"], self.workplan(top), read_features(os.path.join(top, "openspec", "workplan.yaml")))
            if missing:
                self.log("⏳ %s 等 %s merged 才派" % (key, "、".join(missing)))
                continue
            if not AGENT_NAME.match(c["slug"]):
                self.log("-- %s 不是合法的 agent 名，跳過" % key)
                continue
            # 排在等級與額度之前：已經有 pane 在做的卡不該吃掉這輪的額度
            holder = self.branch_holder(top, c["slug"])
            if holder:
                live = self.live_entry(holder)
                if live:
                    self.log("-- %s 的分支已經 checkout 在 %s，%s（pane %s）在做，不派" % (key, holder, live[0], live[1].get("pane")))
                else:
                    self.notify(c, "held", holder, "分支被 %s 佔著，沒有活的 pane" % holder, "收掉那棵 worktree，或手動派進去")
                    self.log("-- %s 的分支已經 checkout 在 %s，那棵 worktree 沒有活的 pane，不派，等人處理" % (key, holder))
                continue
            got = self.level(top, c["slug"])
            if "error" in got:
                self.log("?? %s 等級算不出來：%s" % (key, got["error"]))
                continue
            # parked 的卡是這裡自己停下的，重派是接回原本的工作，不算自動派新卡
            if got["level"] == "P2" and not parked:
                self.log("-- %s 是 P2（%s），不自動派" % (key, got["reason"]))
                continue
            # P0（自己判出或繼承來的）排最前、一起派，不佔每輪上限；在跑的卡一律不停
            p0 = got["level"] == "P0"
            if not p0 and n >= MAX_DISPATCH:
                self.log("-- 這輪派滿 %d 張，%s 下輪" % (MAX_DISPATCH, key))
                continue
            if not p0 and working + n >= self.max_working:
                self.log("-- 同時在跑 %d 張，達上限 %d，%s 下輪" % (working + n, self.max_working, key))
                continue
            agent = entry["agent"] if entry and "agent" in entry else "claude"
            rc, _, err = self.act(["opsx", "dispatch", c["slug"], "--agent", agent, "--mode", "autopilot", "--kind", c["kind"], "--repo", top])
            if not p0:
                n += 1
            if rc != 0:
                self.log("?? %s 派不出去：%s" % (key, err[:200]))
                continue
            self.memo["_parked"].pop(key, None)
        return n

    def branch_holder(self, top, slug):
        """workplan 裡這張卡的 PR 分支被別的 worktree checkout 時，回那棵 worktree 的路徑。
        卡自己的 .claude/worktrees/<slug> 不算；不在 workplan 或 PR 沒寫 branch 不查（分支名要 dispatch.sh 才推得出來，它自己會擋）。"""
        pr = pr_of(self.workplan(top), slug)
        if pr is None or not pr.get("branch"):
            return None
        if top not in self.worktrees:
            rc, out, err = self.run(["git", "-C", top, "worktree", "list", "--porcelain"])
            if rc != 0:
                # 這輪不擋；真的被佔時 dispatch.sh 開 worktree 前的檢查會擋下
                self.log("?? %s 的 git worktree list 失敗，這輪不查分支被誰佔：%s" % (top, err[:200]))
            self.worktrees[top] = worktree_branches(out) if rc == 0 else {}
        wt = self.worktrees[top].get(pr["branch"])
        if wt is None or os.path.realpath(wt) == os.path.realpath(os.path.join(top, ".claude", "worktrees", slug)):
            return None
        return wt

    def live_entry(self, wt):
        """dispatch.json 裡 worktree 指向 wt、pane 還活著的條目 (key, entry)；沒有就是 None。路徑兩邊都 realpath。"""
        real = os.path.realpath(wt)
        for k, v in self.dispatch_file.items():
            if v.get("worktree") and os.path.realpath(v["worktree"]) == real and chain.session_alive(v):
                return k, v
        return None

    def session_feature_of(self, top, slug):
        pr = pr_of(self.workplan(top), slug)
        for f in session_features(read_features(os.path.join(top, "openspec", "workplan.yaml"))):
            if pr is not None and any(p.get("name") == pr.get("name") for p in f.get("prs") or []):
                return f.get("name")
        return None

    def dispatch_features(self, repo_paths, n, working):
        """feature 的 depends-on 都合了、還有沒合的 PR、session 條目不存在或不活：開一個 session（opsx dispatch --feature）。
        條目是 stopped 的不開：coordinate 自己關 session 時會拿掉條目，留下的 stopped 只會是人停的。
        n 是這輪單卡派掉的張數，working 是這輪開始前在跑的卡；兩個上限跟單卡派一樣算。"""
        for repo, top in sorted(repo_paths.items()):
            prs = self.workplan(top)
            status = {p.get("name"): p.get("status") for p in prs}
            features = read_features(os.path.join(top, "openspec", "workplan.yaml"))
            for f in features:
                if not chain.session_managed(f) and (len(f.get("prs") or []) >= 2 or f.get("depends-on")):
                    self.log("?? %s 的 feature %s 不是合法的 agent 名，開不了 session，它的卡照單卡派" % (repo, f.get("name")))
            for f in session_features(features):
                name = f.get("name")
                if all(p.get("status") == "merged" for p in f.get("prs") or []):
                    continue
                missing = [d for d in f.get("depends-on") or [] if status.get(d) != "merged"]
                if missing:
                    self.log("⏳ %s 的 feature %s 等 %s merged 才開 session" % (repo, name, "、".join(missing)))
                    continue
                key = "%s/@%s" % (repo, name)
                session = self.dispatch_file.get(key)
                if session and session.get("mode") == "stopped":
                    self.log("-- %s 是人停的，不重開 session" % key)
                    continue
                if session and chain.session_alive(session):
                    continue
                last = self.memo["_redispatched"].get(key)
                if last and self.now - datetime.datetime.fromisoformat(last) < datetime.timedelta(minutes=REDISPATCH_MINUTES):
                    continue   # redispatch_feature 剛派過（這輪或十分鐘內）
                if not AGENT_NAME.match(name):
                    self.log("-- %s 的 feature %s 不是合法的 agent 名，跳過" % (repo, name))
                    continue
                try:
                    plan = chain.feature_plan(top, name)
                except SystemExit as e:
                    self.log("-- %s 的 feature %s 不開 session：%s" % (repo, name, e))
                    continue
                # 單卡派過的卡（上線前派的、人手動派的）只要 worktree 還在就佔著它的分支，dispatch --feature 會在 worktree add 撞上
                single, slugs = self.feature_members(repo, name, plan)
                live = [s for s in single if self.dispatch_file["%s/%s" % (repo, s)].get("mode") != "stopped"]
                if live:
                    self.log("-- %s 的 feature %s 不開 session：%s 已經單卡派著" % (repo, name, "、".join(live)))
                    continue
                # 停了的單卡不會自己合併，擋整個 feature 就永遠不開；只把它從 --only 拿掉，它的分支留給它自己
                if single:
                    self.log("-- %s 的 feature %s 不交 %s：單卡派過、停了但 worktree 還在" % (repo, name, "、".join(single)))
                levels = [(s, self.level(top, s)) for s in slugs]
                held = ["%s %s" % (s, got["error"] if "error" in got else got["reason"]) for s, got in levels if "error" in got or got["level"] == "P2"]
                ready = [(priority.LEVELS.index(got["level"]), i, s) for i, (s, got) in enumerate(levels) if "error" not in got and got["level"] != "P2"]
                if not ready:
                    self.log("-- %s 的 feature %s 能開工的卡都是 P2、等級算不出來或人停的，不自動開 session：%s" % (repo, name, "；".join(held) or "全部人停"))
                    continue
                # 照等級排、同等級保留 workplan 順序：第一句給排第一的，P0 不會排在 P1 後面
                ranked = sorted(ready)
                only = [s for _, _, s in ranked]
                p0 = ranked[0][0] == priority.LEVELS.index("P0")
                if not p0 and n >= MAX_DISPATCH:
                    self.log("-- 這輪派滿 %d 個，feature %s 下輪" % (MAX_DISPATCH, name))
                    continue
                if not p0 and working + n >= self.max_working:
                    self.log("-- 同時在跑 %d 張，達上限 %d，feature %s 下輪" % (working + n, self.max_working, name))
                    continue
                rc, _, err = self.act(["opsx", "dispatch", "--feature", name, "--only", ",".join(only), "--agent", "claude", "--mode", "autopilot", "--repo", top])
                if rc != 0:
                    self.log("?? %s 的 feature %s 開不了 session：%s" % (repo, name, err[:200]))
                    continue
                if not p0:
                    n += 1

    def feature_members(self, repo, name, plan):
        """feature_plan 的卡分成 (單卡派過的卡, 交給 session 的卡)。人停的成員 dispatch --feature 會跳過，也不在後者。"""
        single = [p[0] for p in plan if self.holds_branch(repo, p[0], name)]
        slugs = [p[0] for p in plan if p[0] not in single and not chain.human_stopped(self.dispatch_file.get("%s/%s" % (repo, p[0])), name)]
        return single, slugs

    def holds_branch(self, repo, slug, feature):
        """<slug> 有條目、不是這個 feature 的 session 成員，而且沒停、或停了但 worktree 還在（opsx stop 不收 worktree）。"""
        entry = self.dispatch_file.get("%s/%s" % (repo, slug))
        if not entry or entry.get("via") == "@" + feature:
            return False
        return entry.get("mode") != "stopped" or ("worktree" in entry and os.path.isdir(entry["worktree"]))


def read_max_working(path):
    """同時 working 的卡數上限。launchd 與 --kick 都讀這個檔；沒有檔是預設值，內容不合法就拒跑。"""
    if not os.path.exists(path):
        return DEFAULT_MAX_WORKING
    with open(path, encoding="utf-8") as f:
        raw = f.read().strip()
    if not re.fullmatch(r"[0-9]+", raw) or int(raw) < 1:
        raise CoordinateError("%s 要是正整數，拿到 %r" % (path, raw))
    return int(raw)


def parse_usage_limit(text, now):
    """畫面文字裡有沒有用量上限訊息，以及它說的重置時刻：(有沒有, 時刻或 None)。
    訊息只寫時刻（7pm），沒有日期：取 now 之後的下一個該時刻。多個時刻取最晚的。"""
    if not any(USAGE_LIMIT_LINE.match(line) and USAGE_LIMIT_WARNING not in line for line in text.splitlines()):
        return False, None
    times = []
    for hour, minute, ampm in USAGE_LIMIT_RESET.findall(text):
        if not 1 <= int(hour) <= 12 or int(minute or 0) > 59:
            continue
        at = now.replace(hour=int(hour) % 12 + (12 if ampm.lower() == "pm" else 0), minute=int(minute or 0), second=0, microsecond=0)
        times.append(at if at > now else at + datetime.timedelta(days=1))
    return True, max(times) if times else None


def mark_stopped(d, key, at):
    """jsonfile.update 的 mutate：條目標 stopped，不碰 pane。"""
    d[key]["mode"] = "stopped"
    d[key]["stopped_at"] = at


def put_entry(d, key, entry):
    """jsonfile.update 的 mutate：寫一筆條目。"""
    d[key] = entry


def drop_entry(d, key):
    """jsonfile.update 的 mutate：拿掉一筆條目。"""
    del d[key]


def card_key(c):
    return "%s/%s" % (c["repo"], c["slug"])


def session_scope(c):
    """卡屬於 feature session 時的通知鍵前綴 <repo>/@<feature>，否則 None。session 內的卡共用 pane，一件事不分卡。"""
    if c["dispatch"] and c["dispatch"].get("feature"):
        return "%s/@%s" % (c["repo"], c["dispatch"]["feature"])
    return None


def one_line(text):
    return text.split("\n", 1)[0][:100]


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


def check_dispatch_entries(entries):
    """dispatch.json 是 {<repo>/<slug>: 條目物件}；別的形狀讓後面每個 .get() 都丟 AttributeError，所以載入時就點名 key 與型別。"""
    if not isinstance(entries, dict):
        raise CoordinateError("dispatch.json 要是 JSON 物件，拿到 %s" % type(entries).__name__)
    for key, entry in entries.items():
        if not isinstance(entry, dict):
            raise CoordinateError("dispatch.json 的條目 %s 要是 JSON 物件，拿到 %s：%s" % (key, type(entry).__name__, json.dumps(entry, ensure_ascii=False)[:100]))


def read_features(path):
    """workplan.yaml 的 features，用 chain.py 同一個 parser。沒有檔就是沒有 feature。"""
    if not os.path.exists(path):
        return []
    return chain.load_workplan(path).get("features") or []


def read_prs(path):
    """workplan.yaml 所有 feature 底下的 PR。沒有檔就是沒有 PR、沒有依賴。"""
    return [pr for f in read_features(path) for pr in f.get("prs") or []]


def plan_order(path):
    """change 名到 (所屬 feature 的 milestone 在 milestones 的位置, 在 workplan 出現的位置)。feature 沒寫 milestone 排在有寫的後面。"""
    if not os.path.exists(path):
        return {}
    wp = chain.load_workplan(path)
    names = [m.get("name") for m in wp.get("milestones") or []]
    out = {}
    for f in wp.get("features") or []:
        ms = names.index(f.get("milestone")) if f.get("milestone") in names else len(names)
        for pr in f.get("prs") or []:
            for c in pr.get("changes") or []:
                out.setdefault(c.get("name"), (ms, len(out)))
    return out


def worktree_branches(porcelain):
    """git worktree list --porcelain 的輸出轉成 {分支名: worktree 路徑}；detached 的 worktree 沒有分支，不列。"""
    out, wt = {}, None
    for line in porcelain.splitlines():
        if line.startswith("worktree "):
            wt = line[len("worktree "):]
        elif line.startswith("branch refs/heads/"):
            out[line[len("branch refs/heads/"):]] = wt
    return out


def merged_prs(prs):
    return [p.get("name") for p in prs if p.get("status") == "merged"]


def pr_of(prs, slug):
    """卡所屬的 PR：卡名是 PR 名（主 change）或 PR 底下的 change 名；workplan 裡沒有就是 None。"""
    return chain.find_pr(prs, slug)


def session_features(features):
    """由 session 代管的 feature（chain.session_managed）：依賴合了才由 coordinate 開 session，它的卡不單獨派。"""
    return [f for f in features if chain.session_managed(f)]


def deps_unmerged(slug, prs, features):
    """卡所屬 PR 的 depends-on，加上所屬 feature 的 depends-on（chain.feature_waits），還沒 merged 的。"""
    pr = pr_of(prs, slug)
    if pr is None:
        return []
    status = {p.get("name"): p.get("status") for p in prs}
    deps = list(pr.get("depends-on") or [])
    deps += [d for d in chain.feature_waits(features, prs).get(pr["name"], []) if d not in deps]
    return [d for d in deps if status.get(d) != "merged"]


def waiting_on(prs, slug):
    """depends-on 裡有這張卡所屬的 PR、自己還沒 merged 的 PR 名。"""
    pr = pr_of(prs, slug)
    if pr is None:
        return []
    return [p.get("name") for p in prs if pr["name"] in (p.get("depends-on") or []) and p.get("status") != "merged"]


def status_line(lines, key, name):
    """`key:`（prs 或 changes）底下 `- name: <name>` 那一項自己的 status 行的 index；找不到是 None。"""
    item_indent = None
    for i, line in enumerate(lines):
        m = re.match(r"^( *)%s:\s*$" % key, line)
        if m:
            item_indent = len(m.group(1)) + 2
            continue
        if item_indent is None or not re.match(r"^ {%d}- name:\s*%s\s*(#.*)?$" % (item_indent, re.escape(name)), line):
            continue
        for j in range(i + 1, len(lines)):
            if re.match(r"^ {%d}status:" % (item_indent + 2), lines[j]):
                return j
            if lines[j].strip() and len(lines[j]) - len(lines[j].lstrip(" ")) <= item_indent:
                return None
        return None
    return None


def claude_argv(info):
    """herdr pane process-info 的輸出裡，前景行程中唯一一筆 argv0 是 claude 的 argv。
    不用 name 欄位：claude 那筆的 name 是版本號。認不得就 raise CoordinateError，點名欄位與值。"""
    try:
        procs = info["result"]["process_info"]["foreground_processes"]
    except (KeyError, TypeError) as e:
        raise CoordinateError("process-info 沒有 result.process_info.foreground_processes：%s" % json.dumps(info, ensure_ascii=False)[:200]) from e
    if not isinstance(procs, list) or not all(isinstance(p, dict) for p in procs):
        raise CoordinateError("foreground_processes 要是物件的 list：%s" % json.dumps(procs, ensure_ascii=False)[:200])
    hits = [p for p in procs if p.get("argv0") == "claude"]
    if not hits:
        raise CoordinateError("前景沒有 claude（argv0 是 %s）" % "、".join(str(p.get("argv0")) for p in procs))
    if len(hits) > 1:
        raise CoordinateError("前景有 %d 個 claude，認不出是哪一個（pid %s）" % (len(hits), "、".join(str(p.get("pid")) for p in hits)))
    if "argv" not in hits[0]:
        raise CoordinateError("claude 那筆前景行程沒有 argv 欄位：%s" % json.dumps(hits[0], ensure_ascii=False)[:200])
    return hits[0]["argv"]


def parse_drive_pid(key, entry):
    """dispatch.json 條目的 drive_pid：缺或 null 回 None，大於 0 的整數回它，其餘 raise DispatchFieldError。
    drive.sh 用 null 清 pid，所以 null 與缺都是「沒有」。"""
    pid = entry.get("drive_pid")
    if pid is None:
        return None
    if type(pid) is not int:
        raise DispatchFieldError(key, "drive_pid", pid, "要是整數")
    if not 0 < pid <= PID_MAX:
        raise DispatchFieldError(key, "drive_pid", pid, "要在 1 到 %d 之間" % PID_MAX)
    return pid


def parse_relaunching_at(key, entry, now):
    """dispatch.json 條目的 relaunching_at：缺或 null 回 None，帶時區、不晚於 now 加 CLOCK_SKEW_MINUTES 的 ISO 8601 字串回 datetime，其餘 raise DispatchFieldError。
    relaunch.sh 用 pop 清標記，所以 null 與缺都是「沒有」。"""
    at = entry.get("relaunching_at")
    if at is None:
        return None
    if not isinstance(at, str):
        raise DispatchFieldError(key, "relaunching_at", at, "要是 ISO 8601 字串")
    try:
        parsed = datetime.datetime.fromisoformat(at)
    except ValueError as e:
        raise DispatchFieldError(key, "relaunching_at", at, "不是 ISO 8601：%s" % e) from e
    if parsed.tzinfo is None:
        raise DispatchFieldError(key, "relaunching_at", at, "沒有時區")
    if parsed - now > datetime.timedelta(minutes=CLOCK_SKEW_MINUTES):
        raise DispatchFieldError(key, "relaunching_at", at, "晚於現在超過 %d 分鐘" % CLOCK_SKEW_MINUTES)
    return parsed


def drive_dead(key, disp):
    pid = parse_drive_pid(key, disp)
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    return False


def is_merged(c):
    """forge 說合了才算；只看 workplan 的 merged 不算，那可能是卡自己 /opsx-workflow:archive 做到一半。"""
    return bool(c["mr"] and c["mr"]["merged_at"])


def owner_gone(c):
    """已合併的卡的 agent 不在了。drive pid 死掉不算：/opsx-workflow:archive 是 pane 裡的 agent 做的，不是 drive。"""
    return not c["dispatch"] or c["agent_status"] == "unknown"


def main():
    state, dry = sys.argv[1], "--dry" in sys.argv[2:]
    rerun = os.path.join(state, "coordinator.rerun")
    # process 死掉時 kernel 會放掉 flock，所以不用處理殘留的 lock 檔
    with safefile.open_lock(os.path.join(state, "coordinator.lock")) as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            # 不等也不搶：同時跑兩輪會答同一個 gate、重派同一張卡兩次。拿著 lock 的那輪結束前會看到記號補跑
            if not dry:
                with safefile.open_lock(rerun):
                    pass
            Round(state, dry).log("-- 另一輪 coordinator 在跑，留下重跑記號")
            return 0
        rc = one_round(state, dry)
        # 補跑一次為限：事件連發時不一直跑下去，之後的記號留給下一次
        if not dry and os.path.exists(rerun):
            os.remove(rerun)
            rc = one_round(state, dry) or rc
    return rc


def one_round(state, dry):
    r = Round(state, dry)
    try:
        data = r.load()
    except CoordinateError as e:
        r.log("!! coordinator 這輪不跑：%s" % e)
        return 1
    r.log("== coordinator 開始" + ("（dry）" if r.dry else ""))
    repo_paths = data["repo_paths"]
    cards = [c for c in data["cards"] if not c["archived"]]

    merged = [c for c in cards if is_merged(c)]
    orphans = []
    for c in merged:
        if card_key(c) not in r.dispatch_file:
            waiting = waiting_on(r.workplan(repo_paths[c["repo"]]), c["slug"])
            r.log("?? %s 已合併但從沒派過，歸檔留給人%s" % (card_key(c), "；在等它的 PR：" + "、".join(waiting) if waiting else ""))
        elif owner_gone(c) or r.nobody_archiving(c):
            orphans.append(c)
    orphans = [c for c in orphans if r.no_late_commits(repo_paths[c["repo"]], c)]
    done = []
    for repo in sorted({c["repo"] for c in orphans}):
        done += r.clean_up(repo_paths[repo], [c for c in orphans if c["repo"] == repo])
    live = [c for c in cards if c not in merged]
    r.settle_parked(live)
    paused = r.usage_limit_paused(live)

    for c in live:
        w = c["waiting"]
        if not w:
            r.forget_waiting(c, live)
        if c["dispatch"] and w and w["type"] != "可以合併" and not paused:
            try:
                r.handle_gate(c, repo_paths[c["repo"]])
            except DispatchFieldError as e:
                r.bad_dispatch(c, e)
        if c["mr"] and c["mr"]["state"] == "ready":
            # 推了新 commit 再全綠是新的一次可以合併，所以綁 head sha
            r.notify(c, "ready", c["mr"]["head_sha"], "可以合併", "看板按「合併」：" + c["mr"]["url"])
    if not paused:
        r.notify_sub_gates(data.get("sessions") or [])
    for c in live:
        if paused or not c["dispatch"] or card_key(c) in r.memo["_parked"]:
            continue
        try:
            dead = drive_dead(card_key(c), c["dispatch"])
            if c["agent_status"] == "unknown":
                r.redispatch(c, repo_paths[c["repo"]], "agent 不在 herdr 裡（pane %s）" % c["dispatch"].get("pane"))
            elif dead:
                r.redispatch(c, repo_paths[c["repo"]], "drive pid %s 已經不在" % c["dispatch"]["drive_pid"])
            else:
                r.check_args(c, repo_paths[c["repo"]])
        except DispatchFieldError as e:
            r.bad_dispatch(c, e)
    if not paused:
        r.dispatch_features(repo_paths, r.dispatch_new(live, repo_paths), r.working(live))
    r.act(["opsx", "reap"])   # 失敗 act 已經記 log；孤兒的判斷與關閉條件都在 opsx reap
    r.save()
    r.log("== 結束：%d 張卡，收尾 %d 張" % (len(live), len(done)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
