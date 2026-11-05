#!/usr/bin/env bash
# opsx merge <slug> [--repo <top>]：核准合併（看板「合併」按鈕背後的那支，herdr-board D5）。
# 不自己跑 glab mr merge：重驗五條件 → dispatch.json 寫一次性核准（MR head sha）→ decisions.tsv 一行
# → herdr agent prompt "/babysit merge"，由那張卡的 agent 執行；grant-gate 看到 sha 相符才放行、放行即刪。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/mr.sh"

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
  st_mr_in_report "$d" || die "merge: $slug 的 report.md 沒有 MR 連結，還沒到合併"

  # 重驗五條件，一定重抓（快取是給看板每 5 秒拉的）
  local mr; mr="$(OPSX_MR_CACHE_TTL=0 mr_json "$d")"
  local verdict; verdict="$(printf '%s' "$mr" | python3 -I -c '
import json,sys
m=json.load(sys.stdin)
if m["state"]=="ready": print("ok\t"+(m["head_sha"] or "")); sys.exit()
c=m["conditions"] or {}
bad=[k for k in ("opened","not_draft","no_conflicts","pipeline","threads") if not c.get(k)] or ["glab 讀不到"]
print("no\t"+m["state"]+"\t"+",".join(bad))')"
  case "$verdict" in
    ok*) ;;
    *) die "merge: $slug 的 MR 五條件沒全綠（$(printf '%s' "$verdict" | cut -f2)；沒過：$(printf '%s' "$verdict" | cut -f3)），不核准。用 /babysit 看怎麼了" ;;
  esac
  local sha; sha="$(printf '%s' "$verdict" | cut -f2)"
  [ -n "$sha" ] || die "merge: glab 沒回 MR 的 head sha，核准綁不到 commit，不核准"

  # 寫一次性核准：卡一定要在 dispatch.json（要有 agent 去執行）
  local key="$repo/$slug" now; now="$(now_iso)"
  OPSX_M_KEY="$key" OPSX_M_SHA="$sha" OPSX_M_NOW="$now" python3 -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY' || exit 2
import json, os, sys
p = sys.argv[1]; key, sha, now = os.environ["OPSX_M_KEY"], os.environ["OPSX_M_SHA"], os.environ["OPSX_M_NOW"]
try:
    d = json.load(open(p, encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    d = {}
if key not in d or d[key].get("mode") == "stopped":
    print("merge: %s 沒派出（不在 dispatch.json），沒有 agent 可以執行合併；先 opsx dispatch" % key, file=sys.stderr); sys.exit(2)
d[key]["merge_approved"] = sha; d[key]["merge_approved_at"] = now
tmp = p + ".tmp"; json.dump(d, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=1); os.replace(tmp, p)
PY
  printf '%s\tyou\tmerge-approved\t%s\t%s\n' "$now" "$sha" "$(st_mr_url "$d")" >> "$d/decisions.tsv"
  herdr agent prompt "$slug" "/babysit merge" >/dev/null || die "merge: 核准已寫進 dispatch.json，但 herdr agent prompt 失敗；在 pane 裡對 agent 說 /babysit merge"
  say "merge: $slug 核准合併 ${sha}，已叫 agent /babysit merge；它跑 glab mr merge 時閘門會放行這一次"
}
