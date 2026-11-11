#!/usr/bin/env bash
# 一張卡的話送給哪個 herdr agent。dispatch.json 該卡的 herdr_name，沒有這個欄位就是 slug（舊條目）。
# 代管卡（有 via）沒有自己的 agent，話送到協調它的 pane；prompt 要帶 slug，pane 才知道轉給哪個 subagent。
# merge / answer / stop 共用。specs/opsx-chain/spec.md「送話給 herdr_name」。

# 印 "<herdr 名>\t<via>"，via 沒有時是空字串
card_route() { # <repo> <slug>
  OPSX_KEY="$1/$2" OPSX_SLUG="$2" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
except FileNotFoundError:
    d = {}
e = d.get(os.environ["OPSX_KEY"]) or {}
print("%s\t%s" % (e.get("herdr_name") or os.environ["OPSX_SLUG"], e.get("via") or ""))
PY
}

# dispatch.json 的 drive_pid 在 drive 被 SIGKILL 或重開機後會留著，pid 之後可能被別的行程重用，所以 kill 前要確認它是這張卡的 drive。
# 回 0：是這張卡的 drive；1：pid 不在；2：活著但不是（命令列放在 DRIVE_PID_CMD）。slug 後面接空格或結尾，retry 才不會中 retry-backoff；手動跑的 opsx drive <slug> 沒有 --repo，所以不比對它
drive_pid_state() { # <pid> <slug>
  kill -0 "$1" 2>/dev/null || return 1
  DRIVE_PID_CMD="$(ps -p "$1" -o command= 2>/dev/null)" || DRIVE_PID_CMD="（ps 讀不到）"
  case "$DRIVE_PID_CMD " in *"/opsx drive $2 "*) return 0 ;; esac
  return 2
}

# 續接後父卡那筆留著當紀錄（handed_to），它的 pane 已經歸子卡；再對它下指令會打到子卡的 agent，所以拒絕
refuse_if_handed() { # <repo> <slug> <command name>
  OPSX_KEY="$1/$2" OPSX_CMD="$3" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY' || exit 2
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
except FileNotFoundError:
    sys.exit(0)
e = d.get(os.environ["OPSX_KEY"]) or {}
if e.get("handed_to"):
    sys.exit("%s: %s 已經在 %s 交接給 %s，它的 pane 現在歸子卡；對子卡下指令"
             % (os.environ["OPSX_CMD"], os.environ["OPSX_KEY"], e.get("handed_at"), "、".join(e["handed_to"])))
PY
}
