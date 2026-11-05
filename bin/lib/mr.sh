#!/usr/bin/env bash
# MR 五條件，drive / collect / merge / grant-gate 共用（herdr-board D5、specs/board-collect）。
#   mr_json  <card dir>  印 {"url","state","head_sha","conditions":{opened,not_draft,no_conflicts,pipeline,threads},"blocked_on"}
#   mr_state <card dir>  印 ready | draft | conflicts | pipeline:<status> | threads:<n> | state:<s> | none（drive 用的短字串）
# 來源：report.md 的 ## MR 連結 → github.com 走 gh，其他走 glab。
# 快取：$OPSX_STATE_DIR/cache/mr-<slug>.json，OPSX_MR_CACHE_TTL 秒（預設 60，0 = 每次都抓）；抓不到不寫快取。

mr_json() { # <card dir>
  local d="$1" url slug ttl cache now mtime age raw forge iid
  url="$(st_mr_url "$d")"
  if [ -z "$url" ]; then
    printf '{"url": null, "state": "none", "head_sha": null, "conditions": null, "blocked_on": null}\n'; return
  fi
  slug="$(basename "$d")"; ttl="${OPSX_MR_CACHE_TTL:-60}"; cache="$OPSX_STATE_DIR/cache/mr-$slug.json"
  if [ "$ttl" -gt 0 ] && [ -f "$cache" ]; then
    now="$(date +%s)"; mtime="$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache")"; age=$((now - mtime))
    if [ "$age" -lt "$ttl" ]; then cat "$cache"; return; fi
  fi
  iid="$(printf '%s' "$url" | grep -oE '[0-9]+$')"
  case "$url" in
    *github.com*) forge=github; raw="$(gh pr view "$iid" --json state,isDraft,mergeable,statusCheckRollup,reviewThreads,headRefOid 2>/dev/null || true)" ;;
    *)            forge=gitlab; raw="$(glab mr view "$iid" -F json 2>/dev/null || true)" ;;
  esac
  local out
  out="$(OPSX_MR_RAW="$raw" python3 -I - "$url" "$forge" <<'PY'
import json, os, sys
url, forge = sys.argv[1], sys.argv[2]
raw = os.environ.get("OPSX_MR_RAW", "").strip()   # heredoc 占了 stdin，原始 JSON 走環境變數
out = {"url": url, "state": "none", "head_sha": None, "conditions": None, "blocked_on": None}
if not raw:
    print(json.dumps(out)); sys.exit()
try:
    d = json.loads(raw)
except json.JSONDecodeError:
    print(json.dumps(out)); sys.exit()
if forge == "github":
    bad = [c for c in d.get("statusCheckRollup") or [] if c.get("conclusion") not in (None, "SUCCESS", "NEUTRAL", "SKIPPED")]
    open_t = [t for t in d.get("reviewThreads") or [] if not t.get("isResolved")]
    c = {"opened": d.get("state") == "OPEN", "not_draft": not d.get("isDraft"),
         "no_conflicts": d.get("mergeable") != "CONFLICTING", "pipeline": not bad, "threads": not open_t}
    sha, ps, n, state = d.get("headRefOid"), "failed", len(open_t), d.get("state")
else:
    ps = (d.get("head_pipeline") or d.get("pipeline") or {}).get("status")
    n = d.get("unresolved_discussions_count")
    if n is None:
        n = 0 if d.get("blocking_discussions_resolved", True) else 1
    c = {"opened": d.get("state") == "opened", "not_draft": not (d.get("draft") or d.get("work_in_progress")),
         "no_conflicts": not d.get("has_conflicts"), "pipeline": ps is None or ps == "success", "threads": n == 0}
    sha, state = d.get("sha") or (d.get("diff_refs") or {}).get("head_sha"), d.get("state")
first = next((k for k in ("opened", "not_draft", "no_conflicts", "pipeline", "threads") if not c[k]), None)
short = {"opened": "state:%s" % state, "not_draft": "draft", "no_conflicts": "conflicts",
         "pipeline": "pipeline:%s" % ps, "threads": "threads:%d" % n, None: "ready"}[first]
out.update(state=short, head_sha=sha, conditions=c, blocked_on=first)
print(json.dumps(out))
PY
)"
  if [ -n "$raw" ] && [ "$ttl" -gt 0 ]; then
    mkdir -p "$(dirname "$cache")"; printf '%s\n' "$out" > "$cache.tmp" && mv "$cache.tmp" "$cache"
  fi
  printf '%s\n' "$out"
}

mr_state() { # <card dir>
  mr_json "$1" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["state"])'
}
