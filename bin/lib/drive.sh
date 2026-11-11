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
  drive_register "$repo/$slug" || exit 2
  trap "drive_unregister $(printf '%q' "$repo/$slug")" EXIT   # 展開在設 trap 時：EXIT 跑時 local 已經沒了
  local max="${OPSX_DRIVE_MAX:-200}" poll="${OPSX_DRIVE_POLL:-300}" i=0 last="" sent=0 settled=0

  while [ "$i" -lt "$max" ]; do
    i=$((i+1))
    dispatched "$repo" "$slug" || { say "drive: $repo/$slug 不在 dispatch.json（停了或被清掉），結束"; return 0; }
    # dispatch 送完第一句不等就起 drive；herdr 不分辨是哪一輪，agent 還在跑時送同一句會排在後面，之後每句都差一輪
    if [ "$settled" = 0 ]; then herdr_step "$slug" agent wait "$slug" || return 0; settled=1; fi
    # 啟動時目錄在，所以現在不在只會是歸檔或被刪；stage_of 分不出這兩種和「還沒建殼」，不能靠它。放在 settle 之後：agent 跑 /archive 的那一輪也要看得到
    if [ ! -d "$d" ]; then
      if compgen -G "$top/openspec/changes/archive/????-??-??-$slug" >/dev/null; then say "drive: $slug 已歸檔，結束"
      else say "drive: $slug 卡目錄不見了（${d}），結束"; fi
      return 0
    fi
    if [ "$(st_open_gates "$d")" -gt 0 ]; then
      say "drive: $slug 有 $(st_open_gates "$d") 個 gate 等人，等板上回覆"
      # 回 gate 時 opsx answer 自己會 prompt agent，所以等它開工再等它做完，才輪到 drive 送下一句。
      # 有 timeout：answer 寫完 gates.md 但 prompt 沒送成時 agent 不會開工，要回頭重讀 gates.md
      herdr_step "$slug" agent wait "$slug" --until working --timeout $((poll * 1000)) || return 0
      [ "$HERDR_STEP_OK" = 1 ] || continue
      herdr_step "$slug" agent wait "$slug" || return 0
      last=""; sent=0
      continue
    fi
    local stage; stage="$(stage_name "$top" "$slug")"
    case "$stage" in
      archive)
        say "drive: $slug 已 merged，結束"; return 0 ;;
      split)
        say "drive: $slug 已拆成別的卡，結束"; return 0 ;;
      babysit)
        local mr; mr="$(OPSX_MR_CACHE_TTL=0 mr_state "$d")"   # 剛 /babysit 過，要看新值，不吃看板的 60 秒快取
        case "$mr" in
          ready) say "drive: $slug MR 五條件全綠，可以合併，停在這裡等人"; opsx_status_quiet "$top" "$slug" pr 5/5 "可以合併"; coordinate_kick "$slug"; return 0 ;;
          none)  say "drive: $slug report.md 有 MR 但 glab 讀不到，等 $poll 秒再看"; sleep "$poll" ;;
          *)     say "drive: $slug MR 卡在 $mr → /opsx-workflow:babysit"; herdr_step "$slug" agent prompt "$slug" "/opsx-workflow:babysit $slug" --wait || return 0; sleep "$poll" ;;
        esac ;;
      explore|grill|propose|apply|review|pr)
        if [ "$stage" = "$last" ] && [ "$sent" -ge 2 ]; then
          write_stuck_gate "$d" "$stage" "$repo" "$slug"; say "drive: $slug 送了兩次 /opsx-workflow:$stage 階段都沒動，寫了 gate 等人"
          coordinate_kick "$slug"   # shell 附加寫的 gate 不經過 gate-timestamp hook
          continue
        fi
        say "drive: $slug → /opsx-workflow:$stage"
        herdr_step "$slug" agent prompt "$slug" "/opsx-workflow:$stage $slug" --wait || return 0
        [ "$HERDR_STEP_OK" = 1 ] || continue   # 沒送進去的不算一次
        if [ "$stage" = "$last" ]; then sent=$((sent+1)); else last="$stage"; sent=1; fi ;;
      *) die "drive: 不認得的階段 $stage" ;;
    esac
  done
  say "drive: 跑滿 $max 輪，結束"
}

# 跑一個 herdr 呼叫。回 1 表示 pane 沒了、drive 該結束；其他情況回 0，HERDR_STEP_OK 說這次呼叫本身成不成功。
# 錯誤一律先等過再回，迴圈才不會在同一個錯誤上空轉。
herdr_step() { # <slug> <herdr args…>
  local slug="$1" err code; shift
  HERDR_STEP_OK=0
  if err="$(herdr "$@" 2>&1 >/dev/null)"; then HERDR_STEP_OK=1; return 0; fi
  code="$(printf '%s' "$err" | jq -r '.error.code // empty' 2>/dev/null || true)"
  case "$code" in
    timeout)
      return 0 ;;
    agent_prompt_stalled)
      # herdr 收下了，只是 5 秒內沒看到 agent 動（指令馬上出錯、hook 擋掉）。算送過，卡住保護才數得到
      say "drive: $slug 的 prompt 送進去了但 agent 沒動（agent_prompt_stalled）"; HERDR_STEP_OK=1; return 0 ;;
    agent_not_found)
      say "drive: $slug 的 pane 沒了（herdr agent_not_found），結束"; coordinate_kick "$slug"; return 1 ;;
    agent_blocked)
      say "drive: $slug 在終端機等待輸入，等人在 pane 處理完"
      coordinate_kick "$slug"
      herdr agent wait "$slug" --until working >/dev/null 2>&1 && herdr agent wait "$slug" >/dev/null 2>&1 || sleep "$poll"
      return 0 ;;
    *)
      say "drive: herdr $1 $2 回 ${code:-$err}，等 $poll 秒"; sleep "$poll"; return 0 ;;
  esac
}

write_stuck_gate() { # <card dir> <stage> <repo> <slug>：gates.md 加一個 open 的 decision gate，id 不跟舊的 drive gate 撞
  local d="$1" stage="$2" repo="$3" slug="$4" n tail_text
  n=$(( $(grep -cE "^## drive-$stage-[0-9]+$" "$d/gates.md" 2>/dev/null || true) + 1 ))
  tail_text="$(herdr pane read "$(dispatch_pane "$repo" "$slug")" 2>/dev/null | tail -20 | tr '\n' ' ' || true)"
  {
    printf '\n## drive-%s-%s\n' "$stage" "$n"
    printf 'type: decision\nstatus: open\n'
    printf '問題: drive 卡在 /opsx-workflow:%s：連送兩次，卡的階段都沒動。agent 沒做完這一步，或做完了但沒寫出下一階段要的檔\n' "$stage"
    # 選項會變成看板的回覆按鈕，按下去的字直接送給 agent，所以寫成 agent 照著做得到的話
    printf '選項: 重做 /opsx-workflow:%s 一次，做不完就把卡在哪寫進 gates.md (Recommended) | 跳過這一步，在 decisions.tsv 寫下原因再往下走 | 停在這裡，把卡在哪寫進 gates.md 等人\n' "$stage"
    printf '建議: 先看 pane（板上開 pane）再回；要整張卡停掉用板上的「停止」\n'
    printf '證據: pane 最後 20 行：%s\n' "$tail_text"
    printf '預設: drive 停在這裡等，不再送 /opsx-workflow:%s\n' "$stage"
  } >> "$d/gates.md"
}

# 手動 `opsx drive` 也要讓板上的「停止」殺得到，所以 pid 由 drive 自己寫，不靠 dispatch。
# 卡不在 dispatch.json 或已 stopped 時不寫（迴圈第一輪就會結束）。
drive_register() { # <repo/slug>
  [ -f "$OPSX_STATE_DIR/dispatch.json" ] || return 0
  OPSX_KEY="$1" OPSX_PID="$$" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
key, me = os.environ["OPSX_KEY"], int(os.environ["OPSX_PID"])
def put(d):
    card = d.get(key)
    if card is None or card.get("mode") == "stopped":
        return
    other = card.get("drive_pid")
    if other and other != me:
        try:
            os.kill(other, 0)
            sys.exit("drive: %s 已經有一支 drive 在跑（pid %d）。要換就先 kill %d 或 opsx stop" % (key, other, other))
        except ProcessLookupError:
            pass
    card["drive_pid"] = me
    if card.get("mode") == "drive":
        card["mode"] = "autopilot"
jsonfile.update(sys.argv[1], put)
PY
}
drive_unregister() { # <repo/slug>：只清自己的 pid，被 stop 或換人之後不動別人的
  [ -f "$OPSX_STATE_DIR/dispatch.json" ] || return 0
  OPSX_KEY="$1" OPSX_PID="$$" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
def put(d):
    card = d.get(os.environ["OPSX_KEY"])
    if card is not None and card.get("drive_pid") == int(os.environ["OPSX_PID"]):
        card["drive_pid"] = None
jsonfile.update(sys.argv[1], put)
PY
}
dispatch_pane() { # <repo> <slug>：dispatch.json 記的 pane id
  jq -r --arg k "$1/$2" '.[$k].pane // empty' "$OPSX_STATE_DIR/dispatch.json" 2>/dev/null || true
}
dispatched() { # <repo> <slug>
  [ -f "$OPSX_STATE_DIR/dispatch.json" ] || return 1
  OPSX_KEY="$1/$2" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import json,os,sys
d=json.load(open(sys.argv[1])); c=d.get(os.environ["OPSX_KEY"]); sys.exit(0 if c is not None and c.get("mode") != "stopped" else 1)
PY
}

# 要人的時刻叫 coordinate 馬上跑一輪（重派、通知人），不等 launchd 的 5 分鐘。失敗只記一行，drive 照原本的路走
coordinate_kick() { # <slug>
  local err
  err="$(opsx coordinate --kick 2>&1 >/dev/null)" || say "drive: $1 叫不動 opsx coordinate --kick：$err"
}

opsx_status_quiet() { # <top> <slug> <phase> <n/t> <label>
  ( cd "$1" && bash "$OPSX_ROOT/bin/opsx" status "$3" "$4" "$5" --change "$2" >/dev/null 2>&1 ) || true
}
