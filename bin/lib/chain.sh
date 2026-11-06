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
  fan_out "$top" "$repo" "$slug" "$rows"
}

# 多張子卡（grill D3）：pane 自己不做，只協調。每張子卡在 dispatch.json 記一筆代管條目，
# 看板才會把它放在「進行中」，送話（route.sh）才知道要送到這個 pane。spawn subagent 是 pane 的事（archive SKILL.md）。
fan_out() { # <top> <repo> <父卡> <chain.py 的 child 行>
  local top="$1" repo="$2" parent="$3" rows="$4" agent now; now="$(now_iso)"
  agent="$(jq -r --arg k "$repo/$parent" '.[$k].agent // "claude"' "$OPSX_STATE_DIR/dispatch.json")"
  local plan="" _ child branch kind
  while IFS=$'\t' read -r _ child branch kind; do
    plan+="$child"$'\t'"$branch"$'\t'"$kind"$'\t'"$(default_model "$agent" "$kind")"$'\n'
  done <<< "$rows"
  local mode
  mode="$(OPSX_KEY="$repo/$parent" OPSX_PARENT="$parent" OPSX_PLAN="$plan" OPSX_AT="$now" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/chain.py" fan-out "$OPSX_STATE_DIR/dispatch.json")" || die "chain: 寫 dispatch.json 失敗"
  while IFS=$'\t' read -r child branch kind _; do
    [ -n "$child" ] || continue
    local d="$top/openspec/changes/$child"
    printf '%s\t%s\t%s\n' "$now" "自動派：因 ${parent} merged（fan out，由 ${parent} 的 pane 代管）" "auto-dispatched" >> "$d/decisions.tsv"
    [ "$mode" = drive ] && printf '%s\t%s\t%s\n' "$now" "父卡是 drive，drive 不支援代管卡（沒有自己的 herdr agent 可以送話），改 autopilot" "decided" >> "$d/decisions.tsv"
    say "chain: fan out ${child} · ${branch} · ${kind} · /$(stage_name "$top" "$child")"
  done <<< "$plan"
}
