#!/usr/bin/env bash
# opsx merge <slug> [--repo <top>]：核准合併（看板「合併」按鈕背後的那支，herdr-board D5）。
# 它不自己跑 glab mr merge。它重驗五條件，把核准（MR 的 head sha）寫進受保護位置（bin/lib/authz.py，沙盒內寫不到），在 decisions.tsv 記一行，
# 然後叫那張卡的 agent「/babysit merge」去執行；grant-gate 只在 sha 相符、指令單獨一條、MR 號碼對時放行。核准綁 sha，不刪。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/mr.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/route.sh"

opsx_merge() {
  local slug="" top=""
  while [ $# -gt 0 ]; do
    case "$1" in --repo) top="$2"; shift 2 ;; --*) die "merge: 不認得的選項 $1" ;; *) [ -z "$slug" ] && slug="$1" || die "merge: 多餘的參數 $1"; shift ;; esac
  done
  [ -n "$slug" ] || die "merge: 用法 opsx merge <slug> [--repo <top>]"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "merge: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  local repo d; repo="$(basename "$top")"; d="$top/openspec/changes/$slug"
  [ -d "$d" ] || die "merge: 沒有這張卡：$d"
  refuse_if_handed "$repo" "$slug" merge
  st_mr_in_report "$d" || die "merge: $slug 的 report.md 沒有 MR 連結，還沒到合併"

  # 重驗五條件，一定重抓（快取是給看板每 5 秒拉的）
  local mr; mr="$(OPSX_MR_CACHE_TTL=0 mr_json "$d")"
  local verdict; verdict="$(printf '%s' "$mr" | "$OPSX_PY" -I -c '
import json,sys
m=json.load(sys.stdin)
if m["state"]=="ready": print("ok\t"+(m["head_sha"] or "")); sys.exit()
c=m["conditions"] or {}
bad=[k for k in ("opened","not_draft","no_conflicts","pipeline","threads") if not c.get(k)] or ["glab 讀不到"]
print("no\t"+m["state"]+"\t"+",".join(bad))')"
  case "$verdict" in
    ok*) ;;
    *) die "merge: $slug 的 MR 五條件沒全綠（$(printf '%s' "$verdict" | cut -f2)；沒過：$(printf '%s' "$verdict" | cut -f3)），不核准。用 /opsx-workflow:babysit 看怎麼了" ;;
  esac
  local sha; sha="$(printf '%s' "$verdict" | cut -f2)"
  [ -n "$sha" ] || die "merge: glab 沒回 MR 的 head sha，核准綁不到 commit，不核准"

  # 寫核准（綁 sha，不刪；見 grant-gate 的 merge_gate）到受保護位置，dispatch.json 只讀：卡一定要在 dispatch.json（要有 agent 去執行），
  # 而且不能是互動模式（互動模式沒有 grant-gate，合併會停在 pane 的權限框，看板上的按鈕永遠轉不完）
  local key="$repo/$slug" now; now="$(now_iso)"
  OPSX_M_KEY="$key" OPSX_M_SHA="$sha" OPSX_M_NOW="$now" OPSX_M_SD="$OPSX_STATE_DIR" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - <<'PY' || exit 2
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import authz, jsonfile
sd, key, sha, now = os.environ["OPSX_M_SD"], os.environ["OPSX_M_KEY"], os.environ["OPSX_M_SHA"], os.environ["OPSX_M_NOW"]
card = jsonfile.load(os.path.join(sd, "dispatch.json")).get(key)
if not card or card.get("mode") == "stopped":
    sys.exit("merge: %s 沒派出（不在 dispatch.json），沒有 agent 可以執行合併；先 opsx dispatch" % key)
if card.get("mode") == "interactive":
    sys.exit("merge: %s 是互動模式，沒有授權閘門，合併要在它的 pane 裡對 agent 說「/opsx-workflow:babysit merge」並自己按權限框" % key)
def put(d):
    c = d.setdefault(key, {}); c["merge_approved"] = sha; c["merge_approved_at"] = now
authz.update(sd, put)
PY
  log_row "$d" 你 已允許 "核准合併 ${sha}" "${sha} · $(st_mr_url "$d")"
  local route name via; route="$(card_route "$repo" "$slug")" || die "讀不懂 dispatch.json，不知道話要送給誰"; name="${route%%$'\t'*}"; via="${route#*$'\t'}"
  herdr agent prompt "$name" "/opsx-workflow:babysit merge ${sha}${via:+ $slug}" >/dev/null || die "merge: 核准已寫進 dispatch.json，但 herdr agent prompt 失敗；在 pane 裡對 agent 說 /opsx-workflow:babysit merge ${sha}"
  say "merge: $slug 核准合併 ${sha}，已叫 agent /opsx-workflow:babysit merge；它跑 glab mr merge 時閘門會放行（只放這個 sha、這條 MR）"
}
