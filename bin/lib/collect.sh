#!/usr/bin/env bash
# opsx collect [--root <dir>] [--state <dir>]：看板唯一的資料來源，印一份 JSON，不寫檔（mr.sh 的 cache/ 除外）。
# 讀三處：<root>/*/openspec/changes/*/（含 archive/）、<state>/{dispatch.json,grants.toml,workspaces.toml,unfiled/*.md}、
# herdr agent list（不看 HERDR_ENV，叫不通記 errors）與 glab / gh（經 mr_json）。specs/board-collect/spec.md。
#
# 輸出：{generated_at, scopes[{workspace, repos[]}], repo_paths{repo: 實體路徑}, cards[], unfiled[{slug, title, source, found}],
#       last_sync（sync.log 最後一行，沒有檔時 null）， unmatched_agents[], errors[{source,message}],
#       progress{repo: {milestone, goal, remaining, mergeable, testing, developing, waiting_on_you, not_dispatched,
#         not_dispatched_planned[], at}}（每個 repo 一份；沒設 current_milestone 或 workplan 壞了時 milestone、goal 為 null，數全部活的 main change）}
# 每張卡：{repo, slug, title, kind, stage, section, since, waiting, open_gates[{id, opened_at}], dispatch, status, agent_status, mr,
#        source, upstream, stale, priority{level, reason, overridden}（已歸檔或算不出來時 null）,
#        notes[{at, text}]（inbox.md ## 派工指示，舊的在前）,
#        merged[{id, when, source, text, kind_of_work, area, evidence?}]（inbox.md 的 ## 併入： 段，依檔案順序；已歸檔的卡是 []）,
#        session（收進 session 的主 change 才有："<repo>/<feature>"）,
#        progress_class ∈ mergeable | waiting_on_you | testing | developing | not_dispatched（不在進度範圍內為 null）}
# sessions[]：{repo, feature, section, main_done, main_total, sub_done, sub_total, current{slug, stage}|null,
#   mains[{slug, pr_status, stage, section, dispatch, agent_status, open_gates, waiting, subs[{slug, status, stage, worker, open_gates, waiting}]}]}
#   section ∈ 待處理 | 進行中 | 待指派 | 收件匣 | 已完成（收件匣＝沒派出、stage 還是 explore）；waiting.type ∈ 等待授權 | 等待決定 | type 不明 | 可以合併 | 終端機等待輸入；waiting.needs ∈ run | null
#
# gates.md 的格式（apply 步 5 寫、answer 改）：每個 gate 一段
#   ## <gate id>
#   type: approval | decision      action: push|mr|migrate|…（approval 才有）      status: open | answered      opened_at: <ISO>
#   needs: run（可選：建議欄是要人在終端機跑的指令；看板不給照建議）      type 沒寫或不在同義詞表內 → waiting.type 為 type 不明
#   waits-on: <卡名>（可選：這題要等那張卡合進 main 才能做；coordinate 只憑這個欄位停 pane，不從問題與建議的文字猜）
#   問題: …   建議: …   選項: a | b (Recommended) | c（decision 才有）   證據: …   風險: …   預設: …
#   已確認: …（可多行，到下一個欄位為止）   answer: …（answered 時）

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/mr.sh"

opsx_collect() {
  local root="$HOME/code" state="$OPSX_STATE_DIR"
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) root="$2"; shift 2 ;;
      --state) state="$2"; shift 2 ;;
      *) die "collect: 不認得的參數 $1" ;;
    esac
  done
  [ -d "$root" ] || die "collect: --root 不是目錄：$root"
  # generated_at 在讀任何來源前取：看板拿它當 banner 看過的資料涵蓋到的時間點，不能晚於任何一次讀取
  local now; now="$(now_iso)"
  local work; work="$(mktemp -d "${TMPDIR:-/tmp}/opsx-collect.XXXXXX")"
  trap 'rm -rf "$work"' RETURN

  # bash 只掃目錄，每張卡寫一行 TSV（repo、slug、dir、archived、stage、mr 檔）給下面那段 python 組 JSON。
  # stage 用 stage_of，MR 用 mr_json，不另算；這裡不 fork python，1000 張卡就是 1000 次啟動。mr_json 只對有 MR 的卡跑。
  # repo 的判準：<root>/<name>/openspec/changes 存在，而且 <name>/.git 是目錄。linked worktree 的 .git 是檔案，跳過，
  # 不然 Agentory-AI-langflow、*-wt-* 會被當成別的 repo。archive 只取最新 N 張，已完成不能無限長。
  local repo_dir repo d slug archived stage mrfile n=0 archive_cap="${OPSX_COLLECT_ARCHIVE_CAP:-30}" seen_archive real
  : > "$work/cards.tsv"; : > "$work/legacy"; : > "$work/seen"; mkdir -p "$work/mr"
  # repo 清單（D1）：<root>/*/ 加上 sources.toml 登記的 path，init 過的 repo 不在 root 底下也算（opsx-workflow 在 ~/code/sandbox/）
  local -a repo_dirs=()
  for repo_dir in "$root"/*/; do repo_dirs+=("${repo_dir%/}"); done
  if [ -f "$state/sources.toml" ]; then
    while IFS= read -r repo_dir; do repo_dirs+=("$repo_dir"); done < <(sed -nE 's/^path = "(.*)"$/\1/p' "$state/sources.toml")
  fi
  for repo_dir in "${repo_dirs[@]}"; do
    [ -d "$repo_dir/openspec/changes" ] || continue
    real="$(cd "$repo_dir" && pwd -P)"
    if grep -qxF "$real" "$work/seen"; then continue; fi
    printf '%s\n' "$real" >> "$work/seen"; repo_dir="$real/"
    if [ -f "$repo_dir/.git" ]; then printf '%s\n' "$(basename "$repo_dir")" >> "$work/worktrees"; continue; fi
    repo="$(basename "$repo_dir")"
    printf '%s\t%s\n' "$repo" "$real" >> "$work/repos"
    seen_archive=0
    for d in "$repo_dir"openspec/changes/*/ $(ls -1dt "$repo_dir"openspec/changes/archive/*/ 2>/dev/null); do
      [ -d "$d" ] || continue
      d="${d%/}"; slug="${d##*/}"
      case "$d" in
        */changes/archive) continue ;;
        */changes/archive/*) seen_archive=$((seen_archive+1)); [ "$seen_archive" -le "$archive_cap" ] || continue
           archived=true; slug="${slug#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"; stage=archive ;;
        *) if collect_is_legacy "$d"; then printf '%s\n' "$repo" >> "$work/legacy"; continue; fi
           archived=false; stage="$(stage_name "${repo_dir%/}" "$slug")" ;;
      esac
      mrfile=""
      if [ "$archived" = false ] && st_mr_in_report "$d"; then n=$((n+1)); mrfile="$work/mr/$n.json"; OPSX_MR_STALE_OK=1 mr_json "$d" > "$mrfile"; fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$slug" "$d" "$archived" "$stage" "$mrfile" >> "$work/cards.tsv"
    done
  done
  [ -f "$work/repos" ] || : > "$work/repos"; [ -f "$work/worktrees" ] || : > "$work/worktrees"

  # herdr：一律問（它靠 socket，不需要在 pane 裡）；失敗記 errors，不中斷
  local herdr_err=""
  herdr agent list > "$work/agents.json" 2>"$work/agents.err" || herdr_err="herdr agent list 失敗：$(head -c 200 "$work/agents.err")"

  # 讀卡的檔與全域狀態，組 JSON
  OPSX_C_WORK="$work" OPSX_C_STATE="$state" OPSX_C_HERDR_ERR="$herdr_err" OPSX_C_NOW="$now" OPSX_C_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - <<'PY'
import datetime, json, os, re, sys, tomllib
sys.path.insert(0, os.environ["OPSX_C_LIB"])
import gaterule
import gatetype
import grantactions
from chain import load_workplan

sys.path.insert(0, os.path.join(os.environ["OPSX_ROOT"], "bin", "lib"))
import inboxmerge
import priority

work, state = os.environ["OPSX_C_WORK"], os.environ["OPSX_C_STATE"]
errors = []
if os.environ["OPSX_C_HERDR_ERR"]:
    errors.append({"source": "herdr", "message": os.environ["OPSX_C_HERDR_ERR"]})

def read(path, default=""):
    try:
        with open(path, encoding="utf-8") as f: return f.read()
    except FileNotFoundError:
        return default

def load_json(path, default):
    try:
        return json.loads(read(path) or "null") if os.path.exists(path) else default
    except json.JSONDecodeError as e:
        errors.append({"source": path, "message": "JSON 壞了：%s" % e}); return default

def load_toml(path):
    try:
        return tomllib.loads(read(path))
    except tomllib.TOMLDecodeError as e:
        errors.append({"source": path, "message": "TOML 壞了：%s" % e}); return {}

repo_paths = dict(l.split("\t", 1) for l in read(os.path.join(work, "repos")).split("\n") if l)
repos = list(repo_paths)
worktrees = [r for r in read(os.path.join(work, "worktrees")).split("\n") if r]
workspaces = load_toml(os.path.join(state, "workspaces.toml")).get("repos", {})
grants = load_toml(os.path.join(state, "grants.toml")).get("repos", {})
dispatch = load_json(os.path.join(state, "dispatch.json"), {}) or {}

# 等級跟 opsx priority 同一個計算，一個 repo 算一次（依賴繼承要看整個 repo）。workplan 壞了：那個 repo 的卡都沒有等級
# workplan 壞了的 repo plans 為 None：進度照沒設 current milestone 算
levels, plans, unreadable = {}, {}, {}
for r, top in repo_paths.items():
    plans[r] = None
    try:
        levels[r] = priority.levels(top)
        plans[r] = priority.load_plan(top)
    except priority.WorkplanUnreadable as e:
        levels[r] = None   # sessions 那段多半也會記同一個檔；輸出前才補記它沒記到的，一個檔一筆
        unreadable[os.path.join(top, "openspec", "workplan.yaml")] = str(e)
    except priority.PriorityError as e:
        errors.append({"source": os.path.join(top, "openspec", "workplan.yaml"), "message": str(e)})
        levels[r] = None

def priority_of(repo, slug, archived, inbox_path):
    if archived or levels[repo] is None:
        return None
    got = levels[repo].get(slug)   # 掃目錄之後才算等級，中間被 archive 搬走的卡不在裡面
    if got is None:
        return None
    if "error" in got:
        errors.append({"source": inbox_path, "message": got["error"]})
        return None
    return got

# scopes：每個 workspace 底下掛哪些 repo；沒掛的 repo 歸在 workspace null
by_ws = {}
for r in repos:
    by_ws.setdefault(workspaces.get(r), []).append(r)
scopes = [{"workspace": ws, "repos": rs} for ws, rs in by_ws.items() if ws is not None]
if None in by_ws:
    scopes.append({"workspace": None, "repos": by_ws[None]})

# herdr agents：真格式（tests/fakes/herdr-samples/agent-list.json，2026-11-06 實跑）
#   {"id":"cli:agent:list","result":{"agents":[{"agent":"claude","agent_status":"idle","pane_id":"w1:p2","tab_id":"w1:t2",
#    "workspace_id":"w1","terminal_title_stripped":"…","agent_session":{"value":"<uuid>"}}],"type":"agent_list"}}
# 沒有 agent 名字；卡對 agent 只靠 pane_id == dispatch.json 的 pane。
agents = None   # None = herdr 不可用（agent_status 一律 null）；[] = herdr 在但沒有 agent（派出的卡都是 unknown）
agents_path = os.path.join(work, "agents.json")
if os.path.exists(agents_path) and not os.environ["OPSX_C_HERDR_ERR"]:
    try:
        raw = json.loads(read(agents_path) or "{}")
        agents = raw["result"]["agents"]
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        agents = None
        errors.append({"source": "herdr", "message": "agent list 讀不懂（要 result.agents）：%s" % e})

FIELD = re.compile(r"^(type|needs|waits-on|action|status|opened_at|問題|建議|選項|證據|風險|預設|已確認|answer):\s*(.*)$")

def parse_gates(text):
    gates, cur, key = [], None, None
    for line in text.split("\n"):
        if line.startswith("## "):
            cur = {"id": line[3:].strip()}; gates.append(cur); key = None; continue
        if cur is None: continue
        m = FIELD.match(line)
        if m:
            key = m.group(1); cur[key] = m.group(2).strip()
        elif key in ("已確認", "證據", "問題") and line.strip():
            cur[key] = (cur[key] + "\n" + line.strip()).strip()
    return gates

OPENED_AT_SLACK = datetime.timedelta(seconds=60)   # 同一秒寫入與時鐘誤差

def opened_at_of(g, path, now_dt):
    """不合格的 opened_at 給 None 並記 errors：沒時區比不出先後，晚於現在會讓 banner 每次都列它。"""
    raw = g.get("opened_at")
    if not raw: return None
    try:
        t = datetime.datetime.fromisoformat(raw)
    except ValueError:
        why = "解析不了"
    else:
        if t.tzinfo is None: why = "沒有時區"
        elif t > now_dt + OPENED_AT_SLACK: why = "晚於現在"
        else: return raw
    errors.append({"source": path, "message": "gate %s 的 opened_at 不合格（%s）：%s" % (g["id"], why, raw)})
    return None

def one_liner(inbox):
    m = re.search(r"^## 一句話\s*\n+(.+?)$", inbox, re.M)
    return m.group(1).strip() if m else None

def frontmatter(inbox, key):
    m = re.search(r"^%s:\s*(.*)$" % key, inbox, re.M)
    return m.group(1).strip() or None if m else None

# 段落範圍跟 note.sh 的 note_append 寫入時認的一樣，兩邊認定不同就會寫得進去、看板看不到
def notes_of(inbox, slug, path):
    lines = inbox.splitlines()
    head = next((i for i, l in enumerate(lines) if re.fullmatch(r"## 派工指示\s*", l)), None)
    if head is None: return []
    notes = []
    for l in lines[head + 1:]:
        if l.startswith("## "): break
        if not l.strip(): continue
        m = re.fullmatch(r"- (\S+) (.+)", l)
        if m: notes.append({"at": m.group(1), "text": m.group(2).strip()})
        else: errors.append({"source": path, "message": "%s 的派工指示格式不對：%s" % (slug, l)})
    return notes

# 格式以 split-out 讀的為準（inboxmerge.parse）：看板列得出來的項目一定拆得回來
def merged_of(inbox, slug, path):
    items = []
    for head, got in inboxmerge.sections(inbox):
        if isinstance(got, ValueError):
            errors.append({"source": path, "message": "%s 的併入段格式不對：%s（%s）" % (slug, head, got)})
        else:
            items.append(got)
    return items

def kind_of(d):
    m = re.search(r"^kind:\s*(\S+)", read(os.path.join(d, ".openspec.yaml")), re.M)
    return m.group(1) if m else "dev"

def waiting_of(card, gates, agent_status):
    for g in gates:
        if g.get("status", "").strip() != "open": continue
        base = {"gate_id": g["id"], "question": g.get("問題"), "recommended": g.get("建議"), "evidence": g.get("證據"),
                "risk": g.get("風險"), "default_if_unanswered": g.get("預設"), "confirmed": g.get("已確認"),
                "needs": "run" if g.get("needs") == "run" else None,
                "waits_on": g.get("waits-on") or None}
        gtype = gatetype.normalize(g.get("type", ""))
        if gtype is None:
            return {"type": "type 不明", "action": None, "options": [], **base}
        if gtype == gatetype.APPROVAL:
            # action 不在閘門會查的動作內（含 merge、沒寫）時 answer --grant 一定失敗，授權選項就不要給
            opts = ["這次", "這張卡", "這個 repo 永遠", "拒絕"] if g.get("action") in grantactions.ACTIONS else ["拒絕"]
            return {"type": "等待授權", "action": g.get("action"), "options": opts, **base}
        opts = [o.strip() for o in (g.get("選項") or "").split("|") if o.strip()]
        rec = base["recommended"]
        cleaned = []
        for o in opts:
            if "(Recommended)" in o:
                o = o.replace("(Recommended)", "").strip(); rec = rec or o
            cleaned.append(o)
        return {"type": "等待決定", "action": None, "options": cleaned, **{**base, "recommended": rec}}
    mr = card["mr"]
    if mr and mr.get("state") == "ready":
        return {"type": "可以合併", "action": "merge", "gate_id": None, "needs": None, "options": ["合併"], "question": "MR 五條件全綠", "recommended": "合併",
                "evidence": mr["url"], "risk": None, "default_if_unanswered": "留在進行中", "confirmed": None}
    if agent_status == "blocked":
        return {"type": "終端機等待輸入", "action": None, "gate_id": None, "needs": None, "options": ["開啟 pane", "停止", "重新指派"],
                "question": "agent 在終端機等輸入，板上沒有對應的 gate", "recommended": "開啟 pane", "evidence": None, "risk": "照規則不該發生：要授權的動作應寫 gate",
                "default_if_unanswered": "agent 停在那裡", "confirmed": None}
    return None

cards, matched_panes, legacy = [], set(), {}
for r in read(os.path.join(work, "legacy")).split("\n"):
    if r: legacy[r] = legacy.get(r, 0) + 1
now = os.environ["OPSX_C_NOW"]
now_dt = datetime.datetime.fromisoformat(now)
for line in read(os.path.join(work, "cards.tsv")).split("\n"):
    if not line: continue
    repo_, slug_, dir_, archived_, stage_, mrfile = line.split("\t")
    c = {"repo": repo_, "slug": slug_, "dir": dir_, "archived": archived_ == "true", "stage": stage_,
         "mr": json.loads(read(mrfile)) if mrfile else None}
    d = c["dir"]
    if c["mr"] and c["mr"].get("error"):
        errors.append({"source": "glab" if "glab" in c["mr"]["error"] else "gh", "message": "%s/%s：%s" % (repo_, slug_, c["mr"]["error"])})
    inbox = read(os.path.join(d, "inbox.md"))
    key = "%s/%s" % (c["repo"], c["slug"])
    disp = dispatch.get(key)
    if disp and disp.get("mode") == "stopped": disp = None
    agent_status = None
    if disp and agents is not None:
        hit = [a for a in agents if str(a.get("pane_id")) == str(disp.get("pane"))]
        agent_status = (hit[0].get("agent_status") or "unknown") if hit else "unknown"
        if hit: matched_panes.add(str(hit[0].get("pane_id")))
    gates_path = os.path.join(d, "gates.md")
    gates = parse_gates(read(gates_path)) if not c["archived"] else []
    waiting = None if c["archived"] else waiting_of(c, gates, agent_status)
    if c["archived"] or c["stage"] in ("archive", "split"): section = "已完成"
    elif waiting: section = "待處理"
    elif disp: section = "進行中"
    elif c["stage"] == "explore": section = "收件匣"
    else: section = "待指派"
    cards.append({
        "repo": c["repo"], "slug": c["slug"], "title": one_liner(inbox) or c["slug"], "kind": kind_of(d),
        "stage": c["stage"], "section": section, "archived": c["archived"],
        "since": frontmatter(inbox, "found") or (re.search(r"^created:\s*(\S+)", read(os.path.join(d, ".openspec.yaml")), re.M) or [None, None])[1],
        "waiting": waiting, "open_gates": [{"id": g["id"], "opened_at": opened_at_of(g, gates_path, now_dt)} for g in gates if g.get("status") == "open"],
        "dispatch": disp, "status": load_json(os.path.join(d, "status.json"), None),
        "agent_status": agent_status, "mr": c["mr"],
        "grants_repo": grants.get(c["repo"]), "path": d,
        "source": frontmatter(inbox, "source"), "upstream": frontmatter(inbox, "upstream"), "stale": frontmatter(inbox, "stale") == "true",
        "priority": priority_of(c["repo"], c["slug"], c["archived"], os.path.join(d, "inbox.md")),
        "notes": notes_of(inbox, c["slug"], os.path.join(d, "inbox.md")),
        "merged": [] if c["archived"] else merged_of(inbox, c["slug"], os.path.join(d, "inbox.md")),
    })

order = {"待處理": 0, "進行中": 1, "待指派": 2, "收件匣": 3, "已完成": 4}

def wp_list(owner, key, where):
    """load_workplan 認不出形狀時不會 raise（features: oops 會變字串），這裡檢查：key 不在或空是 []，其餘要是有 name 的 mapping list。"""
    v = owner.get(key) or []
    if not isinstance(v, list) or not all(isinstance(x, dict) and x.get("name") for x in v):
        raise ValueError("%s 的 %s 要是有 name 的 list：%r" % (where, key, v))
    return v

def sub_stage(d, status):
    if status is not None: return status.get("phase")
    if not os.path.isdir(d): return None
    if not os.path.exists(os.path.join(d, "proposal.md")): return "inbox"
    if not os.path.exists(os.path.join(d, "tasks.md")): return "propose"
    return "apply" if re.search(r"^\s*- \[ \]", read(os.path.join(d, "tasks.md")), re.M) else "done"

def sub_node(main_dir, ch):
    d = os.path.join(main_dir, "subs", ch["name"])
    status_path = os.path.join(d, "status.json")
    status = load_json(status_path, None)
    if status is not None and not isinstance(status, dict):   # 跟 JSON 壞掉同樣處理：記 errors、站點改由檔推，不讓一個檔毀掉整份
        errors.append({"source": status_path, "message": "status.json 要是 object：%r" % (status,)}); status = None
    gates_path = os.path.join(d, "gates.md")
    gates = parse_gates(read(gates_path))
    return {"slug": ch["name"], "status": ch.get("status"), "stage": sub_stage(d, status),
            "worker": status.get("worker") if status is not None else None,
            "open_gates": [{"id": g["id"], "opened_at": opened_at_of(g, gates_path, now_dt)} for g in gates if g.get("status") == "open"],
            "waiting": waiting_of({"mr": None}, gates, None)}

def main_node(repo, pr, by_key):
    c = by_key.get((repo, pr["name"]))
    if c:
        vals = {k: c[k] for k in ("stage", "section", "dispatch", "agent_status", "open_gates", "waiting")}
    else:   # 已歸檔超出 archive cap，或還沒建卡
        merged = pr.get("status") == "merged"
        vals = {"stage": "archive" if merged else None, "section": "已完成" if merged else None,
                "dispatch": None, "agent_status": None, "open_gates": [], "waiting": None}
    main_dir = os.path.join(repo_paths[repo], "openspec", "changes", pr["name"])
    return {"slug": pr["name"], "pr_status": pr.get("status"), **vals,
            "subs": [sub_node(main_dir, ch) for ch in wp_list(pr, "changes", "PR %s" % pr["name"])]}

def session_of(repo, f, by_key):
    prs = wp_list(f, "prs", "feature %s" % f["name"])
    mains = [main_node(repo, pr, by_key) for pr in prs]
    subs = [s for m in mains for s in m["subs"]]
    cur = next((m for m in mains if m["pr_status"] != "merged"), None)
    live = [m for m in mains if m["section"] != "已完成"]
    if not live: section = "已完成"
    elif any(s["waiting"] for s in subs): section = "待處理"
    # 沒有卡、還沒合併的主 change：workplan 排了但還沒建卡，算待指派
    else: section = min((m["section"] or "待指派" for m in live), key=order.__getitem__)
    return {"repo": repo, "feature": f["name"], "section": section,
            "main_done": sum(1 for m in mains if m["pr_status"] == "merged"), "main_total": len(mains),
            "sub_done": sum(1 for s in subs if s["status"] == "done"), "sub_total": len(subs),
            "current": {"slug": cur["slug"], "stage": cur["stage"]} if cur else None, "mains": mains}

# sessions（board-tree D4）：feature 底下有 PR 掛子殼（changes/<PR>/subs/）才收；舊寫法一個 PR 掛多個平放殼的不收
by_key = {}
for c in cards: by_key.setdefault((c["repo"], c["slug"]), c)
sessions = []
for repo in repos:
    wp_path = os.path.join(repo_paths[repo], "openspec", "workplan.yaml")
    if not os.path.exists(wp_path): continue
    try:
        features = wp_list(load_workplan(wp_path), "features", "workplan")
        mine = []
        for f in features:
            prs = wp_list(f, "prs", "feature %s" % f["name"])
            if any(os.path.isdir(os.path.join(repo_paths[repo], "openspec", "changes", pr["name"], "subs")) for pr in prs):
                mine.append(session_of(repo, f, by_key))
    except ValueError as e:   # UnicodeDecodeError 也是 ValueError
        errors.append({"source": wp_path, "message": "workplan 讀不懂：%s" % e}); continue
    for s in mine:
        for m in s["mains"]:
            c = by_key.get((repo, m["slug"]))
            if not c: continue
            if "session" in c:
                errors.append({"source": wp_path, "message": "%s 同時在 %s 與 %s，卡的 session 取前者" % (m["slug"], c["session"], "%s/%s" % (repo, s["feature"]))})
            else:
                c["session"] = "%s/%s" % (repo, s["feature"])
    sessions.extend(mine)

PROGRESS_CLASSES = ("mergeable", "waiting_on_you", "testing", "developing", "not_dispatched")
ARCHIVED_NAME = re.compile(r"^\d{4}-\d{2}-\d{2}-(.+)$")

def progress_class(c):
    """由上往下取第一個符合的；不看協調者在不在跑、不看 agent_status。dispatch 為 None 包含 stopped。"""
    w = c["waiting"]
    if w and w["type"] == "可以合併": return "mergeable"
    if w:
        verdict = gaterule.decide(w)
        # 沒派出的卡協調者不會答它的 gate，只剩人能答；停 pane 等別張卡的不算
        if verdict[0] == "human" or (not c["dispatch"] and verdict[0] != "park"): return "waiting_on_you"
    if c["stage"] in ("review", "pr", "babysit"): return "testing"
    if c["dispatch"]: return "developing"
    return "not_dispatched"

def has_shell(top, name):
    changes = os.path.join(top, "openspec", "changes")
    if os.path.isdir(os.path.join(changes, name)): return True
    archive = os.path.join(changes, "archive")
    return any((m := ARCHIVED_NAME.match(n)) and m[1] == name for n in (os.listdir(archive) if os.path.isdir(archive) else []))

# 進度以 main change 為單位：有殼的卡，加上 workplan 排了還沒建殼的 PR；子 change 與拆過的母卡不算
progress = {}
for repo in repos:
    plan = plans.get(repo)
    current = plan["current"] if plan else None
    scoped = [f for f in (plan["features"] if plan else []) if not current or f.get("milestone") == current]
    owned = {pr["name"] for f in scoped for pr in f.get("prs") or []} if current else None
    counts = dict.fromkeys(PROGRESS_CLASSES, 0)
    for c in cards:
        if c["repo"] != repo: continue
        live = not c["archived"] and c["stage"] not in ("archive", "split")
        c["progress_class"] = progress_class(c) if live and (owned is None or c["slug"] in owned) else None
        if c["progress_class"]: counts[c["progress_class"]] += 1
    planned = [pr["name"] for f in scoped for pr in f.get("prs") or []
               if pr.get("status") != "merged" and not has_shell(repo_paths[repo], pr["name"])]
    counts["not_dispatched"] += len(planned)
    progress[repo] = {"milestone": current, "goal": plan["goals"][current] if current else None,
                      "remaining": sum(counts.values()), **counts, "not_dispatched_planned": planned, "at": now}

cards.sort(key=lambda x: (order[x["section"]], x["repo"], x["slug"]))
unfiled_dir = os.path.join(state, "unfiled")
unfiled = []
for name in sorted(os.listdir(unfiled_dir)) if os.path.isdir(unfiled_dir) else []:
    if not name.endswith(".md"): continue
    text = read(os.path.join(unfiled_dir, name))
    unfiled.append({"slug": name[:-3], "title": one_liner(text) or name[:-3], "source": frontmatter(text, "source"), "found": frontmatter(text, "found")})
# 上次同步：sync.log（opsx log --sync 的格式 ts · source · 新卡數 · 文字）最後一列 source = sync，文字是 sync.py 的 Tally.summary()。
# debt.sh 自己寫的 debt 掃描列、別的工具寫的列不算。
SYNC_TEXT = re.compile(r"新建 (\d+) · 更新 (\d+) · 沒變 (\d+) · 錯誤 (\d+)(?:：(.*))?")
last_sync = None
for line in reversed([l for l in read(os.path.join(state, "sync.log")).split("\n") if l]):
    cols = line.split("\t")
    m = SYNC_TEXT.fullmatch(cols[3]) if len(cols) == 4 and cols[1] == "sync" else None
    if m:
        last_sync = {"at": cols[0], "created": int(m[1]), "updated": int(m[2]), "unchanged": int(m[3]), "errors": int(m[4]), "first_error": m[5] or ""}
        break

# 孤兒 pane：cwd（或 foreground_cwd）在 <repo>/.claude/worktrees/<slug>/ 底下（或 dispatch.json 記的 worktree），
# 而且這張卡已歸檔、已拆（stage split）、dispatch.json 標 stopped、或卡目錄不在，而且這個 pane 就是 dispatch.json 該條記的 pane。
# 三個都要：只看 cwd，人在同名 worktree 自己開的 pane 會被認領；只看 pane id，herdr 重用 id 時會指到別人的 pane。
# 判斷只在這裡算一次，coordinate / reap / 看板都讀 orphans。
# workplan 標 merged 的卡（stage archive）還沒歸檔，agent 可能正在跑 /archive，不算。
# 同一個 slug 先歸檔後又建活卡時活卡優先，所以歸檔的先放、活的後蓋。
card_by_key = {(c["repo"], c["slug"]): c for c in cards if c["archived"]}
card_by_key.update({(c["repo"], c["slug"]): c for c in cards if not c["archived"]})
# session 條目（key <repo>/@<feature>）與它的成員共用一棵 worktree：worktree 一律算給 session 條目，pane 上沒有活成員時它才是孤兒
worktree_of = {}
for k, e in sorted(dispatch.items(), key=lambda kv: kv[0].split("/", 1)[1].startswith("@")):
    if e.get("worktree"):
        worktree_of[e["worktree"].rstrip("/")] = tuple(k.split("/", 1))

def worktree_owner(path):
    for p in {path, os.path.realpath(path)}:
        for wt, key in worktree_of.items():
            if p == wt or p.startswith(wt + "/"): return key
        for repo_, top in repo_paths.items():
            prefix = top + "/.claude/worktrees/"
            if p.startswith(prefix) and p[len(prefix):].split("/")[0]: return (repo_, p[len(prefix):].split("/")[0])
    return None

def orphan_reason(key, pane):
    # .claude/worktrees/ 也放別的工具自己開的 worktree：dispatch.json 沒記過、或記的不是這個 pane 的，不是 opsx 開的 pane
    entry = dispatch.get("%s/%s" % key)
    if entry is None or str(entry.get("pane")) != str(pane): return None
    # opsx 自己已經關掉這個 pane（stop 記 pane_closed_at、reap 記 reaped_at）：同一個 id 現在是別人的 pane
    if entry.get("pane_closed_at") or entry.get("reaped_at"): return None
    # session 條目不是卡：走到這裡代表 pane 上已沒有活成員（live_panes 先擋掉了）
    if key[1].startswith("@"): return "session-done"
    c = card_by_key.get(key)
    if c is None:
        # 卡不在 cards 裡不等於卡目錄不存在：repo 沒被這次掃描、或被當舊卡濾掉的活卡不能算
        top = repo_paths.get(key[0])
        return "card-missing" if top and not os.path.isdir(os.path.join(top, "openspec", "changes", key[1])) else None
    if c["archived"]: return "archived"
    if c["stage"] == "split": return "split"
    if entry.get("mode") == "stopped": return "stopped"
    return None

# 活卡（沒歸檔、不是 split、dispatch.json 不是 stopped）佔著的 pane：續接、代管（via）的卡共用同一個 pane 與 worktree，
# worktree_of 又是最後一筆勝出，所以 pane 上只要還有活卡，這個 pane 就不是孤兒，不管 worktree 現在算給誰。
live_panes = set()
for k, e in dispatch.items():
    key = tuple(k.split("/", 1)); c = card_by_key.get(key)
    if c is None or c["archived"] or c["stage"] == "split" or e.get("mode") == "stopped": continue
    live_panes.add(str(e.get("pane")))
    if e.get("via"): live_panes.add(str((dispatch.get("%s/%s" % (key[0], e["via"])) or {}).get("pane")))

orphans = []
for a in (agents or []):
    if str(a.get("pane_id")) in live_panes: continue
    key = next((k for k in (worktree_owner(p) for p in (a.get("cwd"), a.get("foreground_cwd")) if p) if k), None)
    reason = orphan_reason(key, a.get("pane_id")) if key else None
    if reason:
        orphans.append({"pane": a.get("pane_id"), "cwd": a.get("cwd"), "agent_status": a.get("agent_status"),
                        "repo": key[0], "slug": key[1], "reason": reason})
orphan_panes = {str(o["pane"]) for o in orphans}
unmatched = [{"name": a.get("terminal_title_stripped") or a.get("agent") or "", "pane": a.get("pane_id"),
              "agent_status": a.get("agent_status"), "cwd": a.get("cwd"), "workspace": a.get("workspace_id"),
              "orphan": str(a.get("pane_id")) in orphan_panes}
             for a in (agents or []) if str(a.get("pane_id")) not in matched_panes]
reported = {e["source"] for e in errors}
errors.extend({"source": p, "message": m} for p, m in unreadable.items() if p not in reported)
print(json.dumps({"generated_at": now, "scopes": scopes, "repo_paths": repo_paths, "cards": cards, "sessions": sessions, "unfiled": unfiled, "last_sync": last_sync, "unmatched_agents": unmatched, "orphans": orphans, "errors": errors,
                  "progress": progress, "legacy": legacy, "worktrees_skipped": worktrees}, ensure_ascii=False))
PY
}
