#!/usr/bin/env bash
# MR 五條件，drive / collect / merge / grant-gate 共用（herdr-board D5、specs/board-collect）。
#   mr_json  <card dir>  印 {"url","state","head_sha","conditions":{opened,not_draft,no_conflicts,pipeline,threads},"blocked_on","error","created_at","merged_at"}
#   mr_state <card dir>  印 ready | draft | conflicts | pipeline:<status> | threads:<n> | state:<s> | none（drive 用的短字串）
# 來源：report.md 的 ## MR 連結。project 從 URL 解出來用 -R 指定（不靠 cwd：server 的 cwd 不是那個 repo）。
#   gitlab 的 https://<host>/<group>/<proj>/-/merge_requests/<iid> 變成 glab mr view <iid> -R <host>/<group>/<proj> -F json；
#   github 的 https://github.com/<owner>/<repo>/pull/<n> 變成 gh pr view <n> -R <owner>/<repo> --json <fields>。
# 快取：$OPSX_STATE_DIR/cache/mr-<sha1(url) 前 12 碼>.json（鍵是 URL，不同 repo 同名卡不會串），
#   OPSX_MR_CACHE_TTL 秒（預設 60，0 = 每次都抓）；抓不到不寫快取；寫入用 mktemp，並行不互撞。
#   OPSX_MR_STALE_OK=1（只有 collect 帶）：過期的快取照樣回，重抓丟到背景；沒有快取時照舊同步抓。
# gh 沒有未解 thread 的欄位（reviewThreads 不是 --json 的欄位），threads 條件用 reviewDecision != CHANGES_REQUESTED 近似。

# forge CLI 的時間上限：OPSX_MR_TIMEOUT 秒，沒設就不限時（只有 Stop hook 會設，它自己只有 10 秒）。
# 逾時先 SIGTERM、1 秒後 SIGKILL：gh / glab 是 Go 程式，runtime 接住 SIGALRM 不處理，alarm 殺不掉。
# 退出碼：124 逾時、127 找不到 perl 或那支 CLI；其餘照 CLI 的。
mr_forge() {
  [ -n "${OPSX_MR_TIMEOUT:-}" ] || { "$@"; return; }
  perl -e '
    my $t = shift; my $p = fork // die "fork: $!";
    if (!$p) { exec @ARGV or exit 127 }
    my $hit = 0;
    $SIG{ALRM} = sub { $hit++; kill($hit == 1 ? "TERM" : "KILL", $p); alarm 1 };
    alarm $t;
    my $r; do { $r = waitpid($p, 0) } while ($r < 0 && $!{EINTR});
    my $s = $?;
    exit($hit ? 124 : ($s & 127) ? 128 + ($s & 127) : $s >> 8);
  ' "$OPSX_MR_TIMEOUT" "$@"
}

mr_cache() { # <url>
  printf '%s/cache/mr-%s.json\n' "$OPSX_STATE_DIR" "$(printf '%s' "$1" | shasum | cut -c1-12)"
}

mr_age() { # <path> 印距 mtime 幾秒
  local mtime; mtime="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1")"
  echo $(( $(date +%s) - mtime ))
}

# 過期快取的背景重抓（只有 OPSX_MR_STALE_OK=1 的 collect 會走到）。一個 MR 同時只有一支：鎖是 <cache>.lock 目錄。
# setsid 讓它離開 collect 的 process group（server.py 逾時會 killpg collect）；三個 fd 都接 /dev/null，collect 的 stdout 才關得掉。
mr_refresh_bg() { # <card dir> <cache>
  local lock="$2.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    # shortcut: 120 s 死鎖上限，背景行程掛住時最多兩分鐘不重抓；要更準改成在 lock 目錄裡寫 pid
    [ "$(mr_age "$lock")" -ge 120 ] || return 0
    rmdir "$lock" 2>/dev/null; mkdir "$lock" 2>/dev/null || return 0
  fi
  # forge 的時間上限要比 120 s 死鎖上限短：鎖被當死鎖接手時，舊的那支已經被殺了，不會兩支一起掛著
  OPSX_MR_TIMEOUT=60 perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' bash "$OPSX_ROOT/bin/opsx" mr "$1" --refresh "$lock" </dev/null >/dev/null 2>&1 &
}

# opsx mr <card dir> [--refresh [<lock>]]：印 mr_json；--refresh 跳過快取重抓、寫快取；帶 <lock> 時最後放掉那個鎖（mr_refresh_bg 拿的）
opsx_mr() {
  local d="${1:?用法：opsx mr <card dir> [--refresh [<lock>]]}" rc=0
  case "${2:-}" in
    "") mr_json "$d" ;;
    --refresh)
      OPSX_MR_REFRESH=1 mr_json "$d" >/dev/null || rc=$?
      [ -z "${3:-}" ] || rmdir "$3"
      return "$rc" ;;
    *) die "opsx mr：不認得的參數 $2" ;;
  esac
}

mr_json() { # <card dir>
  local d="$1" url ttl cache raw rc=0 forge iid proj host path out tmp
  url="$(st_mr_url "$d")"
  if [ -z "$url" ]; then
    printf '{"url": null, "state": "none", "head_sha": null, "conditions": null, "blocked_on": null, "error": null, "created_at": null, "merged_at": null}\n'; return
  fi
  ttl="${OPSX_MR_CACHE_TTL:-60}"
  cache="$(mr_cache "$url")"
  if [ "$ttl" -gt 0 ] && [ -f "$cache" ] && [ "${OPSX_MR_REFRESH:-}" != 1 ]; then
    if [ "$(mr_age "$cache")" -lt "$ttl" ]; then cat "$cache"; return; fi
    if [ "${OPSX_MR_STALE_OK:-}" = 1 ]; then cat "$cache"; mr_refresh_bg "$d" "$cache"; return; fi
  fi
  iid="$(printf '%s' "$url" | grep -oE '[0-9]+$')"
  host="$(printf '%s' "$url" | sed -E 's#^https?://([^/]+)/.*#\1#')"
  case "$url" in
    *github.com/*) forge=github; proj="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/.*#\1#')"
      raw="$(mr_forge gh pr view "$iid" -R "$proj" --json state,isDraft,mergeable,mergeStateStatus,statusCheckRollup,reviewDecision,headRefOid,createdAt,mergedAt 2>/dev/null)" || rc=$? ;;
    *) forge=gitlab; path="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/(.*)/-/merge_requests/.*#\1#')"; proj="$host/$path"
      raw="$(mr_forge glab mr view "$iid" -R "$proj" -F json 2>/dev/null)" || rc=$? ;;
  esac
  out="$(OPSX_MR_RAW="$raw" OPSX_MR_RC="$rc" "$OPSX_PY" -I - "$url" "$forge" "$proj" "$iid" <<'PY'
import json, os, sys
url, forge, proj, iid = sys.argv[1:5]
raw = os.environ.get("OPSX_MR_RAW", "").strip()   # heredoc 占了 stdin，原始 JSON 走環境變數
out = {"url": url, "state": "none", "head_sha": None, "conditions": None, "blocked_on": None, "error": None, "created_at": None, "merged_at": None}
tool = "gh pr view %s -R %s" % (iid, proj) if forge == "github" else "glab mr view %s -R %s" % (iid, proj)
if not raw:
    rc = os.environ["OPSX_MR_RC"]
    if rc == "124":
        out["error"] = "%s 逾時（%s 秒）" % (tool, os.environ["OPSX_MR_TIMEOUT"])
    elif rc == "127":
        out["error"] = "%s 跑不起來：找不到 perl 或 %s" % (tool, tool.split()[0])
    else:
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
