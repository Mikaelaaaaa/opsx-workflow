#!/usr/bin/env bash
# opsx log <slug> <who> <tag> <文字> [證據] [--repo <top>]：在卡的 decisions.tsv 追加一列 ts · who · tag · 文字 · 證據。
# opsx log --sync <source> <新卡數> <文字>：在 <state>/sync.log 追加一列 ts · source · 新卡數 · 文字。
# 別的子命令 source 這檔後用 log_row 寫列，格式只在這裡。specs/opsx-log/spec.md。

OPSX_TAGS="已允許 已決定 替你決定 已指派 已停止 已合併 同步 驗證"
export OPSX_TAGS

log_cell() { printf '%s' "$1" | tr '\t\n\r' '   '; }

log_row() { # <card dir> <who> <tag> <文字> [證據]
  local d="$1" who="$2" tag="$3" text="$4" ev="${5:-}"
  [ -d "$d" ] || die "log: 卡的目錄不存在：$d"
  [ -n "$who" ] || die "log: who 不能是空的"
  [ -n "$text" ] || die "log: 文字不能是空的"
  case " $OPSX_TAGS " in *" $tag "*) ;; *) die "log: 不認得的 tag「${tag}」，要是其中之一：$OPSX_TAGS" ;; esac
  printf '%s\t%s\t%s\t%s\t%s\n' "$(now_iso)" "$(log_cell "$who")" "$tag" "$(log_cell "$text")" "$(log_cell "$ev")" | opsx_append "$d/decisions.tsv" || die "log: 寫不進 $d/decisions.tsv"
}

sync_row() { # <source> <新卡數> <文字>
  [ -n "$1" ] || die "log --sync: source 不能是空的"
  case "$2" in ""|*[!0-9]*) die "log --sync: 新卡數要是非負整數，收到「${2}」" ;; esac
  [ -n "$3" ] || die "log --sync: 文字不能是空的"
  mkdir -p "$OPSX_STATE_DIR"
  printf '%s\t%s\t%s\t%s\n' "$(now_iso)" "$(log_cell "$1")" "$2" "$(log_cell "$3")" | opsx_append "$OPSX_STATE_DIR/sync.log" || die "log: 寫不進 $OPSX_STATE_DIR/sync.log"
}

reap_row() { # <repo/slug 或 pane> <文字>：卡目錄已不在時，stop / reap 的紀錄寫這裡
  [ -n "$1" ] || die "log: reap 紀錄的對象不能是空的"
  [ -n "$2" ] || die "log: reap 紀錄的文字不能是空的"
  mkdir -p "$OPSX_STATE_DIR"
  printf '%s\t%s\t%s\n' "$(now_iso)" "$(log_cell "$1")" "$(log_cell "$2")" | opsx_append "$OPSX_STATE_DIR/reap.log" || die "log: 寫不進 $OPSX_STATE_DIR/reap.log"
}

opsx_log() {
  if [ "${1:-}" = --sync ]; then
    [ $# -eq 4 ] || die "log: 用法 opsx log --sync <source> <新卡數> <文字>"
    sync_row "$2" "$3" "$4"; return
  fi
  local top="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in --repo) top="$2"; shift 2 ;; *) args+=("$1"); shift ;; esac
  done
  [ "${#args[@]}" -ge 4 ] && [ "${#args[@]}" -le 5 ] || die "log: 用法 opsx log <slug> <who> <tag> <文字> [證據]"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "log: 不在 git repo 裡，或給 --repo"
  log_row "$top/openspec/changes/${args[0]}" "${args[1]}" "${args[2]}" "${args[3]}" "${args[4]:-}"
}
