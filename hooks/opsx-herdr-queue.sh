#!/usr/bin/env bash
# PostToolUse(Bash)：`opsx chain` 跑完後，執行它寫在 $OPSX_STATE_DIR/herdr-queue/<repo>-<子卡>.tsv 的 herdr 動作。
# 派工 session 的沙盒擋了 herdr socket，hook 不在沙盒裡，所以續接的 rename / prompt / drive 由這裡代做（grill D5）。
# 每行 <動作>\t<參數1>\t<參數2>：rename <舊名> <新名> · prompt <agent> <文字> · drive <slug> <repo top>。
# 依序執行；任一步失敗就停，佇列改名 .failed 留著，子卡 decisions.tsv（log_row）記哪一步、herdr 說了什麼。specs/opsx-chain/spec.md。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/common.sh"   # log_row 用到 die、now_iso
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/log.sh"
cmd="$(hook_cmd)"
printf '%s' "$cmd" | grep -qE '(^|\s|&&|;)opsx\s+chain(\s|$)' || exit 0
top="$(repo_top)"
[ -n "$top" ] || exit 0
qd="$OPSX_STATE_DIR/herdr-queue"
repo="$(repo_name)"
[ -d "$qd" ] || exit 0

failures=""
for q in "$qd/$repo"-*.tsv; do
  [ -f "$q" ] || continue
  run="$q.running"
  mv "$q" "$run" 2>/dev/null || continue   # 另一支 hook 先拿走了
  child="$(basename "$q" .tsv)"; child="${child#"$repo"-}"
  card="$top/openspec/changes/$child"
  ok=1
  while IFS=$'\t' read -r op a b; do
    case "$op" in
      rename) out="$(herdr agent rename "$a" "$b" 2>&1)" || ok=0 ;;
      prompt) out="$(herdr agent prompt "$a" "$b" 2>&1)" || ok=0 ;;
      drive)
        nohup bash "$OPSX_ROOT/bin/opsx" drive "$a" --repo "$b" >> "$OPSX_STATE_DIR/drive-$repo-$a.log" 2>&1 &
        pid=$!
        out="$(OPSX_KEY="$repo/$a" OPSX_PID="$pid" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY' 2>&1
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import jsonfile
def put(d): d[os.environ["OPSX_KEY"]]["drive_pid"] = int(os.environ["OPSX_PID"])
jsonfile.update(sys.argv[1], put)
PY
)" || ok=0 ;;
      *) out="佇列裡有不認得的動作：$op"; ok=0 ;;
    esac
    if [ "$ok" -eq 0 ]; then
      out="$(log_cell "$out")"
      [ -d "$card" ] && log_row "$card" 系統 已指派 "續接的 herdr 動作失敗：$op $a → ${out}" "$q.failed"
      failures+="$child 的 $op 失敗：${out}；"
      mv "$run" "$q.failed"
      break
    fi
  done < "$run"
  [ "$ok" -eq 1 ] && rm -f -- "$run"
done
[ -z "$failures" ] || ctx PostToolUse "opsx 續接失敗（herdr 佇列）：${failures}pane 沒有改名或沒送出第一句。看子卡 decisions.tsv，修好後可以把 .failed 改回 .tsv 再跑一次 opsx chain，或在看板上重派。"
exit 0
