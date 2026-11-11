#!/usr/bin/env bash
# opsx late <slug> [--repo <top>] [--open-gate]：PR 合併後，remote 的分支又多了幾個沒進 main 的 commit 嗎。
# 判斷在 late.py；這裡只取 MR 資料（mr.sh，合併當下的分支 head 是 head_sha）。coordinate 收尾前與 /archive 都叫它。
# 退出 0：none | acked <短 sha>；1：late <N> <短 sha> <branch> 加 commit 清單；2：查不出來（stderr 說缺什麼）。
# 驗收：specs/merged-late-commits/spec.md

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/mr.sh"

opsx_late() {
  local slug="" top="" gate=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --open-gate) gate=1; shift ;;
      --*) die "late: 不認得的選項 $1" ;;
      *) [ -z "$slug" ] || die "late: 只收一個 slug"; slug="$1"; shift ;;
    esac
  done
  [ -n "$slug" ] || die "late: 用法 opsx late <slug> [--repo <top>] [--open-gate]"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "late: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  local d="$top/openspec/changes/$slug" mr
  [ -d "$d" ] || die "late: 沒有這張卡：$d"
  mr="$(mr_json "$d")"
  OPSX_LATE_MR="$mr" "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/late.py" "$top" "$slug" "$OPSX_STATE_DIR" "$gate"
}
