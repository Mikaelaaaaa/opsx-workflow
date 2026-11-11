#!/usr/bin/env bash
# opsx drop <slug> [--repo <path>] -- <理由>：捨棄一張卡，理由必填單行。
# 給 repo：.openspec.yaml 寫 outcome: declined、inbox.md 尾端加 ## 捨棄理由、decisions.tsv 記一行，再 openspec archive。
#   收件卡沒有 explore.md，所以 archive 要的「不做」就寫在 ## 捨棄理由。還派著（dispatch.json 有、不是 stopped）的卡要先停止。
# 不給 repo：對象是待分類 <state>/unfiled/<slug>.md，移到 unfiled/dropped/，不刪，誤按還找得回來；
#   附件資料夾 unfiled/<slug>/ 一起移成 dropped/ 裡跟 .md 同名的資料夾。
# specs/board-actions「捨棄」。

opsx_drop() {
  local slug="" top="" reason=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --) shift; reason="$*"; break ;;
      -*) die "drop: 不認得的選項 $1" ;;
      *) [ -z "$slug" ] || die "drop: 用法 opsx drop <slug> [--repo <path>] -- <理由>"; slug="$1"; shift ;;
    esac
  done
  [ -n "$slug" ] || die "drop: 用法 opsx drop <slug> [--repo <path>] -- <理由>"
  [[ "$slug" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "drop: slug 不合格：$slug"
  single_line "$reason"
  reason="$(printf '%s' "$reason" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  if [ -z "$top" ]; then
    local src="$OPSX_STATE_DIR/unfiled/$slug.md"
    [ -f "$src" ] || die "drop: 待分類裡沒有 ${slug}（${src}）"
    local dropped="$OPSX_STATE_DIR/unfiled/dropped" dest="$slug" n=1
    mkdir -p "$dropped"
    while [ -e "$dropped/$dest.md" ] || [ -e "$dropped/$dest" ]; do n=$((n+1)); dest="$slug-$n"; done
    printf '\n## 捨棄理由\n\n%s\n' "$reason" >> "$src"
    mv -n "$src" "$dropped/$dest.md"
    [ ! -d "$OPSX_STATE_DIR/unfiled/$slug" ] || mv -n "$OPSX_STATE_DIR/unfiled/$slug" "$dropped/$dest"
    say "drop: 待分類 $slug 移到 unfiled/dropped/$dest.md"
    return
  fi

  top="$(opsx_repo_top "$top")"
  local repo d; repo="$(basename "$top")"; d="$top/openspec/changes/$slug"
  [ -d "$d" ] || die "drop: 沒有這張卡：$d"
  local f="$OPSX_STATE_DIR/dispatch.json" mode=""
  [ -f "$f" ] && mode="$(OPSX_KEY="$repo/$slug" "$OPSX_PY" -I -c 'import json,os,sys;e=json.load(open(sys.argv[1])).get(os.environ["OPSX_KEY"]);print("" if e is None else e.get("mode") or "running")' "$f")"
  [ -z "$mode" ] || [ "$mode" = stopped ] || die "drop: $repo/$slug 還派著（${mode}），先在板上按停止或 opsx stop $slug"
  # 併入的項目只活在這張卡的 inbox.md：歸檔之後 split-out 找不到，等於跟著一起丟掉。舊卡可能沒有 inbox.md。
  local ids=""
  [ ! -f "$d/inbox.md" ] || ids="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/inboxmerge.py" ids "$d")" || die "drop: 讀不了 $d/inbox.md 的併入段（上面是原因）"
  [ -z "$ids" ] || die "drop: $repo/$slug 還有併入的項目（${ids//$'\n'/ }），先用 opsx split-out $slug <id> 拆出來再捨棄"

  printf 'outcome: declined\n' >> "$d/.openspec.yaml"
  printf '\n## 捨棄理由\n\n%s\n' "$reason" >> "$d/inbox.md"
  log_row "$d" 你 已決定 "捨棄：$reason" declined
  ( cd "$top" && openspec archive "$slug" --yes --skip-specs >/dev/null ) || die "drop: openspec archive $slug 失敗；outcome 與理由已寫進 $d"
  say "drop: $repo/$slug 已捨棄並歸檔"
}
