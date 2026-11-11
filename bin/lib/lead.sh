#!/usr/bin/env bash
# opsx lead：在目前的 herdr workspace 開協調者 session（herdr 名 opsx-coordinator），第一句載入 /opsx-workflow:lead。
# specs/opsx-lead/spec.md。權限模式不帶，用使用者平常的模式：這個 session 能連 herdr socket，不再放寬。

opsx_lead() {
  [ "$#" -le 1 ] || die "lead 只接受一個 repo 路徑，收到：$*"
  [ -n "${HERDR_ENV:-}" ] || die "lead: 不在 herdr pane 裡。先開 herdr，在 herdr pane 裡跑 opsx lead"
  [ -n "${HERDR_WORKSPACE_ID:-}" ] || die "lead: HERDR_ENV 有值但沒有 HERDR_WORKSPACE_ID，不知道要開在哪個 workspace"
  local dir="${1:-$PWD}" top settings="$OPSX_STATE_DIR/coordinator-settings.json" got where tabjson pane tab
  [ -d "$dir" ] || die "lead: 不是目錄：$dir"
  top="$(cd "$dir" && pwd -P)"
  [ -f "$settings" ] || die "lead: 沒有 ${settings}。先在沙盒外（你的終端機）跑 opsx init --global"

  if got="$(herdr agent get "$COORDINATOR_AGENT" 2>&1)"; then
    where="$(printf '%s' "$got" | jq -er '[.. | objects | select(has("pane_id"))][0] | "workspace \(.workspace_id) · tab \(.tab_id) · pane \(.pane_id)"' 2>/dev/null)" \
      || die "lead: herdr agent get $COORDINATOR_AGENT 回的格式讀不懂：$got"
    say "lead: 協調者已在跑（${where}），不開第二個。herdr agent focus $COORDINATOR_AGENT 切過去"
    return 0
  fi
  case "$got" in *agent_not_found*) ;; *) die "lead: herdr agent get $COORDINATOR_AGENT 失敗：$got" ;; esac

  tabjson="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$top" --label "$COORDINATOR_AGENT" --no-focus)"
  pane="$(printf '%s' "$tabjson" | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null || true)"
  tab="$(printf '%s' "$tabjson" | jq -r '.result.tab.tab_id // empty' 2>/dev/null || true)"
  [ -n "$pane" ] || die "lead: herdr tab create 沒回 root_pane：$tabjson"
  herdr_start_agent lead "$COORDINATOR_AGENT" claude "$pane" "$tab" --settings "$settings" --add-dir "$OPSX_STATE_DIR"
  herdr agent prompt "$COORDINATOR_AGENT" "/opsx-workflow:lead" >/dev/null || die "lead: 協調者起來了但第一句送不進去（pane $pane）"
  herdr agent focus "$COORDINATOR_AGENT" >/dev/null || warn "焦點切不過去，協調者在 tab ${tab}（pane ${pane}）"
  say "lead: 協調者開在 tab ${tab}（pane ${pane}），cwd ${top}"
}
