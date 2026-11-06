#!/usr/bin/env bash
# MR 五條件，drive / collect / merge / grant-gate 共用（herdr-board D5、specs/board-collect）。
#   mr_json  <card dir>  印 {"url","state","head_sha","conditions":{opened,not_draft,no_conflicts,pipeline,threads},"blocked_on","error","created_at","merged_at"}
#   mr_state <card dir>  印 ready | draft | conflicts | pipeline:<status> | threads:<n> | state:<s> | none（drive 用的短字串）
# 來源：report.md 的 ## MR 連結。project 從 URL 解出來用 -R 指定（不靠 cwd：server 的 cwd 不是那個 repo）。
#   gitlab 的 https://<host>/<group>/<proj>/-/merge_requests/<iid> 變成 glab mr view <iid> -R <host>/<group>/<proj> -F json；
#   github 的 https://github.com/<owner>/<repo>/pull/<n> 變成 gh pr view <n> -R <owner>/<repo> --json <fields>。
# 快取：$OPSX_STATE_DIR/cache/mr-<sha1(url) 前 12 碼>.json（鍵是 URL，不同 repo 同名卡不會串），
#   OPSX_MR_CACHE_TTL 秒（預設 60，0 = 每次都抓）；抓不到不寫快取；寫入用 mktemp，並行不互撞。
# gh 沒有未解 thread 的欄位（reviewThreads 不是 --json 的欄位），threads 條件用 reviewDecision != CHANGES_REQUESTED 近似。

mr_json() { # <card dir>
  local d="$1" url ttl cache now mtime age raw forge iid proj host path out tmp
  url="$(st_mr_url "$d")"
  if [ -z "$url" ]; then
    printf '{"url": null, "state": "none", "head_sha": null, "conditions": null, "blocked_on": null, "error": null, "created_at": null, "merged_at": null}\n'; return
  fi
  ttl="${OPSX_MR_CACHE_TTL:-60}"
  cache="$OPSX_STATE_DIR/cache/mr-$(printf '%s' "$url" | shasum | cut -c1-12).json"
  if [ "$ttl" -gt 0 ] && [ -f "$cache" ]; then
    now="$(date +%s)"; mtime="$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache")"; age=$((now - mtime))
    if [ "$age" -lt "$ttl" ]; then cat "$cache"; return; fi
  fi
  iid="$(printf '%s' "$url" | grep -oE '[0-9]+$')"
  host="$(printf '%s' "$url" | sed -E 's#^https?://([^/]+)/.*#\1#')"
  case "$url" in
    *github.com/*) forge=github; proj="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/.*#\1#')"
      raw="$(gh pr view "$iid" -R "$proj" --json state,isDraft,mergeable,mergeStateStatus,statusCheckRollup,reviewDecision,headRefOid,createdAt,mergedAt 2>/dev/null || true)" ;;
    *) forge=gitlab; path="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/(.*)/-/merge_requests/.*#\1#')"; proj="$host/$path"
      raw="$(glab mr view "$iid" -R "$proj" -F json 2>/dev/null || true)" ;;
  esac
  out="$(OPSX_MR_RAW="$raw" "$OPSX_PY" -I - "$url" "$forge" "$proj" "$iid" <<'PY'
import json, os, sys
url, forge, proj, iid = sys.argv[1:5]
raw = os.environ.get("OPSX_MR_RAW", "").strip()   # heredoc 占了 stdin，原始 JSON 走環境變數
out = {"url": url, "state": "none", "head_sha": None, "conditions": None, "blocked_on": None, "error": None, "created_at": None, "merged_at": None}
tool = "gh pr view %s -R %s" % (iid, proj) if forge == "github" else "glab mr view %s -R %s" % (iid, proj)
if not raw:
    out["error"] = "%s 沒回東西（沒登入、沒網路、或 project 不對）" % tool
    print(json.dumps(out)); sys.exit()
try:
    d = json.loads(raw)
except json.JSONDecodeError as e:
    out["error"] = "%s 回的不是 JSON：%s" % (tool, e)
    print(json.dumps(out)); sys.exit()
if forge == "github":
    checks_ok = True
    for c in d.get("statusCheckRollup") or []:
        if "conclusion" in c:   # CheckRun：要跑完而且過
            checks_ok = checks_ok and c.get("status") == "COMPLETED" and c.get("conclusion") in ("SUCCESS", "NEUTRAL", "SKIPPED")
        else:                   # StatusContext：只有 state
            checks_ok = checks_ok and c.get("state") == "SUCCESS"
    decision = d.get("reviewDecision") or ""
    c = {"opened": d.get("state") == "OPEN", "not_draft": not d.get("isDraft"),
         "no_conflicts": d.get("mergeable") != "CONFLICTING" and d.get("mergeStateStatus") != "DIRTY",
         "pipeline": checks_ok, "threads": decision != "CHANGES_REQUESTED"}
    sha, ps, n, state = d.get("headRefOid"), ("success" if checks_ok else "failed"), (1 if decision == "CHANGES_REQUESTED" else 0), d.get("state")
    out.update(created_at=d.get("createdAt"), merged_at=d.get("mergedAt"))
else:
    ps = (d.get("head_pipeline") or d.get("pipeline") or {}).get("status")
    n = d.get("unresolved_discussions_count")
    if n is None:
        n = 0 if d.get("blocking_discussions_resolved", True) else 1
    c = {"opened": d.get("state") == "opened", "not_draft": not (d.get("draft") or d.get("work_in_progress")),
         "no_conflicts": not d.get("has_conflicts"), "pipeline": ps is None or ps == "success", "threads": n == 0}
    sha, state = d.get("sha") or (d.get("diff_refs") or {}).get("head_sha"), d.get("state")
    out.update(created_at=d.get("created_at"), merged_at=d.get("merged_at"))
first = next((k for k in ("opened", "not_draft", "no_conflicts", "pipeline", "threads") if not c[k]), None)
short = {"opened": "state:%s" % state, "not_draft": "draft", "no_conflicts": "conflicts",
         "pipeline": "pipeline:%s" % ps, "threads": "threads:%d" % n, None: "ready"}[first]
out.update(state=short, head_sha=sha, conditions=c, blocked_on=first)
print(json.dumps(out))
PY
)"
  if [ -n "$raw" ] && [ "$ttl" -gt 0 ]; then
    mkdir -p "$(dirname "$cache")"
    tmp="$(mktemp "$cache.XXXXXX")" && printf '%s\n' "$out" > "$tmp" && mv -f "$tmp" "$cache" || rm -f "$tmp"
  fi
  printf '%s\n' "$out"
}

mr_state() { # <card dir>
  mr_json "$1" | "$OPSX_PY" -I -c 'import json,sys; print(json.load(sys.stdin)["state"])'
}
