#!/usr/bin/env bash
# opsx answer <slug> --gate <id> [--grant this|card|repo] [--repo <top>] <text…>：回一個 gate。
# 依序：驗 gate → 授權落檔（repo → grants.toml；card → dispatch.json；this 不記）→ gates.md 改 answered
# → decisions.tsv 一行 → herdr agent prompt（卡沒派出就跳過，gates.md 已改，agent 下次讀得到）。
# 看板的「回它」按鈕背後就是這支；終端機打也一樣。specs/board-actions/spec.md、要求檔 §3.6 授權三級。

opsx_answer() {
  local slug="" gate="" grant="" top="" text=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --gate) gate="$2"; shift 2 ;;
      --grant) grant="$2"; shift 2 ;;
      --repo) top="$2"; shift 2 ;;
      --*) die "answer: 不認得的選項 $1" ;;
      *) if [ -z "$slug" ]; then slug="$1"; else text+=("$1"); fi; shift ;;
    esac
  done
  [ -n "$slug" ] && [ -n "$gate" ] && [ ${#text[@]} -gt 0 ] || die "answer: 用法 opsx answer <slug> --gate <id> [--grant this|card|repo] <text…>"
  case "$grant" in ""|this|card|repo) ;; *) die "answer: --grant 要是 this|card|repo，收到 $grant" ;; esac
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "answer: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  local repo d answer; repo="$(basename "$top")"; d="$top/openspec/changes/$slug"; answer="${text[*]}"
  [ -d "$d" ] || die "answer: 沒有這張卡：$d"
  [ -f "$d/gates.md" ] || die "answer: $slug 沒有 gates.md，沒有 gate 可回"
  mkdir -p "$OPSX_STATE_DIR"

  # 一段 python 做完驗證與所有檔案改動：失敗在哪一步就印哪一步，退出 2；成功印 "dispatched" 或 "undispatched"
  local result
  result="$(OPSX_A_DIR="$d" OPSX_A_GATE="$gate" OPSX_A_GRANT="$grant" OPSX_A_TEXT="$answer" OPSX_A_REPO="$repo" OPSX_A_SLUG="$slug" \
            OPSX_A_SD="$OPSX_STATE_DIR" OPSX_A_NOW="$(now_iso)" python3 -I - <<'PY'
import json, os, re, sys, tomllib
e = os.environ
d, gate, grant, text, repo, slug, sd, now = (e["OPSX_A_DIR"], e["OPSX_A_GATE"], e["OPSX_A_GRANT"], e["OPSX_A_TEXT"],
                                             e["OPSX_A_REPO"], e["OPSX_A_SLUG"], e["OPSX_A_SD"], e["OPSX_A_NOW"])
key = "%s/%s" % (repo, slug)

def fail(msg):
    print(msg, file=sys.stderr); sys.exit(2)

# --- 1. 找 gate 那一段 ---
gates_path = os.path.join(d, "gates.md")
src = open(gates_path, encoding="utf-8").read()
parts = re.split(r"(?m)^(?=## )", src)
idx = next((i for i, p in enumerate(parts) if p.startswith("## ") and p.split("\n", 1)[0][3:].strip() == gate), None)
if idx is None:
    fail("answer: gates.md 裡沒有 gate「%s」（有：%s）" % (gate, ", ".join(p.split("\n", 1)[0][3:].strip() for p in parts if p.startswith("## ")) or "無"))
sec = parts[idx]
def field(name):
    m = re.search(r"(?m)^%s:\s*(.*)$" % name, sec); return m.group(1).strip() if m else ""
if field("status") != "open":
    fail("answer: gate「%s」不是 open（status: %s），不能再回" % (gate, field("status") or "缺"))
gtype, action = field("type"), field("action")
if grant and gtype != "approval":
    fail("answer: --grant 只對 type: approval 的 gate 有意義，「%s」是 %s" % (gate, gtype or "沒寫 type"))
if grant == "repo" and action == "merge":
    fail("answer: merge 永遠要人，不能給「這個 repo 永遠」")
if grant in ("card", "repo") and not action:
    fail("answer: gate「%s」沒寫 action:，不知道要授權哪個動作" % gate)

# --- 2. 授權落檔 ---
dispatch_path = os.path.join(sd, "dispatch.json")
try:
    dispatch = json.load(open(dispatch_path, encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    dispatch = {}
dispatched = key in dispatch and dispatch[key].get("mode") != "stopped"
if grant == "repo":
    gp = os.path.join(sd, "grants.toml")
    try:
        g = tomllib.load(open(gp, "rb"))
    except FileNotFoundError:
        g = {}
    except tomllib.TOMLDecodeError as ex:
        fail("answer: grants.toml 壞了：%s" % ex)
    repos = g.get("repos", {}); repos.setdefault(repo, {})[action] = True
    lines = ["# 「這個 repo 永遠」那級的授權。每 repo 一個表：push / mr / migrate … 布林。merge 永遠不可寫。"]
    for r, acts in repos.items():
        lines.append('\n[repos."%s"]' % r)
        for a, v in acts.items():
            lines.append("%s = %s" % (a, "true" if v else "false"))
    tmp = gp + ".tmp"; open(tmp, "w", encoding="utf-8").write("\n".join(lines) + "\n"); os.replace(tmp, gp)
elif grant == "card":
    if not dispatched:
        fail("answer: 「這張卡」的授權記在 dispatch.json，但 %s 沒派出；用 --grant repo 或不帶 --grant" % key)
    gl = dispatch[key].setdefault("grants", [])
    if action not in gl: gl.append(action)
    tmp = dispatch_path + ".tmp"; json.dump(dispatch, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=1); os.replace(tmp, dispatch_path)

# --- 3. gates.md：status → answered，附 answer / answered_at ---
sec2 = re.sub(r"(?m)^status:\s*open\s*$", "status: answered", sec, count=1).rstrip("\n")
sec2 += "\nanswer: %s\nanswered_at: %s\n" % (text, now)
if grant: sec2 += "grant: %s\n" % grant
if idx + 1 < len(parts): sec2 += "\n"
parts[idx] = sec2
tmp = gates_path + ".tmp"; open(tmp, "w", encoding="utf-8").write("".join(parts)); os.replace(tmp, gates_path)

# --- 4. decisions.tsv ---
note = text + ("（grant: %s）" % grant if grant else "")
with open(os.path.join(d, "decisions.tsv"), "a", encoding="utf-8") as f:
    f.write("%s\tyou\tanswer\t%s\t%s\n" % (now, gate, note.replace("\t", " ").replace("\n", " ")))
print("dispatched" if dispatched else "undispatched")
PY
)" || exit 2

  # --- 5. 回給 agent ---
  if [ "$result" = dispatched ]; then
    herdr agent prompt "$slug" "$answer" >/dev/null || die "answer: gates.md 與 decisions 已寫，但 herdr agent prompt 失敗；agent 下次讀 gates.md 會看到答案"
    say "answer: $slug 的 $gate 已回「${answer}」${grant:+（grant: ${grant}）}，已送進 agent"
  else
    say "answer: $slug 的 $gate 已回「${answer}」${grant:+（grant: ${grant}）}；這張卡沒派出，沒有 agent 可以通知，派出時它會讀 gates.md"
  fi
}
