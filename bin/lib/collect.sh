#!/usr/bin/env bash
# opsx collect [--root <dir>] [--state <dir>]：看板唯一的資料來源，印一份 JSON，不寫檔（mr.sh 的 cache/ 除外）。
# 讀三處：<root>/*/openspec/changes/*/（含 archive/）、<state>/{dispatch.json,grants.toml,workspaces.toml,unfiled/*.md}、
# herdr agent list（只在 HERDR_ENV 設定時）與 glab / gh（經 mr_json）。specs/board-collect/spec.md。
#
# 輸出：{generated_at, scopes[{workspace, repos[]}], repo_paths{repo: 實體路徑}, cards[], unfiled[{slug, title, source, found}],
#       last_sync（sync.log 最後一行，沒有檔時 null）， unmatched_agents[], errors[{source,message}]}
# 每張卡：{repo, slug, title, kind, stage, section, since, waiting, dispatch, status, agent_status, mr, last_output, source, upstream, stale}
#   section ∈ 待處理 | 進行中 | 待指派 | 收件匣 | 已完成（收件匣＝沒派出、stage 還是 explore）；waiting.type ∈ 等待授權 | 等待決定 | 可以合併 | 終端機等待輸入
#
# gates.md 的格式（apply 步 5 寫、answer 改）：每個 gate 一段
#   ## <gate id>
#   type: approval | decision      action: push|mr|migrate|…（approval 才有）      status: open | answered
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
  local work; work="$(mktemp -d "${TMPDIR:-/tmp}/opsx-collect.XXXXXX")"
  trap 'rm -rf "$work"' RETURN

  # bash 只掃目錄，每張卡寫一行 TSV（repo、slug、dir、archived、stage、mr 檔）給下面那段 python 組 JSON。
  # stage 用 stage_of，MR 用 mr_json，不另算；這裡不 fork python，1000 張卡就是 1000 次啟動。mr_json 只對有 MR 的卡跑。
  # repo 的判準：<root>/<name>/openspec/changes 存在，而且 <name>/.git 是目錄。linked worktree 的 .git 是檔案，跳過，
  # 不然 Agentory-AI-langflow、*-wt-* 會被當成別的 repo。archive 只取最新 N 張，已完成不能無限長。
  local repo_dir repo d slug archived stage mrfile n=0 archive_cap="${OPSX_COLLECT_ARCHIVE_CAP:-30}" seen_archive real
  : > "$work/cards.tsv"; : > "$work/seen"; mkdir -p "$work/mr"
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
      d="${d%/}"; slug="$(basename "$d")"
      case "$d" in
        */changes/archive) continue ;;
        */changes/archive/*) seen_archive=$((seen_archive+1)); [ "$seen_archive" -le "$archive_cap" ] || continue
           archived=true; slug="${slug#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"; stage=archive ;;
        *) archived=false; stage="$(stage_name "${repo_dir%/}" "$slug")" ;;
      esac
      mrfile=""
      if [ "$archived" = false ] && st_mr_in_report "$d"; then n=$((n+1)); mrfile="$work/mr/$n.json"; mr_json "$d" > "$mrfile"; fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$slug" "$d" "$archived" "$stage" "$mrfile" >> "$work/cards.tsv"
    done
  done
  [ -f "$work/repos" ] || : > "$work/repos"; [ -f "$work/worktrees" ] || : > "$work/worktrees"

  # herdr：只在 herdr 內問；失敗記 errors，不中斷
  local herdr_err=""
  if [ -n "${HERDR_ENV:-}" ]; then
    herdr agent list > "$work/agents.json" 2>"$work/agents.err" || herdr_err="herdr agent list 失敗：$(head -c 200 "$work/agents.err")"
  else
    herdr_err="不在 herdr 內（HERDR_ENV 未設），agent 狀態不可得"
  fi

  # 讀卡的檔與全域狀態，組 JSON
  OPSX_C_WORK="$work" OPSX_C_STATE="$state" OPSX_C_HERDR_ERR="$herdr_err" python3 -I - <<'PY'
import datetime, json, os, re, sys, tomllib

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

FIELD = re.compile(r"^(type|action|status|問題|建議|選項|證據|風險|預設|已確認|answer):\s*(.*)$")

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

def one_liner(inbox):
    m = re.search(r"^## 一句話\s*\n+(.+?)$", inbox, re.M)
    return m.group(1).strip() if m else None

def frontmatter(inbox, key):
    m = re.search(r"^%s:\s*(.*)$" % key, inbox, re.M)
    return m.group(1).strip() or None if m else None

def kind_of(d):
    m = re.search(r"^kind:\s*(\S+)", read(os.path.join(d, ".openspec.yaml")), re.M)
    return m.group(1) if m else "dev"

def waiting_of(card, gates, agent_status):
    for g in gates:
        if g.get("status", "").strip() != "open": continue
        base = {"gate_id": g["id"], "question": g.get("問題"), "recommended": g.get("建議"), "evidence": g.get("證據"),
                "risk": g.get("風險"), "default_if_unanswered": g.get("預設"), "confirmed": g.get("已確認")}
        if g.get("type") == "approval":
            opts = ["這次", "這張卡", "這個 repo 永遠", "拒絕"]
            if g.get("action") == "merge": opts = ["這次", "這張卡", "拒絕"]   # merge 永遠不可長期授權，answer 會拒，按鈕就不要給
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
        return {"type": "可以合併", "action": "merge", "gate_id": None, "options": ["合併"], "question": "MR 五條件全綠", "recommended": "合併",
                "evidence": mr["url"], "risk": None, "default_if_unanswered": "留在進行中", "confirmed": None}
    if agent_status == "blocked":
        return {"type": "終端機等待輸入", "action": None, "gate_id": None, "options": ["開啟 pane", "停止", "重新指派"],
                "question": "agent 在終端機等輸入，板上沒有對應的 gate", "recommended": "開啟 pane", "evidence": None, "risk": "照規則不該發生：要授權的動作應寫 gate",
                "default_if_unanswered": "agent 停在那裡", "confirmed": None}
    return None

cards, matched_panes, legacy = [], set(), {}
now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
for line in read(os.path.join(work, "cards.tsv")).split("\n"):
    if not line: continue
    repo_, slug_, dir_, archived_, stage_, mrfile = line.split("\t")
    c = {"repo": repo_, "slug": slug_, "dir": dir_, "archived": archived_ == "true", "stage": stage_,
         "mr": json.loads(read(mrfile)) if mrfile else None}
    d = c["dir"]
    if c["mr"] and c["mr"].get("error"):
        errors.append({"source": "glab" if "glab" in c["mr"]["error"] else "gh", "message": "%s/%s：%s" % (repo_, slug_, c["mr"]["error"])})
    spec_yaml = read(os.path.join(d, ".openspec.yaml"))
    inbox = read(os.path.join(d, "inbox.md"))
    # 卡的資格：schema: opsx 或有 inbox.md。舊 spec-driven 的 change 只計數，不當卡（真 repo 裡有幾百張，會灌爆待指派）
    if not c["archived"] and not re.search(r"^schema:\s*opsx\s*$", spec_yaml, re.M) and not inbox.strip():
        legacy[repo_] = legacy.get(repo_, 0) + 1
        continue
    key = "%s/%s" % (c["repo"], c["slug"])
    disp = dispatch.get(key)
    if disp and disp.get("mode") == "stopped": disp = None
    agent_status = None
    if disp and agents is not None:
        hit = [a for a in agents if str(a.get("pane_id")) == str(disp.get("pane"))]
        agent_status = (hit[0].get("agent_status") or "unknown") if hit else "unknown"
        if hit: matched_panes.add(str(hit[0].get("pane_id")))
    gates = parse_gates(read(os.path.join(d, "gates.md"))) if not c["archived"] else []
    waiting = None if c["archived"] else waiting_of(c, gates, agent_status)
    if c["archived"] or c["stage"] == "archive": section = "已完成"
    elif waiting: section = "待處理"
    elif disp: section = "進行中"
    elif c["stage"] == "explore": section = "收件匣"
    else: section = "待指派"
    cards.append({
        "repo": c["repo"], "slug": c["slug"], "title": one_liner(inbox) or c["slug"], "kind": kind_of(d),
        "stage": c["stage"], "section": section,
        "since": frontmatter(inbox, "found") or (re.search(r"^created:\s*(\S+)", read(os.path.join(d, ".openspec.yaml")), re.M) or [None, None])[1],
        "waiting": waiting, "dispatch": disp, "status": load_json(os.path.join(d, "status.json"), None),
        "agent_status": agent_status, "mr": c["mr"], "last_output": None,
        "grants_repo": grants.get(c["repo"]), "path": d,
        "source": frontmatter(inbox, "source"), "upstream": frontmatter(inbox, "upstream"), "stale": frontmatter(inbox, "stale") == "true",
    })

order = {"待處理": 0, "進行中": 1, "待指派": 2, "收件匣": 3, "已完成": 4}
cards.sort(key=lambda x: (order[x["section"]], x["repo"], x["slug"]))
unfiled_dir = os.path.join(state, "unfiled")
unfiled = []
for name in sorted(os.listdir(unfiled_dir)) if os.path.isdir(unfiled_dir) else []:
    if not name.endswith(".md"): continue
    text = read(os.path.join(unfiled_dir, name))
    unfiled.append({"slug": name[:-3], "title": one_liner(text) or name[:-3], "source": frontmatter(text, "source"), "found": frontmatter(text, "found")})
last_sync = None
log_lines = [l for l in read(os.path.join(state, "sync.log")).split("\n") if l]
if log_lines:
    at_, created_, updated_, unchanged_, errors_, first_ = (log_lines[-1].split("\t") + [""] * 6)[:6]
    last_sync = {"at": at_, "created": int(created_), "updated": int(updated_), "unchanged": int(unchanged_), "errors": int(errors_), "first_error": first_}
unmatched = [{"name": a.get("terminal_title_stripped") or a.get("agent") or "", "pane": a.get("pane_id"),
              "agent_status": a.get("agent_status"), "cwd": a.get("cwd"), "workspace": a.get("workspace_id")}
             for a in (agents or []) if str(a.get("pane_id")) not in matched_panes]
print(json.dumps({"generated_at": now, "scopes": scopes, "repo_paths": repo_paths, "cards": cards, "unfiled": unfiled, "last_sync": last_sync, "unmatched_agents": unmatched, "errors": errors,
                  "legacy": legacy, "worktrees_skipped": worktrees}, ensure_ascii=False))
PY
}
