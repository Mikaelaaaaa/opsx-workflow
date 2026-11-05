#!/usr/bin/env bash
# opsx drive <slug> --repo <top>：「開到可合併」的迴圈。dispatch 用 nohup 跑它，pid 記在 dispatch.json。
# 每一輪：看卡的狀態（跟 hook 同一張表）→ 該丟哪句就丟哪句 `herdr agent prompt … --wait` → 等 settled。
# 有開著的 gate → `herdr agent wait --until working` 阻塞到人在板上回；絕不定時 prompt 問「好了沒」。
# MR 開了 → 查 glab 五條件；全綠就停（merge 永遠人）；沒綠就 /babysit 一次，然後 sleep 等 CI。
# 要求檔 §3.6 自主程度表。

opsx_drive() {
  local slug="" top=""
  while [ $# -gt 0 ]; do
    case "$1" in --repo) top="$2"; shift 2 ;; *) [ -z "$slug" ] && slug="$1" || die "drive: 多餘的參數 $1"; shift ;; esac
  done
  [ -n "$slug" ] || die "drive: 要給 slug"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "drive: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  local repo d; repo="$(basename "$top")"; d="$top/openspec/changes/$slug"
  [ -d "$d" ] || die "drive: 沒有這張卡：$d"
  local max="${OPSX_DRIVE_MAX:-200}" poll="${OPSX_DRIVE_POLL:-300}" i=0

  while [ "$i" -lt "$max" ]; do
    i=$((i+1))
    dispatched "$repo" "$slug" || { say "drive: $repo/$slug 不在 dispatch.json（停了或被清掉），結束"; return 0; }
    if [ "$(st_open_gates "$d")" -gt 0 ]; then
      say "drive: $slug 有 $(st_open_gates "$d") 個 gate 等人，等板上回覆"
      herdr agent wait "$slug" --until working >/dev/null || true
      continue
    fi
    local stage; stage="$(stage_name "$top" "$slug")"
    case "$stage" in
      archive)
        say "drive: $slug 已 merged，結束"; return 0 ;;
      babysit)
        local mr; mr="$(mr_state "$d")"
        case "$mr" in
          ready) say "drive: $slug MR 五條件全綠，可以合併，停在這裡等人"; opsx_status_quiet "$top" "$slug" pr 5/5 "可以合併"; return 0 ;;
          none)  say "drive: $slug report.md 有 MR 但 glab 讀不到，等 $poll 秒再看"; sleep "$poll" ;;
          *)     say "drive: $slug MR 卡在 $mr → /babysit"; herdr agent prompt "$slug" "/babysit $slug" --wait >/dev/null || true; sleep "$poll" ;;
        esac ;;
      explore|grill|propose|apply|review|pr)
        say "drive: $slug → /$stage"
        herdr agent prompt "$slug" "/$stage $slug" --wait >/dev/null || true ;;
      *) die "drive: 不認得的階段 $stage" ;;
    esac
  done
  say "drive: 跑滿 $max 輪，結束"
}

dispatched() { # <repo> <slug>
  [ -f "$OPSX_STATE_DIR/dispatch.json" ] || return 1
  OPSX_KEY="$1/$2" python3 -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import json,os,sys
d=json.load(open(sys.argv[1])); sys.exit(0 if os.environ["OPSX_KEY"] in d else 1)
PY
}

# glab 五條件：report.md 有 MR URL ∧ opened 非 draft ∧ 無衝突 ∧ pipeline success ∧ 未解 threads 0
# 印 ready | draft | conflicts | pipeline:<status> | threads:<n> | none
mr_state() { # <card dir>
  local url; url="$(st_mr_url "$1")"
  [ -n "$url" ] || { printf none; return; }
  local iid; iid="$(printf '%s' "$url" | grep -oE '[0-9]+$')"
  local j
  case "$url" in
    *github.com*) j="$(gh pr view "$iid" --json state,isDraft,mergeable,statusCheckRollup,reviewThreads 2>/dev/null || true)"
      [ -n "$j" ] || { printf none; return; }
      printf '%s' "$j" | python3 -I -c '
import json,sys
d=json.load(sys.stdin)
if d.get("state")!="OPEN": print("state:"+str(d.get("state"))); sys.exit()
if d.get("isDraft"): print("draft"); sys.exit()
if d.get("mergeable")=="CONFLICTING": print("conflicts"); sys.exit()
bad=[c for c in d.get("statusCheckRollup") or [] if c.get("conclusion") not in (None,"SUCCESS","NEUTRAL","SKIPPED")]
if bad: print("pipeline:failed"); sys.exit()
open_t=[t for t in d.get("reviewThreads") or [] if not t.get("isResolved")]
print("threads:%d"%len(open_t) if open_t else "ready")' ;;
    *) j="$(glab mr view "$iid" -F json 2>/dev/null || true)"
      [ -n "$j" ] || { printf none; return; }
      printf '%s' "$j" | python3 -I -c '
import json,sys
d=json.load(sys.stdin)
if d.get("state")!="opened": print("state:"+str(d.get("state"))); sys.exit()
if d.get("draft") or d.get("work_in_progress"): print("draft"); sys.exit()
if d.get("has_conflicts"): print("conflicts"); sys.exit()
ps=(d.get("head_pipeline") or d.get("pipeline") or {}).get("status")
if ps and ps!="success": print("pipeline:"+ps); sys.exit()
n=d.get("unresolved_discussions_count")
if n is None:
    n=0 if d.get("blocking_discussions_resolved",True) else 1
if n: print("threads:%d"%n); sys.exit()
print("ready")' ;;
  esac
}

opsx_status_quiet() { # <top> <slug> <phase> <n/t> <label>
  ( cd "$1" && bash "$OPSX_ROOT/bin/opsx" status "$3" "$4" "$5" --change "$2" >/dev/null 2>&1 ) || true
}
