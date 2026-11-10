#!/usr/bin/env bash
# opsx answer <slug> [--sub <子>] --gate <id> [--grant this|card|repo] [--repo <top>] <text…>：回一個 gate。
# 先驗 gate，再把授權落檔（repo 寫 grants.toml；card 與 this 寫受保護位置 bin/lib/authz.py 的 grants / once，閘門用掉 once 就刪），
# 把 gates.md 那段改成 answered，在 decisions.tsv 記一行（log_row），最後 herdr agent prompt 送給 agent。卡沒派出就不送，agent 派出時會讀 gates.md。
# --sub：gates.md 與 decisions.tsv 換成 changes/<slug>/subs/<子>/ 的；子 change 跑在主 change 的 session、不在 dispatch.json，
# 所以授權、派出判斷與送話對象都照主 change，送話一律帶 [<slug>/<子>] 讓 session 轉給對的 subagent。
# 看板的「回它」按鈕背後就是這支；終端機打也一樣。specs/board-actions/spec.md、要求檔 §3.6 授權三級。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/route.sh"

opsx_answer() {
  local slug="" sub="" gate="" grant="" top="" text=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --sub) sub="$2"; shift 2 ;;
      --gate) gate="$2"; shift 2 ;;
      --grant) grant="$2"; shift 2 ;;
      --repo) top="$2"; shift 2 ;;
      --) shift; text+=("$@"); break ;;   # 之後全是文字（答案本身以 -- 開頭時用；server 一律這樣送）
      --*) die "answer: 不認得的選項 $1（答案以 -- 開頭請先放一個 --）" ;;
      *) if [ -z "$slug" ]; then slug="$1"; else text+=("$1"); fi; shift ;;
    esac
  done
  [ -n "$slug" ] && [ -n "$gate" ] && [ ${#text[@]} -gt 0 ] || die "answer: 用法 opsx answer <slug> [--sub <子>] --gate <id> [--grant this|card|repo] <text…>"
  case "$grant" in ""|this|card|repo) ;; *) die "answer: --grant 要是 this|card|repo，收到 $grant" ;; esac
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "answer: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  local repo d answer; repo="$(basename "$top")"; d="$top/openspec/changes/$slug"; answer="${text[*]}"
  [ -d "$d" ] || die "answer: 沒有這張卡：$d"
  if [ -n "$sub" ]; then
    d="$d/subs/$sub"
    [ -d "$d" ] || die "answer: $slug 底下沒有子 change：$d"
  fi
  [ -f "$d/gates.md" ] || die "answer: $slug${sub:+/$sub} 沒有 gates.md，沒有 gate 可回"
  refuse_if_handed "$repo" "$slug" answer
  mkdir -p "$OPSX_STATE_DIR"

  # 一段 python 做完驗證與所有檔案改動：失敗在哪一步就印哪一步，退出 2；成功印 "dispatched" 或 "undispatched"
  local result
  result="$(OPSX_A_DIR="$d" OPSX_A_GATE="$gate" OPSX_A_GRANT="$grant" OPSX_A_TEXT="$answer" OPSX_A_REPO="$repo" OPSX_A_SLUG="$slug" \
            OPSX_A_SD="$OPSX_STATE_DIR" OPSX_A_NOW="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - <<'PY'
import os, re, sys, tomllib
sys.path.insert(0, os.environ["OPSX_LIB"]); import authz, gatetype, jsonfile
e = os.environ
d, gate, grant, text, repo, slug, sd, now = (e["OPSX_A_DIR"], e["OPSX_A_GATE"], e["OPSX_A_GRANT"], e["OPSX_A_TEXT"],
                                             e["OPSX_A_REPO"], e["OPSX_A_SLUG"], e["OPSX_A_SD"], e["OPSX_A_NOW"])
key = "%s/%s" % (repo, slug)
ACTION_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")   # 要當 grants.toml 的 key 與 hook 的比對字串，只准這些字元

def fail(msg):
    print(msg, file=sys.stderr); sys.exit(2)

# 多行答案會在 gates.md 裡變成新欄位甚至新 gate（`ok\nstatus: open` 會把已答的 gate 重開），所以壓成一行
text = " ".join(text.splitlines()).strip()
if not text:
    fail("answer: 答案壓成一行後是空的")

gates_path = os.path.join(d, "gates.md")
src = open(gates_path, encoding="utf-8").read()
parts = re.split(r"(?m)^(?=## )", src)
def field_of(section, name):
    m = re.search(r"(?m)^%s:\s*(.*)$" % name, section); return m.group(1).strip() if m else ""
named = [i for i, p in enumerate(parts) if p.startswith("## ") and p.split("\n", 1)[0][3:].strip() == gate]
if not named:
    fail("answer: gates.md 裡沒有 gate「%s」（有：%s）" % (gate, ", ".join(p.split("\n", 1)[0][3:].strip() for p in parts if p.startswith("## ")) or "無"))
idx = next((i for i in named if field_of(parts[i], "status") == "open"), None)
if idx is None:
    fail("answer: gate「%s」不是 open（status: %s），不能再回" % (gate, "、".join(field_of(parts[i], "status") or "缺" for i in named)))
sec = parts[idx]
def field(name): return field_of(sec, name)
gtype, action = field("type"), field("action")
if grant and gatetype.normalize(gtype) != gatetype.APPROVAL:
    fail("answer: --grant 只對 type: approval 的 gate 有意義，「%s」是 %s" % (gate, gtype or "沒寫 type"))
if grant == "repo" and action == "merge":
    fail("answer: merge 永遠要人，不能給「這個 repo 永遠」")
if grant and not action:
    fail("answer: gate「%s」沒寫 action:，不知道要授權哪個動作" % gate)
if grant and not ACTION_RE.match(action):
    fail("answer: gate「%s」的 action「%s」不合格（只准 [a-z][a-z0-9_-]，最多 32 字），不能當授權的 key" % (gate, action))

dispatch_path = os.path.join(sd, "dispatch.json")
dispatch = jsonfile.load(dispatch_path)
dispatched = key in dispatch and dispatch[key].get("mode") != "stopped"
def add_card_grant(dd): gl = dd.setdefault(key, {}).setdefault("grants", []); action in gl or gl.append(action)
def add_once(dd): ol = dd.setdefault(key, {}).setdefault("once", []); action in ol or ol.append(action)
if grant == "repo":
    gp = os.path.join(sd, "grants.toml")
    try:
        g = tomllib.load(open(gp, "rb"))
    except FileNotFoundError:
        g = {}
    except tomllib.TOMLDecodeError as ex:
        fail("answer: grants.toml 壞了：%s" % ex)
    repos = g.get("repos", {}); repos.setdefault(repo, {})[action] = True
    # 只重寫 [repos."…"] 那些表；第一個 [repos. 之前的註解與別的表原樣留著
    try:
        old = open(gp, encoding="utf-8").read()
    except FileNotFoundError:
        old = "# 「這個 repo 永遠」那級的授權。每 repo 一個表：push / mr / migrate … 布林。merge 永遠不可寫。\n"
    head = re.split(r'(?m)^\[repos\.', old, maxsplit=1)[0].rstrip("\n")
    lines = [head] if head else []
    for r, acts in repos.items():
        lines.append('\n[repos."%s"]' % r)
        for a, v in acts.items():
            lines.append("%s = %s" % (a, "true" if v else "false"))
    tmp = gp + ".tmp"; open(tmp, "w", encoding="utf-8").write("\n".join(lines) + "\n"); os.replace(tmp, gp)
elif grant == "card":
    if not dispatched:
        fail("answer: 「這張卡」的授權要有 agent 才有意義，但 %s 沒派出（不在 dispatch.json）；用 --grant repo 或不帶 --grant" % key)
    authz.update(sd, add_card_grant)
elif grant == "this":
    # 「這次」也要留痕，不然 agent 重試還是被 deny：寫進 once，閘門用掉就刪
    if not dispatched:
        fail("answer: 「這次」的授權要有 agent 才有意義，但 %s 沒派出（不在 dispatch.json）" % key)
    authz.update(sd, add_once)

sec2 = re.sub(r"(?m)^status:\s*open\s*$", "status: answered", sec, count=1).rstrip("\n")
sec2 += "\nanswer: %s\nanswered_at: %s\n" % (text, now)
if grant: sec2 += "grant: %s\n" % grant
if idx + 1 < len(parts): sec2 += "\n"
parts[idx] = sec2
tmp = gates_path + ".tmp"; open(tmp, "w", encoding="utf-8").write("".join(parts)); os.replace(tmp, gates_path)

print("dispatched" if dispatched else "undispatched")
PY
)" || exit 2
  if [ -n "$grant" ]; then log_row "$d" 你 已允許 "$answer" "$gate · $grant"
  else log_row "$d" 你 已決定 "$answer" "$gate"; fi

  if [ "$result" = dispatched ]; then
    local route name via; route="$(card_route "$repo" "$slug")" || die "讀不懂 dispatch.json，不知道話要送給誰"; name="${route%%$'\t'*}"; via="${route#*$'\t'}"
    local prefix="${via:+[$slug] }"; [ -z "$sub" ] || prefix="[$slug/$sub] "
    herdr agent prompt "$name" "$prefix$answer" >/dev/null || die "answer: gates.md 與 decisions 已寫，但 herdr agent prompt 失敗；agent 下次讀 gates.md 會看到答案"
    say "answer: $slug 的 $gate 已回「${answer}」${grant:+（grant: ${grant}）}，已送進 agent"
  else
    say "answer: $slug 的 $gate 已回「${answer}」${grant:+（grant: ${grant}）}；這張卡沒派出，沒有 agent 可以通知，派出時它會讀 gates.md"
  fi
}
