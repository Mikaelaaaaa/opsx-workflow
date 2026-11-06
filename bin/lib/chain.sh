#!/usr/bin/env bash
# opsx chain <父卡 slug> [--repo <top>]：父卡合併後，讓同一個 pane 接著做依賴它的子卡。archive 做完會叫它。
# 判斷在 chain.py。沒有子卡可接時 exit 0、什麼都不碰（不接不是錯）。specs/opsx-chain/spec.md。

opsx_chain() {
  local slug="" top=""
  while [ $# -gt 0 ]; do
    case "$1" in --repo) top="$2"; shift 2 ;; --*) die "chain: 不認得的選項 $1" ;; *) [ -z "$slug" ] && slug="$1" || die "chain: 多餘的參數 $1"; shift ;; esac
  done
  [ -n "$slug" ] || die "chain: 用法 opsx chain <父卡 slug> [--repo <top>]"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "chain: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  local repo rows; repo="$(basename "$top")"
  rows="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/chain.py" children "$top" "$repo" "$slug" "$OPSX_STATE_DIR/dispatch.json")" || exit 2

  case "$rows" in skip*) say "chain: ${rows#skip$'\t'}"; return 0 ;; esac
  local n; n="$(printf '%s\n' "$rows" | grep -c '^child')"
  if [ "$n" -eq 1 ]; then
    die "chain: 單一子卡續接還沒做（等 gate herdr-from-session 決定 herdr 由誰呼叫）"
  fi
  die "chain: fan-out 還沒做"
}
