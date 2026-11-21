#!/usr/bin/env bash
# opsx dispatch <slug> --agent claude|codex --model <id> --mode interactive|autopilot --kind <kind> [--repo <path>]
# opsx dispatch --feature <feature> [--only <卡,…>] --agent … --mode …：一個 session 代管 workplan 一個 feature 現在能開工的主 change；
#   --only 只交出列出的卡，第一句照列出的順序給第一張（coordinate 用它濾掉 P2、把 P0 排前面）
# 把一張卡派出去：開 worktree，在 repo 掛的 workspace 開 herdr tab，agent start，送第一句 prompt，記進 dispatch.json。
# 要求檔 §3.6「派」、§3.6 自主程度表、§3.1。herdr 的每個呼叫都可以被 PATH 上的假 herdr 取代（tests/fakes）。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/note.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/agents-md.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/launch.sh"

opsx_dispatch() {
  local slug="" agent=claude model="" mode=autopilot kind="" top="" feature="" plan="" note="" has_note="" only=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --feature) feature="$2"; shift 2 ;;
      --only) only="$2"; shift 2 ;;
      --note) has_note=1; note="$(note_oneline "$2")"; shift 2 ;;
      --agent) agent="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --mode) mode="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --repo) top="$2"; shift 2 ;;
      --*) die "dispatch: 不認得的選項 $1" ;;
      *) [ -z "$slug" ] && slug="$1" || die "dispatch: 多餘的參數 $1"; shift ;;
    esac
  done
  if [ -n "$feature" ]; then
    [ -z "$slug" ] || die "dispatch: slug 與 --feature 只能給一個"
    slug="$feature"   # herdr agent 名、worktree、tab 都用 feature 名
  fi
  [ -z "$only" ] || [ -n "$feature" ] || die "dispatch: --only 只能跟 --feature 一起用"
  [ -n "$slug" ] || die "dispatch: 要給 slug"
  [ -z "$has_note" ] || [ -n "$note" ] || die "dispatch: --note 壓成一行後是空的"
  # 在找卡之前：`..` 與 archive 在每個有歸檔卡的 repo 都是 openspec/changes/ 底下的目錄
  printf '%s' "$slug" | grep -qE '^[a-z][a-z0-9_-]{0,31}$' || die "dispatch: slug 要符合 [a-z][a-z0-9_-]{0,31}（herdr agent 名）：$slug"
  [ -n "$feature" ] || [ "$slug" != archive ] || die "dispatch: archive 是 openspec/changes/ 底下放歸檔卡的資料夾，不是卡"
  if [ -z "$top" ]; then
    top="$(git_toplevel)"
    # 卡不在 cwd 的 repo（或 cwd 不在 repo 裡）時，到已登記 repo 找；--feature 的名字在 workplan，不是卡目錄
    if [ -z "$feature" ]; then
      [ -d "$top/openspec/changes/$slug" ] || top="$(find_card_repo "$slug")" || exit 2
      # cwd 的 repo 有卡也印：同名卡在別的 repo 時，看得到這次派的是哪一張
      say "dispatch: 卡在 $top"
    fi
  fi
  [ -n "$top" ] || die "dispatch: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  refuse_conflict_repo "$top" || exit 2
  case "$agent" in claude|codex) ;; *) die "dispatch: --agent 只收 claude|codex" ;; esac
  case "$mode" in interactive|autopilot) ;; drive) mode=autopilot ;; *) die "dispatch: --mode 只收 interactive|autopilot（drive 是 autopilot 的舊名）" ;; esac
  local card="$slug" repo; repo="$(basename "$top")"
  command -v herdr >/dev/null || die "dispatch: 找不到 herdr"
  ensure_dir "$OPSX_STATE_DIR"

  # herdr agent 只認名字（agent start <name>），新卡的名字 = slug。還在跑的條目用的 herdr 名（herdr_name，沒有就是它的 slug）
  # 跟這個 slug 一樣時，prompt 會送錯人，所以拒絕；代管卡的 herdr 名是協調它的 pane。
  # 單一續接交出去的條目（herdr 名已改成子卡、列在 handed_to 裡）只是紀錄，不算；fan-out 的父卡 pane 還活著、名字還是父卡，照算。
  # feature session 自己的條目是 <repo>/@<feature>，pane 活不活只看它：它還活著就算成員全停了，herdr 上 feature 名的 agent 也還在；
  # 它停了，同 repo 成員條目（via @<feature>）的 agent 也跟著不在，不算撞名
  local me_key="$repo/$slug"
  [ -z "$feature" ] || me_key="$repo/@$feature"
  OPSX_KEY="$me_key" OPSX_SLUG="$slug" OPSX_FEATURE="$feature" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY' || exit 2
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import chain, jsonfile
d = jsonfile.load(sys.argv[1]); me = os.environ["OPSX_KEY"]; slug = os.environ["OPSX_SLUG"]; feature = os.environ["OPSX_FEATURE"]
mine = d.get(me)
if mine and (chain.session_alive(mine) if feature else mine.get("mode") != "stopped"):
    sys.exit("dispatch: %s 已經派出去了，在 %s · %s · %s（%s 起）。要換人先 opsx stop %s" % (me, mine.get("workspace"), mine.get("tab"), mine.get("pane"), mine.get("started_at"), me.split("/", 1)[1]))
members = {k for k, v in d.items() if feature and k.startswith(me.split("/", 1)[0] + "/") and v.get("via") == "@" + feature}
clash = [k for k, v in d.items() if k != me and k not in members and v.get("mode") != "stopped" and (v.get("herdr_name") or k.split("/", 1)[1]) not in (v.get("handed_to") or []) and (v.get("herdr_name") or k.split("/", 1)[1]) == slug]
if clash:
    sys.exit("dispatch: herdr agent 名字就是 slug，而 %s 還在跑、用的 herdr 名也是 %s，herdr agent prompt 會送錯 agent。先 opsx stop 那張，或把這張卡改名" % ("、".join(clash), slug))
PY

  if [ -n "$feature" ]; then
    plan="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/chain.py" feature "$top" "$feature")" || exit 2
    # 這個 session 的成員條目（via @<feature>）是 stopped 就是人停的：不寫它的條目、不給它第一句。feature_plan 只管 workplan 上能不能開工
    plan="$(OPSX_PLAN="$plan" OPSX_ONLY="$only" OPSX_REPO="$repo" OPSX_FEATURE="$feature" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import chain, jsonfile
d = jsonfile.load(sys.argv[1]); e = os.environ
lines = e["OPSX_PLAN"].splitlines()
if e["OPSX_ONLY"]:
    by_slug = {line.split("\t")[0]: line for line in lines}
    want = e["OPSX_ONLY"].split(",")
    missing = [s for s in want if s not in by_slug]
    if missing:
        sys.exit("dispatch: --only 的 %s 不在 feature「%s」現在能開工的主 change（%s）裡"
                 % ("、".join(missing), e["OPSX_FEATURE"], "、".join(by_slug)))
    lines = [by_slug[s] for s in want]
keep, held = [], []
for line in lines:
    entry = d.get("%s/%s" % (e["OPSX_REPO"], line.split("\t")[0]))
    (held if chain.human_stopped(entry, e["OPSX_FEATURE"]) else keep).append(line)
if not keep:
    sys.exit("dispatch: feature「%s」能開工的主 change（%s）都被人停了；要接回其中一張用 opsx dispatch <slug>"
             % (e["OPSX_FEATURE"], "、".join(l.split("\t")[0] for l in held)))
print("\n".join(keep))
PY
)" || exit 2
    card="$(printf '%s' "$plan" | head -1 | cut -f1)"
  fi
  local d="$top/openspec/changes/$card"
  [ -d "$d" ] || die "dispatch: 沒有這張卡：$d"
  if [ -z "$feature" ]; then
    # 人停掉的 session 成員卡：session 還活著就交回 session（grill D1），它的 branch 可能正被 session 的 worktree checkout，單卡派會被 git 拒絕
    local session; session="$(OPSX_REPO="$repo" OPSX_SLUG="$slug" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import chain, jsonfile
d = jsonfile.load(sys.argv[1]); repo = os.environ["OPSX_REPO"]
mine = d.get("%s/%s" % (repo, os.environ["OPSX_SLUG"]))
if mine and mine.get("feature"):
    s = d.get("%s/@%s" % (repo, mine["feature"]))
    if s and chain.session_alive(s):
        print(mine["feature"])
PY
)"
    if [ -n "$session" ]; then send_to_session "$top" "$repo" "$slug" "$session" "$note"; return; fi
  fi

  # kind：沒給就從 .openspec.yaml 讀，再沒有就是 dev；寫回 .openspec.yaml
  if [ -z "$kind" ]; then kind="$(st_card_kind "$d")"; kind="${kind:-dev}"; fi
  case "$kind" in dev|bug-fix|refactoring|perf|experiment|ops|chore) ;; *) die "dispatch: kind 不在七種裡：$kind" ;; esac
  if grep -q '^kind:' "$d/.openspec.yaml" 2>/dev/null; then
    sed -i '' "s/^kind:.*/kind: $kind/" "$d/.openspec.yaml" 2>/dev/null || sed -i "s/^kind:.*/kind: $kind/" "$d/.openspec.yaml"
  else printf 'kind: %s\n' "$kind" >> "$d/.openspec.yaml"; fi

  # model：沒給就照 kind
  [ -n "$model" ] || model="$(default_model "$agent" "$kind")"

  # 不在 workplan 的卡先掛進去（workplan-attach「派工時補掛」）；feature session 的卡本來就在 workplan。
  # 掛不進去只警告，下面照 kind 的預設 branch 派，跟建卡時一樣（workplan-attach D11）
  if [ -z "$feature" ]; then
    "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/workplanwrite.py" attach "$top" "$card" "" "$(branch_user "$top")" "$kind" \
      || warn "dispatch: ${card} 沒掛進 workplan（上面是原因），照 kind 的預設 branch 派"
  fi
  # branch：workplan 有就用，沒有（repo 沒有 workplan）就 {type}/{slug}/{user}
  local branch; branch="$(workplan_branch "$top" "$card")"
  if [ -z "$branch" ]; then
    local t=feat; case "$kind" in bug-fix) t=fix ;; refactoring) t=refactor ;; ops|chore) t=chore ;; esac
    local user; user="$(branch_user "$top")"
    [ -n "$user" ] || die "dispatch: 分支尾巴沒有名字：OPSX_USER 沒設，git config user.name 是「$(git -C "$top" config user.name 2>/dev/null)」。設 OPSX_USER，或在這個 repo git config user.name"
    branch="$t/$slug/$user"
  fi

  # worktree：一卡一棵
  local wt="$top/.claude/worktrees/$slug" fresh=""
  if [ ! -d "$wt" ]; then
    fresh=1
    local used; used="$(git -C "$top" worktree list --porcelain | awk -v b="branch refs/heads/$branch" '/^worktree /{w=substr($0, 10)} $0 == b {print w}')"
    [ -z "$used" ] || die "dispatch: 分支 $branch 已經 checkout 在 ${used}$(held_by "$used")，不另開 worktree。那張卡在做就不用派；沒人在做就先收掉那棵 worktree"
    ensure_dir "$top/.claude/worktrees"
    if git -C "$top" show-ref --verify --quiet "refs/heads/$branch"; then git -C "$top" worktree add -q "$wt" "$branch"
    else
      # 主 checkout 可能不在 main、或還沒 pull 剛合併的依賴：有 remote 的 main 就從 fetch 後的它開。
      # 沒有 remote 追蹤分支的（本機 repo、測試）只能從主 checkout 的 HEAD 開
      local remote start=HEAD; remote="$(primary_remote "$top")"
      if git -C "$top" show-ref --verify --quiet "refs/remotes/$remote/main"; then
        git -C "$top" fetch -q "$remote" || die "dispatch: $top 的 git fetch $remote 失敗，不從舊的 $remote/main 開分支"
        start="$remote/main"
      fi
      git -C "$top" worktree add -q --no-track "$wt" -b "$branch" "$start"
    fi
  fi
  # 依賴沒裝好的標記放在 worktree 的 git-dir，跟著樹走：上次派工裝失敗或被殺在半路、卡又沒派出去時，重派看得到。卡派出去、gate 開好才刪
  local mark deps_fail="" real
  # 頂層不是這棵樹（沒有 .git 時 git 往上找到主 repo；.git 指向已刪的 git-dir 時找不到）：標記會寫錯地方，pane 也會開在壞掉的樹上
  real="$(cd "$wt" && pwd -P)"
  [ "$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null)" = "$real" ] \
    || die "dispatch: $wt 不是一棵能用的 git worktree（.git 不在或指向已刪的 git-dir）。先 cd $top && git worktree prune，或刪掉 $wt 再派"
  mark="$(git -C "$wt" rev-parse --absolute-git-dir)/opsx-deps-pending"
  # 只裝這次新建的樹：既有的 worktree 可能有人手動刪過或正在裝 node_modules
  if [ -n "$fresh" ] && [ -f "$wt/pnpm-lock.yaml" ]; then install_deps "$wt" "$mark"; fi
  if [ -f "$mark" ]; then deps_fail="$(cat "$mark")"; fi
  warn_untrusted "$top"
  warn_slots_full
  # codex 沒有 router hook：把同一批規則放進 worktree。worktree 已在也寫（重派可能換模式）
  if [ "$agent" = codex ]; then place_agents_md "$wt" "$mode" || die "dispatch: AGENTS.md 放不進 $wt"; fi

  # workspace：workspaces.toml 記的是 label（人看的，例 acmecorp-ai），開 agent 用 workspace list 換成 id；沒掛就開一個以 repo 為 label 的
  local ws ws_arg; ws="$(workspace_for "$repo")"
  if [ -n "$ws" ]; then
    ws_arg=(--workspace-label "$ws")
  else
    ws="$repo"
    ws_arg=(--workspace-create "$repo" "$top" --on-workspace-created dispatch_record_workspace)
  fi

  launch_args "$agent" "$model" "$mode" "$repo" "$slug" "$top"
  # 名字被占用：dispatch.json 沒記著（手動開的、或 stop 時 pane 沒關成）但 herdr 還有同名 agent，指出它在哪
  runtime_open "$me_key" --kind "$agent" "${ws_arg[@]}" --cwd "$wt" --label "$slug" -- "${LAUNCH_ARGS[@]}" \
    || die "dispatch: herdr agent start 失敗：herdr 已經有叫 ${slug} 的 agent，dispatch.json 沒記：${HERDR_TAKEN_AT}。關掉那個 pane 再派${deps_fail:+。$wt 的依賴沒裝好：$deps_fail}"
  local pane="$RUNTIME_PANE" tab="$RUNTIME_TAB" ws_id="$RUNTIME_WORKSPACE_ID"

  # dispatch.json
  # 一般卡一筆。feature session 另有自己的條目 <repo>/@<feature>（pane 層的欄位），每個能開工的主 change 再各一筆：
  # pane 照抄 session 的，herdr_name / feature 是 feature 名，via 指向 @<feature>
  [ -n "$plan" ] || plan="$card"$'\t'"$branch"$'\t'"$kind"
  local written
  written="$(OPSX_REPO="$repo" OPSX_FEATURE="$feature" OPSX_PLAN="$plan" OPSX_WS="$ws" OPSX_WSID="$ws_id" OPSX_TAB="$tab" OPSX_PANE="$pane" OPSX_AGENT="$agent" OPSX_MODEL="$model" OPSX_MODE="$mode" OPSX_WT="$wt" OPSX_AT="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" \
  "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import chain, jsonfile
e = os.environ
written = []
def put(d):
    repo, feature = e["OPSX_REPO"], e["OPSX_FEATURE"]
    pane_part = {"workspace": e["OPSX_WS"], "workspace_id": e["OPSX_WSID"], "tab": e["OPSX_TAB"], "pane": e["OPSX_PANE"], "agent": e["OPSX_AGENT"],
                 "model": e["OPSX_MODEL"], "mode": e["OPSX_MODE"], "worktree": e["OPSX_WT"], "started_at": e["OPSX_AT"], "drive_pid": None}
    rows = [line.split("\t") for line in e["OPSX_PLAN"].splitlines()]
    if feature:
        # 從判斷人停到這裡，dispatch 開 worktree、等 agent 起來，人可能又在板上停了一張：寫入前再查一次
        rows = [r for r in rows if not chain.human_stopped(d.get("%s/%s" % (repo, r[0])), feature)]
        if not rows:
            return
        d["%s/@%s" % (repo, feature)] = dict(pane_part)
        # 不在這次 plan 裡、沒停的成員（開了 MR 在等合併）也改抄新 pane，collect 才不會拿舊 pane 判它的 agent 不在
        for k, v in d.items():
            if k.startswith(repo + "/") and v.get("via") == "@" + feature and v.get("mode") != "stopped":
                v.update(pane_part)
    for card, branch, kind in rows:
        entry = dict(pane_part, kind=kind, branch=branch, grants=[], once=[])
        if feature:
            entry["herdr_name"] = entry["feature"] = feature
            entry["via"] = "@" + feature
        d["%s/%s" % (repo, card)] = entry
        written.append(card)
jsonfile.update(sys.argv[1], put)
print("\n".join(written))
PY
)" || exit 2
  if [ -z "$written" ]; then
    herdr tab close "$tab" >/dev/null 2>&1 || true
    die "dispatch: feature「${feature}」能開工的主 change 在派工途中都被人停了，tab 已關"
  fi
  card="$(printf '%s\n' "$written" | head -1)"; d="$top/openspec/changes/$card"
  local c via=""
  # feature session 的卡共用這棵樹，每張進 apply 前都要看得到依賴沒裝好
  if [ -n "$deps_fail" ]; then
    for c in $written; do write_install_gate "$top/openspec/changes/$c" "$wt" "$deps_fail"; done
    rm -f "$mark"
  fi

  # 第一句：照狀態
  local first; first="$(stage_name "$top" "$card")"
  st_sendable_stage "$top" "$card" "$first" || first=explore
  # 指示要在 agent 讀到第一句前就在卡上；放在前面每一步之後，失敗的派工不會留下指示，重跑也不會寫兩條
  if [ -n "$note" ]; then note_append "$d" "$note" || die "dispatch: 寫不進 $d/inbox.md 的派工指示，第一句沒送"; fi
  runtime_prompt "$me_key" "/opsx-workflow:$first $card" nowait >/dev/null
  [ -n "$feature" ] && via="（session ${feature}）"
  for c in $written; do
    log_row "$top/openspec/changes/$c" 你 已指派 "指派給 ${agent}${via}，第一句 /opsx-workflow:${first} ${card}" "${agent} · ${mode} · ${model}"
  done
  say "dispatch: $repo/$slug → $agent $model · $mode · kind $kind · $ws $pane · 第一句 /opsx-workflow:$first $card"

  if [ -n "$feature" ]; then
    # drive 對 herdr agent 名 = 卡名送話；session 代管多張卡，跟 fan-out 的代管卡一樣不起 drive
    say "dispatch: session $feature 代管 $(printf '%s\n' "$written" | tr '\n' ' ')；不起 drive"
  elif [ "$mode" = autopilot ]; then
    # pid 由 drive 自己寫進 dispatch.json（手動 opsx drive 也一樣），這裡只負責起
    local drivelog="$OPSX_STATE_DIR/drive-$repo-$slug.log"
    : | opsx_append "$drivelog" 2>/dev/null || die "dispatch: refuse to write through symlink: ${drivelog}（卡已派出，drive 沒起）"
    ( trap '' HUP; exec "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/safefile.py" exec-append "$drivelog" bash "$OPSX_ROOT/bin/opsx" drive "$slug" --repo "$top" ) < /dev/null > /dev/null 2>&1 &
    say "dispatch: drive 跑起來了（pid $!），log 在 $drivelog"
  fi
}

install_deps() { # <worktree> <標記檔>：裝不起來不擋派工，原因寫進標記檔，卡派出去後才開 gate
  local wt="$1" mark="$2" out
  if ! command -v pnpm >/dev/null; then
    say "dispatch: PATH 上找不到 pnpm，$wt 沒裝依賴，派出去後在卡上開 gate"
    printf 'PATH 上找不到 pnpm\n' > "$mark"
    return 0
  fi
  # 開跑前就留標記：dispatch 在 install 途中被殺（看板 120 秒逾時）時沒機會寫失敗原因
  printf 'pnpm install 沒跑完（dispatch 在安裝途中被停）\n' > "$mark"
  say "dispatch: 在 $wt 跑 pnpm install --frozen-lockfile"
  # --frozen-lockfile：鎖檔對不上就失敗，不讓新分支一開就有改過的 pnpm-lock.yaml
  # shortcut: 沒有時限，registry 卡住時 dispatch 跟著等、coordinate 那一輪也停住；量到最大的 pnpm repo 實際要裝幾秒，或 coordinate 真的被卡過一輪，就加 timeout，逾時照 install 失敗開 gate
  if out="$(pnpm --dir "$wt" install --frozen-lockfile < /dev/null 2>&1)"; then rm -f "$mark"; say "dispatch: 依賴裝好了"; return 0; fi
  # \r 也換掉：看板用 Python 讀 gates.md 時把 \r 當換行，依賴的安裝腳本印的字會變成假的 gate 欄位
  out="$(printf '%s\n' "$out" | tail -10 | tr '\r\n' '  ')"
  say "dispatch: pnpm install 失敗，派出去後在卡上開 gate：$out"
  printf 'pnpm install --frozen-lockfile 失敗：%s\n' "$out" > "$mark"
}

write_install_gate() { # <card dir> <worktree> <reason>：同一張卡再寫時 id 加流水號，不跟舊的撞
  local d="$1" wt="$2" why="$3" id=install-deps n q cmd
  # 取已有的最大編號（install-deps 算 1），不數題數：前面的題被手動刪掉時不會撞 id。卡上還沒有 gates.md 時 awk 讀空的 stdin，照樣印 0；cat 的失敗在 pipefail 下用 || true 接住
  n=$(cat "$d/gates.md" 2>/dev/null | awk '/^## install-deps$/ { if (m < 1) m = 1 } /^## install-deps-[0-9]+$/ { k = substr($0, 17) + 0; if (k > m) m = k } END { print m + 0 }' || true)
  [ "$n" -eq 0 ] || id="install-deps-$((n + 1))"
  printf -v q '%q' "$wt"
  # 不建議刪 node_modules：使用者可能已經自己裝好（CLAUDE.md §7 不刪除重裝）
  cmd="cd $q && pnpm install --frozen-lockfile"
  {
    printf '\n## %s\n' "$id"
    # blocks-from: apply：卡寫出 tasks.md 前 stop hook、drive、看板都不當它在等人（stage.sh st_gates_file_count）
    printf 'type: decision\nstatus: open\nneeds: run\nblocks-from: apply\nopened_at: %s\n' "$(now_iso)"
    printf '問題: dispatch 沒裝好 %s 的依賴，你自己裝嗎？\n' "$wt"
    printf '已確認: 卡照樣派出去了；%s\n' "$why"
    printf '選項: 我在終端機裝好了 (Recommended) | 先不裝，照樣往下做\n'
    printf '建議: %s\n' "$cmd"
    printf '證據: %s\n' "$why"
    printf '風險: 不裝的話 apply 跑測試時缺依賴\n'
    printf '預設: explore／grill／propose 照常往下；卡寫出 tasks.md 時還沒回，就停在 apply 等你\n'
  } >> "$d/gates.md"
}

send_to_session() { # <top> <repo> <slug> <feature> <note>：人停的成員卡交回活著的 session，不開 pane
  local top="$1" repo="$2" slug="$3" feature="$4" note="$5" d="$1/openspec/changes/$3" first
  first="$(stage_name "$top" "$slug")"
  st_sendable_stage "$top" "$slug" "$first" || die "dispatch: $repo/$slug 現在的階段是 ${first:-（算不出來）}，不能交回 session ${feature}"
  if [ -n "$note" ]; then note_append "$d" "$note" || die "dispatch: 寫不進 $d/inbox.md 的派工指示，沒送給 session"; fi
  runtime_prompt "$repo/@$feature" "[$slug] /opsx-workflow:$first $slug" nowait >/dev/null || die "dispatch: 送不到 session ${feature}，$repo/$slug 仍是 stopped"
  # 送到了才清 stopped；pane 層的欄位重抄 session 條目，舊 pane 不會被拿去送話
  OPSX_KEY="$repo/$slug" OPSX_SESSION="$repo/@$feature" OPSX_AT="$(now_iso)" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
def put(d):
    e, s = d[os.environ["OPSX_KEY"]], d[os.environ["OPSX_SESSION"]]
    for k in ("workspace", "workspace_id", "tab", "pane", "worktree", "agent", "model", "mode"):
        e[k] = s[k]
    e["started_at"] = os.environ["OPSX_AT"]
    e.pop("stopped_at", None)
    e.pop("pane_closed_at", None)
jsonfile.update(sys.argv[1], put)
PY
  log_row "$d" 你 已指派 "交回 session ${feature}，送 [${slug}] /opsx-workflow:${first} ${slug}" "session ${feature}"
  say "dispatch: $repo/$slug 交回 session ${feature}，送 [${slug}] /opsx-workflow:${first} ${slug}；不開 pane"
}

# 活著的 pane 已達同時上限時印一行警告，照派：人按的派是明確決定，排隊只管協調者自動派（specs/dispatch-concurrency）。
# 數法與上限跟協調者共用 coordinate.py
warn_slots_full() {
  # 這只是警告，不擋派工。數不成的原因也印 stdout：看板派工成功時只顯示 stdout
  OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR" <<'PY' || true
import os, subprocess, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import coordinate, jsonfile, runtime
state = sys.argv[1]
p = subprocess.run(runtime.list_agents(), capture_output=True, text=True)
if p.returncode != 0:
    print("dispatch: 數不出名額：herdr agent list 失敗（rc %d）" % p.returncode)
    sys.exit(0)
try:
    agents = coordinate.parse_agents(p.stdout)
    limit = coordinate.read_max_working(os.path.join(state, "max-working"))
except coordinate.CoordinateError as e:
    print("dispatch: 不數名額：%s" % e)
    sys.exit(0)
n = len(coordinate.live_panes(jsonfile.load(os.path.join(state, "dispatch.json")), agents))
if n >= limit:
    print("dispatch: 已有 %d/%d 個 pane" % (n, limit))
PY
}

find_card_repo() { # <slug>：已登記 repo（跟 collect、sync 同一份清單）裡剛好一個有 openspec/changes/<slug>/ 就印它的路徑，否則說明原因、退出非 0
  OPSX_SLUG="$1" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "${OPSX_CODE_ROOT:-$HOME/code}" "$OPSX_STATE_DIR" <<'PY'
import os, pathlib, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import sync
slug = os.environ["OPSX_SLUG"]
try:
    repos, conflicts, _, _ = sync.scan_repos(pathlib.Path(sys.argv[1]), sync.source_paths(pathlib.Path(sys.argv[2])))
except ValueError as e:
    sys.exit("opsx: dispatch: sources.toml 壞了，找不了別的 repo：%s" % e)
clashes = [sync.conflict_message(n, ps) for n, ps in conflicts.items() if any((p / "openspec" / "changes" / slug).is_dir() for p in ps)]
hits = sorted(str(p) for p in repos.values() if (p / "openspec" / "changes" / slug).is_dir())
if clashes:
    hint = "".join("；%s 也有這張卡，可以用 --repo %s 派" % (h, h) for h in hits)
    sys.exit("opsx: dispatch: %s 在同名的 repo 裡，不派：%s%s" % (slug, "；".join(clashes), hint))
if not hits:
    sys.exit("opsx: dispatch: 沒有這張卡：%s（cwd 的 repo 與 %d 個已登記 repo 的 openspec/changes/ 都沒有）" % (slug, len(repos)))
if len(hits) > 1:
    sys.exit("opsx: dispatch: %s 在 %d 個 repo 都有，給 --repo 指定一個：%s" % (slug, len(hits), "、".join(hits)))
print(hits[0])
PY
}
refuse_conflict_repo() { # <top>：top 的名字是同名衝突的名字、或已是清單裡另一個路徑的 repo 名，就說衝突、退出非 0。cwd 與 --repo 決定的 top 也要擋：dispatch.json 與授權以 repo 名為 key
  OPSX_TOP="$1" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "${OPSX_CODE_ROOT:-$HOME/code}" "$OPSX_STATE_DIR" <<'PY'
import os, pathlib, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import sync
try:
    sources = sync.source_paths(pathlib.Path(sys.argv[2]))
except ValueError as e:
    print("opsx: dispatch: %s" % sync.sources_message(e), file=sys.stderr)
    sources = []
repos, conflicts, _, _ = sync.scan_repos(pathlib.Path(sys.argv[1]), sources)
top = os.environ["OPSX_TOP"]
name = os.path.basename(top)
if name in conflicts:
    sys.exit("opsx: dispatch: %s 是同名的 repo，不派：%s" % (top, sync.conflict_message(name, conflicts[name])))
if name in repos and not os.path.samefile(repos[name], top):
    sys.exit("opsx: dispatch: %s 跟已登記的 %s 同名（repo 名 %s），不派；把其中一個資料夾改名" % (top, repos[name], name))
PY
}
workplan_branch() { wp_pr_field "$1" "$2" branch; } # <top> <slug>：印 workplan 裡這張卡所屬 PR 的 branch，沒有就空
held_by() { # <worktree>：印 dispatch.json 裡 worktree 指向它的條目（「（key · pane …）」），沒有就空。兩邊路徑先 realpath 再比
  [ -f "$OPSX_STATE_DIR/dispatch.json" ] || return 0
  OPSX_WT="$1" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
wt = os.path.realpath(os.environ["OPSX_WT"])
hits = ["%s · pane %s" % (k, v.get("pane")) for k, v in jsonfile.load(sys.argv[1]).items() if v.get("worktree") and os.path.realpath(v["worktree"]) == wt]
if hits:
    print("（%s）" % "；".join(hits))
PY
}
workspace_for() { # <repo>：印 workspaces.toml 記的 label（或 id），沒有就空
  [ -f "$OPSX_STATE_DIR/workspaces.toml" ] || return 0
  OPSX_REPO="$1" "$OPSX_PY" -I - "$OPSX_STATE_DIR/workspaces.toml" <<'PY'
import os, sys, tomllib
try:
    print(tomllib.load(open(sys.argv[1], "rb")).get("repos", {}).get(os.environ["OPSX_REPO"], ""))
except tomllib.TOMLDecodeError as e:
    sys.exit("dispatch: workspaces.toml 壞了：%s" % e)
PY
}
# runtime_open 的 --on-workspace-created：新 workspace 一建好就記 label，在開 tab 之前。
# 早於 create 記，create 失敗後每次派工都找不到這個 label；晚到 agent 起來才記，開 agent 失敗一次重派就多開一個同名 workspace
dispatch_record_workspace() { # <label> <workspace id>
  grep -q '^\[repos\]' "$OPSX_STATE_DIR/workspaces.toml" 2>/dev/null || printf '\n[repos]\n' | opsx_append "$OPSX_STATE_DIR/workspaces.toml" || die "dispatch: 寫不進 $OPSX_STATE_DIR/workspaces.toml"   # 第二台機器沒跑過 init 時檔案是空的
  printf '"%s" = "%s"\n' "$1" "$1" | opsx_append "$OPSX_STATE_DIR/workspaces.toml" || die "dispatch: 寫不進 $OPSX_STATE_DIR/workspaces.toml"
  say "dispatch: 新 workspace ${1}（${2}）記進 workspaces.toml"
}
