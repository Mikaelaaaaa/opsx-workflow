#!/usr/bin/env bash
# opsx lead：在目前的 herdr workspace 開協調者 session（herdr 名 opsx-coordinator），第一句載入 /opsx-workflow:lead。
# specs/opsx-lead/spec.md。權限模式不帶，用使用者平常的模式：這個 session 能連 herdr socket，不再放寬。

opsx_lead() {
  [ "$#" -le 1 ] || die "lead 只接受一個 repo 路徑，收到：$*"
  [ -n "${HERDR_ENV:-}" ] || die "lead: 不在 herdr pane 裡。先開 herdr，在 herdr pane 裡跑 opsx lead"
  [ -n "${HERDR_WORKSPACE_ID:-}" ] || die "lead: HERDR_ENV 有值但沒有 HERDR_WORKSPACE_ID，不知道要開在哪個 workspace"
  local dir="${1:-$PWD}" top settings="$OPSX_STATE_DIR/coordinator-settings.json" got where pane tab
  [ -d "$dir" ] || die "lead: 不是目錄：$dir"
  top="$(cd "$dir" && pwd -P)"
  [ -f "$settings" ] || die "lead: 沒有 ${settings}。先在沙盒外（你的終端機）跑 opsx init --global"

  # agent get 的真輸出與錯誤碼沒有樣本，所以它只用來提早說「已在跑」：查不到、或讀不出位置就照常開，
  # 第二個協調者由 herdr 的名字唯一性擋（agent start 回 agent_name_taken）
  if got="$(runtime_get --agent "$COORDINATOR_AGENT" 2>/dev/null)" \
    && where="$(printf '%s' "$got" | jq -er 'first(.. | objects | select(has("pane_id") and has("tab_id") and has("workspace_id"))) | "workspace \(.workspace_id) · tab \(.tab_id) · pane \(.pane_id)"' 2>/dev/null)"; then
    say "lead: 協調者已在跑（${where}），不開第二個。herdr agent focus $COORDINATOR_AGENT 切過去"
    return 0
  fi

  if ! runtime_open --agent "$COORDINATOR_AGENT" --kind claude --workspace-id "$HERDR_WORKSPACE_ID" --cwd "$top" --label "$COORDINATOR_AGENT" \
    -- --settings "$settings" --add-dir "$OPSX_STATE_DIR"; then
    say "lead: 協調者已在跑（${HERDR_TAKEN_AT}），剛開的 tab 已收掉，不開第二個。herdr agent focus $COORDINATOR_AGENT 切過去"
    return 0
  fi
  pane="$RUNTIME_PANE"; tab="$RUNTIME_TAB"
  runtime_prompt --agent "$COORDINATOR_AGENT" "/opsx-workflow:lead" nowait >/dev/null || die "lead: 協調者起來了但第一句送不進去。到 pane ${pane} 自己打 /opsx-workflow:lead（重跑 opsx lead 會說已在跑，不會補送）"
  runtime_focus --agent "$COORDINATOR_AGENT" >/dev/null || warn "焦點切不過去，協調者在 tab ${tab}（pane ${pane}）"
  say "lead: 協調者開在 tab ${tab}（pane ${pane}），cwd ${top}"
}
