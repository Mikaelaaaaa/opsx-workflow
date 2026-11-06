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
  if [ "$n" -eq 1 ]; then continue_one "$top" "$repo" "$slug" "$rows"; return; fi
  fan_out "$top" "$repo" "$slug" "$rows"
}

# 一張子卡（grill D1）：同一棵 worktree 換到子卡 branch，同一個 pane 接著做。
# 沙盒擋了 herdr socket，所以改名、送第一句、起 drive 都寫進佇列，由 hooks/opsx-herdr-queue.sh 執行（grill D5）。
continue_one() { # <top> <repo> <父卡> <chain.py 的 child 行>
  local top="$1" repo="$2" parent="$3" _ child branch kind
  IFS=$'\t' read -r _ child branch kind <<< "$4"
  local d="$top/openspec/changes/$child" wt used
  wt="$(jq -r --arg k "$repo/$parent" '.[$k].worktree // empty' "$OPSX_STATE_DIR/dispatch.json")"
  if [ ! -d "$wt" ]; then chain_skip "$d" "父卡 ${parent} 記的 worktree 不在：${wt:-（dispatch.json 沒記）}"; return 0; fi
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then chain_skip "$d" "父卡 worktree $wt 有未 commit 的改動，換 branch 會把它們帶過去"; return 0; fi
  used="$(git -C "$wt" worktree list --porcelain | awk -v b="branch refs/heads/$branch" '/^worktree /{w=substr($0, 10)} $0 == b {print w}')"
  if [ -n "$used" ]; then chain_skip "$d" "子卡 branch $branch 已經 checkout 在 $used"; return 0; fi
  if git -C "$wt" show-ref --verify --quiet "refs/heads/$branch"; then
    chain_skip "$d" "子卡 branch $branch 本地已存在，可能是舊的；要從最新的 main 開就先刪掉它再派"; return 0
  fi
  local remote; remote="$(primary_remote "$wt")"
  git -C "$wt" fetch -q "$remote" || die "chain: $wt 的 git fetch $remote 失敗"
  # 不帶 tracking：派工 session 的沙盒寫不進 .git/config，帶 tracking 會停在半套（branch 建了、HEAD 沒換）
  git -C "$wt" switch -q --no-track -c "$branch" "$remote/main" || die "chain: 從 $remote/main 開 $branch 失敗"

  local agent now old_name mode stage
  now="$(now_iso)"; agent="$(jq -r --arg k "$repo/$parent" '.[$k].agent // "claude"' "$OPSX_STATE_DIR/dispatch.json")"
  local out
  out="$(OPSX_KEY="$repo/$parent" OPSX_PARENT="$parent" OPSX_PLAN="$child"$'\t'"$branch"$'\t'"$kind"$'\t'"$(default_model "$agent" "$kind")" OPSX_AT="$now" OPSX_WT="$wt" \
    "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/chain.py" continue "$OPSX_STATE_DIR/dispatch.json")" || die "chain: 寫 dispatch.json 失敗；$wt 已切到 ${branch}，pane 沒改名"
  read -r old_name mode <<< "$out"
  stage="$(stage_name "$top" "$child")"
  local q="$OPSX_STATE_DIR/herdr-queue/$repo-$child.tsv"; ensure_dir "$(dirname "$q")"
  { printf 'rename\t%s\t%s\n' "$old_name" "$child"; printf 'prompt\t%s\t/%s %s\n' "$child" "$stage" "$child"
    [ "$mode" = drive ] && printf 'drive\t%s\t%s\n' "$child" "$top"; true; } > "$q"
  printf '%s\t%s\t%s\n' "$now" "自動派：因 ${parent} merged（同一個 pane 續接，worktree ${wt}）" "auto-dispatched" >> "$d/decisions.tsv"
  say "chain: ${parent} → ${child}：$wt 已切到 ${branch}；改名和第一句 /${stage} 交給 hook（佇列 ${q}）"
}

chain_skip() { # <子卡目錄> <原因>
  printf '%s\t%s\t%s\n' "$(now_iso)" "沒有續接：$2" "skipped" >> "$1/decisions.tsv"
  say "chain: 沒有續接：$2"
}

# 多張子卡（grill D3）：pane 自己不做，只協調。每張子卡在 dispatch.json 記一筆代管條目，
# 看板才會把它放在「進行中」，送話（route.sh）才知道要送到這個 pane。spawn subagent 是 pane 的事（archive SKILL.md）。
fan_out() { # <top> <repo> <父卡> <chain.py 的 child 行>
  local top="$1" repo="$2" parent="$3" rows="$4" agent now; now="$(now_iso)"
  agent="$(jq -r --arg k "$repo/$parent" '.[$k].agent // "claude"' "$OPSX_STATE_DIR/dispatch.json")"
  local plan="" _ child branch kind remote
  remote="$(primary_remote "$top")"
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
    say "chain: fan out ${child} · ${branch} · ${kind} · /$(stage_name "$top" "$child") · from ${remote}/main"
  done <<< "$plan"
}
