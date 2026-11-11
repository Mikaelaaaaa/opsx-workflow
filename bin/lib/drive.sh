#!/usr/bin/env bash
# opsx drive <slug> --repo <top>：「開到可合併」的迴圈。dispatch 在背景跑它，pid 記在 dispatch.json。
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
  local max="${OPSX_DRIVE_MAX:-200}" poll="${OPSX_DRIVE_POLL:-300}" i=0 settled=0 watch="" watch_fp="" last_stage="" last_at=0 backoff=0

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
      if [ -z "$watch" ]; then   # 答案送進 agent 之前記基準指紋，答完驗「重做」有沒有動
        watch="$(drive_gate_open "$d")"; [ -z "$watch" ] || watch_fp="$(stage_fingerprint "$top" "$slug")"
      fi
      # 回 gate 時 opsx answer 自己會 prompt agent，所以等它開工再等它做完，才輪到 drive 送下一句。
      # 有 timeout：answer 寫完 gates.md 但 prompt 沒送成時 agent 不會開工，要回頭重讀 gates.md
      herdr_step "$slug" agent wait "$slug" --until working --timeout $((poll * 1000)) || return 0
      [ "$HERDR_STEP_OK" = 1 ] || continue
      herdr_step "$slug" agent wait "$slug" || return 0
      continue
    fi
    if [ -n "$watch" ]; then
      # shortcut: 答案的 prompt 沒送成時 agent 沒動，這裡會多開一個 gate；多一個 gate 給人看，升級時改成答完先確認 agent 開過工
      local ans wstage; ans="$(gate_field "$d" "$watch" answer)"; wstage="${watch#drive-}"; wstage="${wstage%-*}"
      case "$ans" in
        重做*)
          if [ "$(stage_fingerprint "$top" "$slug")" = "$watch_fp" ]; then
            write_stuck_gate "$d" "$wstage" "$repo" "$slug"; say "drive: $slug 重做 /opsx-workflow:$wstage 之後階段還是沒動，寫了 gate 等人"
            coordinate_kick "$slug"; watch=""; continue   # 新 gate 開著，回頭走 gate 分支，不送階段指令
          fi
          watch="" ;;
        *)
          say "drive: $slug 的 gate $watch 答「${ans}」，不是重做，drive 結束交回人"; coordinate_kick "$slug"; return 0 ;;
      esac
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
        # 同階段相鄰兩次送出之間至少隔 poll 秒；階段前進的那一輪不受限
        local gap
        if [ "$stage" = "$last_stage" ]; then gap=$((poll - ($(date +%s) - last_at))); [ "$gap" -le 0 ] || sleep "$gap"; fi
        say "drive: $slug → /opsx-workflow:$stage"
        local before sent_at; before="$(stage_fingerprint "$top" "$slug")"; sent_at="$(date +%s)"
        herdr_step "$slug" agent prompt "$slug" "/opsx-workflow:$stage $slug" --wait || return 0
        # prompt 已送、只是沒在時限內 settle：算一次送出（下一輪受間隔下限），但沒 settle 不驗
        if [ "$HERDR_STEP_OK" = 1 ] || [ "$HERDR_STEP_TIMEOUT" = 1 ]; then last_stage="$stage"; last_at="$sent_at"; fi
        [ "$HERDR_STEP_OK" = 1 ] || continue   # 沒送進去的不驗、不算一次送出（herdr_step 已經退避過）
        if [ "$(stage_fingerprint "$top" "$slug")" != "$before" ]; then backoff=0
        else
          case "$(pane_tail "$repo" "$slug")" in
            *rate_limit*|*"Usage limit reached"*|*"HTTP 429"*|*"API Error"*)
              # shortcut: 沒有 usage-limit-pause 的重置時間，從 poll 秒起每次翻倍、上限 3600 秒；有那張卡之後改等重置時間
              if [ "$backoff" -eq 0 ]; then backoff="$poll"; else backoff=$((backoff * 2 > 3600 ? 3600 : backoff * 2)); fi
              say "drive: $slug 送了 /opsx-workflow:$stage 之後 agent 立刻失敗（pane 尾巴有 API 錯誤），不重送、不寫 gate，退避 $backoff 秒"
              sleep "$backoff" ;;
            *)
              write_stuck_gate "$d" "$stage" "$repo" "$slug"; say "drive: $slug 送了 /opsx-workflow:$stage 之後階段沒動，寫了 gate 等人"
              coordinate_kick "$slug" ;;   # shell 附加寫的 gate 不經過 gate-timestamp hook
          esac
        fi ;;
      *) die "drive: 不認得的階段 $stage" ;;
    esac
  done
  say "drive: 跑滿 $max 輪，結束"
}

# 跑一個 herdr 呼叫。回 1 表示 pane 沒了、drive 該結束；其他情況回 0，HERDR_STEP_OK 說這次呼叫本身成不成功。
# 錯誤一律先等過再回，迴圈才不會在同一個錯誤上空轉。
herdr_step() { # <slug> <herdr args…>
  local slug="$1" err code; shift
  HERDR_STEP_OK=0; HERDR_STEP_TIMEOUT=0
  if err="$(herdr "$@" 2>&1 >/dev/null)"; then HERDR_STEP_OK=1; return 0; fi
  code="$(printf '%s' "$err" | jq -r '.error.code // empty' 2>/dev/null || true)"
  case "$code" in
    timeout)
      HERDR_STEP_TIMEOUT=1; return 0 ;;
    agent_prompt_stalled)
      # herdr 收下了，只是 5 秒內沒看到 agent 動（指令馬上出錯、hook 擋掉）。算送過，送出後的驗證才跑得到
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

pane_tail() { # <repo> <slug>：pane 最後 20 行壓成一行；pane 讀不到印空
  herdr pane read "$(dispatch_pane "$1" "$2")" 2>/dev/null | tail -20 | tr '\n' ' ' || true
}
drive_gate_open() { # <card dir>：第一個 open 的 drive-<stage>-<n> gate 的標題，沒有印空
  awk '/^## /{id = substr($0, 4)} /^status:[ \t]*open[ \t]*$/ && id ~ /^drive-[a-z]+-[0-9]+$/ {print id; exit}' "$1/gates.md"
}
gate_field() { # <card dir> <gate id> <欄位>：該 gate 的欄位值，沒有印空
  awk -v id="$2" -v k="$3" '/^## /{cur = (substr($0, 4) == id)} cur && index($0, k ":") == 1 {sub(/^[^:]*:[ \t]*/, ""); print; exit}' "$1/gates.md"
}

write_stuck_gate() { # <card dir> <stage> <repo> <slug>：gates.md 加一個 open 的 decision gate，id 不跟舊的 drive gate 撞
  local d="$1" stage="$2" repo="$3" slug="$4" n tail_text
  n=$(( $(grep -cE "^## drive-$stage-[0-9]+$" "$d/gates.md" 2>/dev/null || true) + 1 ))
  tail_text="$(pane_tail "$repo" "$slug")"
  {
    printf '\n## drive-%s-%s\n' "$stage" "$n"
    printf 'type: decision\nstatus: open\n'
    printf '問題: drive 卡在 /opsx-workflow:%s：送出後階段沒動。可能跑到別的 skill（同名的內建指令），或 agent 沒做完這一步、做完了但沒寫出下一階段要的檔\n' "$stage"
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
