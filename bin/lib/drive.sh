#!/usr/bin/env bash
# opsx drive <slug> --repo <top>：「開到可合併」的迴圈。dispatch 用 nohup 跑它，pid 記在 dispatch.json。
# 每一輪：看卡的狀態（跟 hook 同一張表）→ 該丟哪句就丟哪句 `herdr agent prompt … --wait` → 等 settled。
# 有開著的 gate → `herdr agent wait --until working` 阻塞到人在板上回；絕不定時 prompt 問「好了沒」。
# MR 開了 → 查 glab 五條件；全綠就停（merge 永遠人）；沒綠就 /babysit 一次，然後 sleep 等 CI。
# 要求檔 §3.6 自主程度表。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/mr.sh"   # mr_state：五條件，collect / merge / grant-gate 共用

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
        local mr; mr="$(OPSX_MR_CACHE_TTL=0 mr_state "$d")"   # 剛 /babysit 過，要看新值，不吃看板的 60 秒快取
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

opsx_status_quiet() { # <top> <slug> <phase> <n/t> <label>
  ( cd "$1" && bash "$OPSX_ROOT/bin/opsx" status "$3" "$4" "$5" --change "$2" >/dev/null 2>&1 ) || true
}
