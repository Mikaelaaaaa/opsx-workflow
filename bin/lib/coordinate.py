"""opsx coordinate 的一輪：讀 opsx collect，依序收尾已合併的卡、答 gate、停等依賴的卡、重派死掉的卡、派新卡。

每個動作是一條外部指令（opsx / git / openspec）。推節點（送 /<stage>）是每張卡的 drive 的事，這裡不送。
合併永遠由人按（板上的「合併」或 forge 網頁），這裡從不呼叫 opsx merge。
規則見 openspec/specs/opsx-coordinate/spec.md。
用法：coordinate.py <state dir> [--dry]
"""
import datetime
import fcntl
import functools
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chain  # noqa: E402
import grantactions  # noqa: E402
import jsonfile  # noqa: E402
import priority  # noqa: E402
import safefile  # noqa: E402

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
MERGE_WORDS = ("合併", "merge")
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
        self.levels = {}
        self.level_errors = {}
        self.orders = {}
        self.redispatched_now = set()

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
        for k in ("_parked", "_redispatched", "_notified"):
            self.memo.setdefault(k, {})   # 沒有這個 key 就是還沒記過任何一張
        self.dispatch_file = read_json(os.path.join(self.state, "dispatch.json"), "dispatch.json")
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
        """已合併但 agent 還在：歸檔、標 workplan、叫 chain 都是它自己 /archive 的事，這裡不搶。
        過了寬限 agent 還 idle，代表沒人會送 /archive（例如人在網頁上合併、drive 早就結束），回傳 True 由這裡收尾。"""
        key = card_key(c)
        ago = self.now - datetime.datetime.fromisoformat(c["mr"]["merged_at"])
        minutes = ago.total_seconds() // 60
        if ago <= datetime.timedelta(minutes=ARCHIVE_GRACE_MINUTES):
            self.log("⏳ %s 已合併，等它自己 /archive" % key)
            return False
        # idle 也可能是在等人回 gate，或互動模式的人暫時離開：那兩種不收，收了等於替人答 gate、關掉人的 session
        waiting_human = c["open_gates"] or self.dispatch_file[key].get("mode") == "interactive"
        if c["agent_status"] == "idle" and not waiting_human:
            self.log("-- %s 合併 %d 分鐘了 agent 還 idle，沒人會 /archive，這裡收尾" % (key, minutes))
            return True
        self.log("?? %s 合併 %d 分鐘了還沒歸檔，agent 是 %s，要人看它卡在哪" % (key, minutes, c["agent_status"]))
        return False

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
        shared = self.session_siblings(key, entry, top)
        if entry and entry.get("mode") != "stopped" and not shared:
            self.act(["opsx", "stop", c["slug"], "--repo", top])
        if not self.mark_merged(top, c["slug"]):
            return False
        rc, _, err = self.act(["openspec", "archive", c["slug"], "-y"], cwd=top)
        if rc != 0:
            self.log("?? %s openspec archive 失敗：%s" % (key, err[:200]))
            return False
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
            archived = [n for n in unfinished if is_archived(top, n)]
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

    def answer(self, c, top, gate, text, grant=False):
        args = ["opsx", "answer", c["slug"], "--gate", gate] + (["--grant", "this"] if grant else []) + ["--repo", top, "--", text]
        rc, out, err = self.act(args)
        if "agent_not_found" in out + err:
            self.redispatch(c, top, "answer 送不到")
        elif rc != 0:
            self.log("?? %s gate %s 回不了：%s" % (card_key(c), gate, err[:200]))

    def notify(self, c, kind, ident, event, body, scope=None):
        """這裡處理不了、要人去處理的事。每輪從狀態重算，送過的鍵記在 _notified，所以事件觸發那輪漏掉的由定時那輪補，也不會重送。
        scope 是去重鍵的前綴，預設是這張卡；feature session 的事屬於整個 session，傳 <repo>/@<feature>。
        herdr 的通知沒有點擊動作，內文要寫去哪裡處理。"""
        key = "%s/%s/%s" % (scope or card_key(c), kind, ident)
        if key in self.memo["_notified"]:
            return
        rc, out, err = self.act(["herdr", "notification", "show", "[%s] %s" % (card_key(c), event),
                                 "--body", body, "--sound", "request"])
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

    def notify_gate(self, c, w, why):
        self.notify(c, "gate", w["gate_id"], "gate %s %s" % (w["gate_id"], why), "看板：" + one_line(w.get("question") or ""))

    def handle_gate(self, c, top):
        """派出去的卡的第一個 open gate，照固定規則答、停、或留給人。"""
        w, key = c["waiting"], card_key(c)
        if w.get("needs") == "run":
            self.log("?? %s gate %s 要人在終端機跑指令再貼結果，不代答：%s" % (key, w["gate_id"], (w.get("recommended") or "")[:100]))
            self.notify_gate(c, w, "要你在終端機跑指令")
            return
        if w["type"] == "等待授權":
            # 合併永遠由人按：action 不一定剛好寫成 merge（mr-merge、external 打合併 API），題目也要看
            if any(k in ((w["action"] or "") + " " + (w.get("question") or "")).lower() for k in MERGE_WORDS):
                self.log("?? %s gate %s 要合併授權，不代答：合併由人在板上按" % (key, w["gate_id"]))
                self.notify_gate(c, w, "要合併授權")
                return
            self.answer(c, top, w["gate_id"], "允許", grant=w["action"] in grantactions.ACTIONS)
            return
        if w["type"] == "終端機等待輸入":
            pane = c["dispatch"].get("pane")
            self.log("?? %s 在 pane %s 等終端機輸入（autopilot 不該問 pane），要人看" % (key, pane))
            self.notify(c, "blocked", pane, "在終端機等輸入", "pane %s：%s" % (pane, one_line(w.get("question") or "")),
                        scope=session_scope(c))
            return
        if w["type"] == "type 不明":
            self.log("?? %s gate %s 的 type 沒寫或不在 approval | decision，不代答，要人看：%s" % (key, w["gate_id"], (w.get("question") or "")[:100]))
            self.notify_gate(c, w, "的 type 不明")
            return
        q = w.get("question") or ""
        pick = w.get("recommended") or (w.get("options") or [None])[0]
        text = q + " " + (pick or "")
        # 等別張卡的字本身含「合併後」「等 X 合」，要先認出來，不然會被下面的合併類規則吃掉
        if any(re.search(k, text) for k in WAIT_WORDS):
            self.log("⏳ %s gate %s 在等別張卡，先停 pane，有卡合進 main 那輪再派：%s" % (key, w["gate_id"], q[:100]))
            rc, _, _ = self.act(["opsx", "stop", c["slug"], "--repo", top])
            if rc == 0:
                self.memo["_parked"][key] = {"at": self.now.isoformat(timespec="seconds"), "gate": w["gate_id"],
                                             "merged": merged_prs(self.workplan(top))}
            return
        # merge 永遠人：合併授權綁 head sha，代答「重試合併」這類題就等於替人決定合併
        if any(k in text.lower() for k in MERGE_WORDS):
            self.log("?? %s gate %s 是合併類決定題，不代答：%s → %s" % (key, w["gate_id"], q[:100], (pick or "")[:60]))
            self.notify_gate(c, w, "是合併的決定")
            return
        if any(k in q for k in VERIFY_WORDS):
            self.answer(c, top, w["gate_id"], VERIFY_ANSWER)
            return
        if any(k in q for k in GRANT_WORDS):
            self.answer(c, top, w["gate_id"], GRANT_ANSWER)
            return
        if not pick:
            self.log("?? %s gate %s 沒有選項也沒有建議，要人看：%s" % (key, w["gate_id"], q[:120]))
            self.notify_gate(c, w, "沒有選項也沒有建議")
            return
        if any(k in pick for k in HUMAN_WORDS) or any(k in q for k in HUMAN_QUESTION):
            self.log("?? %s gate %s 要人動手，不代答：%s → %s" % (key, w["gate_id"], q[:100], pick[:60]))
            self.notify_gate(c, w, "要你動手")
            return
        self.answer(c, top, w["gate_id"], pick)

    def session_siblings(self, key, entry, top):
        """條目帶 feature 時，同 repo、同 feature、還沒停掉、卡還沒歸檔的其他卡的 key。
        session 共用時歸檔的卡條目不標 stopped（標了要送 stop 給共用的 pane），所以用卡的資料夾還在不在判斷。"""
        if not entry or not entry.get("feature"):
            return []
        repo = key.split("/", 1)[0]
        return [k for k, v in self.dispatch_file.items()
                if k != key and k.startswith(repo + "/") and v.get("feature") == entry["feature"] and v.get("mode") != "stopped"
                and os.path.isdir(os.path.join(top, "openspec", "changes", k.split("/", 1)[1]))]

    def redispatch_feature(self, c, top, why):
        """session 的 pane 不在了：同 feature 每張沒停的卡 stop 一次，再整個 feature 重派一次。memo 以 <repo>/@<feature> 記。"""
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
        self.log("!! %s %s，各卡 stop 後整個 feature 重派" % (key, why))
        mine = card_key(c)
        for k in sorted([mine] + self.session_siblings(mine, self.dispatch_file.get(mine), top)):
            self.act(["opsx", "stop", k.split("/", 1)[1], "--repo", top])
            self.dispatch_file[k]["mode"] = "stopped"
        rc, _, err = self.act(["opsx", "dispatch", "--feature", feature, "--agent", c["dispatch"]["agent"], "--mode", "autopilot", "--repo", top])
        if rc != 0:
            self.log("?? %s 重派開不了 session：%s" % (key, err[:200]))
            return
        self.memo["_redispatched"][key] = self.now.isoformat(timespec="seconds")
        self.redispatched_now.add(key)

    def redispatch(self, c, top, why):
        if c["dispatch"].get("feature"):
            self.redispatch_feature(c, top, why)
            return
        key = card_key(c)
        last = self.memo["_redispatched"].get(key)
        if last and self.now - datetime.datetime.fromisoformat(last) < datetime.timedelta(minutes=REDISPATCH_MINUTES):
            self.log("-- %s %s，%d 分鐘內重派過，這輪不再派" % (key, why, REDISPATCH_MINUTES))
            self.notify(c, "dead", last, "重派後 %d 分鐘內又掛了" % REDISPATCH_MINUTES,
                        "pane %s：%s；看板上重派或停掉" % (c["dispatch"].get("pane"), why))
            return
        if "agent" not in c["dispatch"]:
            self.log("?? %s %s，但 dispatch.json 沒記 agent，不知道派給誰" % (key, why))
            return
        self.log("!! %s %s，stop 後重派" % (key, why))
        self.act(["opsx", "stop", c["slug"], "--repo", top])
        self.act(["opsx", "dispatch", c["slug"], "--agent", c["dispatch"]["agent"], "--mode", "autopilot", "--kind", c["kind"], "--repo", top])
        self.memo["_redispatched"][key] = self.now.isoformat(timespec="seconds")

    def settle_parked(self, cards):
        """人手動重派了的 parked 卡不再由這裡管。人在板上把那個 gate 答掉了，記成已答，
        dispatch_new 照 coordinator 自己答過的一樣重派：卡是 coordinator 停的，不重派就沒有 agent 讀得到答案。"""
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

    def dispatch_new(self, cards, repo_paths):
        n = 0
        ranked = sorted((self.rank(c, repo_paths[c["repo"]]), i, c) for i, c in enumerate(cards))
        for _, _, c in ranked:
            key, top = card_key(c), repo_paths[c["repo"]]
            entry = self.dispatch_file.get(key)
            parked = self.memo["_parked"].get(key)
            newly = []
            if parked:
                # 等的 gate 還開著，collect 把它放在「待處理」。停下之後 workplan 多了 merged 的 PR 才重派：
                # 不管是卡自己 /archive 標的，還是這裡收尾時標的。gate 已經答過（上一輪派失敗）就直接重試派
                if c["section"] not in ("待指派", "待處理"):
                    continue
                if not parked.get("answered"):
                    newly = [p for p in merged_prs(self.workplan(top)) if p not in parked["merged"]]
                    if not newly:
                        continue
            elif c["section"] != "待指派":
                continue
            elif entry and entry.get("mode") == "stopped":
                continue   # 人在板上停掉的
            if not os.path.isfile(os.path.join(c["path"], "tasks.md")) or c["mr"]:
                continue
            owner, waiting = self.feature_wait(top, c["slug"])
            if waiting:
                self.log("⏳ %s 的 feature %s 等 %s merged 才派" % (key, owner, "、".join(waiting)))
                continue
            missing = deps_unmerged(c["slug"], self.workplan(top))
            if missing:
                self.log("⏳ %s 等 %s merged 才派" % (key, "、".join(missing)))
                continue
            if not AGENT_NAME.match(c["slug"]):
                self.log("-- %s 不是合法的 agent 名，跳過" % key)
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
            if parked and not parked.get("answered"):
                text = "停下之後合進 main 的 PR：%s。照最新的 main 繼續；你等的那張還沒合就再開 gate。" % "、".join(newly)
                rc, _, err = self.act(["opsx", "answer", c["slug"], "--gate", parked["gate"], "--repo", top, "--", text])
                if rc != 0:
                    self.log("?? %s parked 的 gate %s 回不了，不重派：%s" % (key, parked["gate"], err[:200]))
                    continue
                parked["answered"] = True
            agent = entry["agent"] if entry and "agent" in entry else "claude"
            rc, _, err = self.act(["opsx", "dispatch", c["slug"], "--agent", agent, "--mode", "autopilot", "--kind", c["kind"], "--repo", top])
            if not p0:
                n += 1
            if rc != 0:
                self.log("?? %s 派不出去：%s" % (key, err[:200]))
                continue
            self.memo["_parked"].pop(key, None)

    def feature_wait(self, top, slug):
        """卡所屬的 feature 名，與它 depends-on 裡還沒合併的 PR。coordinate 不自動開 session
        （等 session-entry 卡重構 session 條目），所以有依賴的 feature 的卡等依賴合了照單卡派。"""
        prs = self.workplan(top)
        pr = pr_of(prs, slug)
        if pr is None:
            return None, []
        status = {p.get("name"): p.get("status") for p in prs}
        for f in session_features(read_features(os.path.join(top, "openspec", "workplan.yaml"))):
            if any(p.get("name") == pr.get("name") for p in f.get("prs") or []):
                return f.get("name"), [d for d in f["depends-on"] if status.get(d) != "merged"]
        return None, []


def mark_stopped(d, key, at):
    """jsonfile.update 的 mutate：條目標 stopped，不碰 pane。"""
    d[key]["mode"] = "stopped"
    d[key]["stopped_at"] = at


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


def merged_prs(prs):
    return [p.get("name") for p in prs if p.get("status") == "merged"]


def pr_of(prs, slug):
    """卡所屬的 PR：卡名是 PR 名（主 change）或 PR 底下的 change 名；workplan 裡沒有就是 None。"""
    return chain.find_pr(prs, slug)


def session_features(features):
    """有 depends-on 的 feature：它的卡要等 feature 的依賴都合併才派。"""
    return [f for f in features if f.get("depends-on")]


def deps_unmerged(slug, prs):
    pr = pr_of(prs, slug)
    if pr is None:
        return []
    status = {p.get("name"): p.get("status") for p in prs}
    return [d for d in pr.get("depends-on") or [] if status.get(d) != "merged"]


def is_archived(top, name):
    """change 目錄不在了，而且 openspec archive 留下了 <日期>-<name>。"""
    changes = os.path.join(top, "openspec", "changes")
    return not os.path.isdir(os.path.join(changes, name)) and bool(glob.glob(os.path.join(changes, "archive", "????-??-??-" + glob.escape(name))))


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
    """已合併的卡的 agent 不在了。drive pid 死掉不算：/archive 是 pane 裡的 agent 做的，不是 drive。"""
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
    done = []
    for repo in sorted({c["repo"] for c in orphans}):
        done += r.clean_up(repo_paths[repo], [c for c in orphans if c["repo"] == repo])
    live = [c for c in cards if c not in merged]
    r.settle_parked(live)

    for c in live:
        w = c["waiting"]
        if not w:
            r.forget_waiting(c, live)
        if c["dispatch"] and w and w["type"] != "可以合併":
            r.handle_gate(c, repo_paths[c["repo"]])
        if c["mr"] and c["mr"]["state"] == "ready":
            # 推了新 commit 再全綠是新的一次可以合併，所以綁 head sha
            r.notify(c, "ready", c["mr"]["head_sha"], "可以合併", "看板按「合併」：" + c["mr"]["url"])
    for c in live:
        if not c["dispatch"] or card_key(c) in r.memo["_parked"]:
            continue
        if c["agent_status"] == "unknown":
            r.redispatch(c, repo_paths[c["repo"]], "agent 不在 herdr 裡（pane %s）" % c["dispatch"].get("pane"))
        elif drive_dead(c["dispatch"]):
            r.redispatch(c, repo_paths[c["repo"]], "drive pid %s 已經不在" % c["dispatch"]["drive_pid"])
    r.dispatch_new(live, repo_paths)
    r.act(["opsx", "reap"])   # 失敗 act 已經記 log；孤兒的判斷與關閉條件都在 opsx reap
    r.save()
    r.log("== 結束：%d 張卡，收尾 %d 張" % (len(live), len(done)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
