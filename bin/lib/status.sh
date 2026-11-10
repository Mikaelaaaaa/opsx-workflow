#!/usr/bin/env bash
# opsx status：寫 changes/<slug>/status.json。要求檔 §3.6 新增的儲存 6。
#   opsx status <phase> <n>/<total> <label…> [--tests green|red] [--change <slug>] [--sub <子>] [--worker <誰>]
#   opsx status --show [--change <slug>]
# phase 只准主流程的那幾個；slug 從 branch {action}/{slug}/{user} 推，推不到要給 --change。
# slug 是 <主>--<子>（subagent 的子殼分支）或給了 --sub 時寫子殼 changes/<主>/subs/<子>/status.json。
# worker 是誰在做：子殼分支是 subagent-<子>，其他是 session；--worker 覆寫。

OPSX_PHASES="explore grill propose apply review pr archive"

opsx_status() {
  local phase="" step="" total="" label=() tests="" change="" show="" sub="" worker=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tests) tests="${2:-}"; shift 2 ;;
      --change) change="${2:-}"; shift 2 ;;
      --sub) sub="${2:-}"; shift 2 ;;
      --worker) worker="${2:-}"; shift 2 ;;
      --show) show=1; shift ;;
      --*) die "status: 不認得的選項 $1" ;;
      *)
        if [ -z "$phase" ]; then phase="$1"
        elif [ -z "$step" ]; then step="$1"
        else label+=("$1"); fi
        shift ;;
    esac
  done

  local top; top="$(git_toplevel)"
  [ -n "$top" ] || die "status: 不在 git repo 裡"
  [ -n "$change" ] || change="$(slug_from_branch "$(git_branch)")"
  [ -n "$change" ] || die "status: branch '$(git_branch)' 對不到卡（要 {action}/{slug}/{user}），或給 --change <slug>"
  case "$change" in *--*) [ -z "$worker" ] && worker="subagent-${change#*--}" ;; esac
  [ -n "$sub" ] && change="${change%%--*}--$sub"
  [ -n "$worker" ] || worker=session
  local dir file; dir="$(st_card_dir "$top" "$change")"
  [ -d "$dir" ] || die "status: 沒有這張卡：$dir"
  file="$dir/status.json"

  if [ -n "$show" ]; then
    [ -f "$file" ] || { say none; return 0; }
    "$OPSX_PY" -I -c 'import json,sys;d=json.load(open(sys.argv[1]));print("%s %s/%s · %s · tests %s · %s"%(d["phase"],d["step"],d["total"],d["label"],d["tests"],d["at"]))' "$file"
    return 0
  fi

  [ -n "$phase" ] && [ -n "$step" ] && [ ${#label[@]} -gt 0 ] || die "status: 用法 opsx status <phase> <n>/<total> <label…>"
  case " $OPSX_PHASES " in *" $phase "*) ;; *) die "status: phase 要是 $OPSX_PHASES 之一，收到 $phase" ;; esac
  case "$step" in
    [0-9]*/[0-9]*) ;;
    *) die "status: step 要是 n/total，收到 $step" ;;
  esac
  local n="${step%/*}" t="${step#*/}"
  [ "$n" -le "$t" ] 2>/dev/null || die "status: step $n 大於 total $t"
  case "$tests" in ""|green|red|unknown) ;; *) die "status: --tests 只收 green|red，收到 $tests" ;; esac
  if [ -z "$tests" ] && [ -f "$file" ]; then
    tests="$("$OPSX_PY" -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get("tests","unknown"))' "$file")"
  fi
  [ -n "$tests" ] || tests=unknown

  local lbl="${label[*]}" at; at="$(now_iso)"
  OPSX_PHASE="$phase" OPSX_N="$n" OPSX_T="$t" OPSX_LABEL="$lbl" OPSX_TESTS="$tests" OPSX_AT="$at" OPSX_WORKER="$worker" \
  "$OPSX_PY" -I - "$file" <<'PY'
import json,os,sys
d={"phase":os.environ["OPSX_PHASE"],"step":int(os.environ["OPSX_N"]),"total":int(os.environ["OPSX_T"]),
   "label":os.environ["OPSX_LABEL"],"tests":os.environ["OPSX_TESTS"],"at":os.environ["OPSX_AT"],"worker":os.environ["OPSX_WORKER"]}
with open(sys.argv[1],"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2); f.write("\n")
PY
  say "status: $change → $phase $n/$t · $lbl · tests $tests"

  # herdr 鏡像：有 herdr 才做，失敗不影響
  if [ -n "${HERDR_ENV:-}" ] && command -v herdr >/dev/null; then
    local pane; pane="$(herdr pane current --json 2>/dev/null | "$OPSX_PY" -I -c 'import json,sys;print(json.load(sys.stdin).get("result",{}).get("pane_id",""))' 2>/dev/null || true)"
    [ -n "$pane" ] && herdr pane report-metadata --source opsx "$pane" --tokens "phase=$phase" --tokens "step=$n/$t" --tokens "tests=$tests" >/dev/null 2>&1 || true
  fi
}
