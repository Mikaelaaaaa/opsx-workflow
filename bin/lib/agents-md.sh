#!/usr/bin/env bash
# 給 codex 的 AGENTS.md：codex 沒有 router hook 每句注入的規則，dispatch 把同一批規則渲染成檔放進 worktree。
# 規則文字在 rules.sh（跟 router 同源）；接續規則與授權三級嵌 references/ 下的原檔。
# 階段不寫進來：階段由每句 prompt 的 `/opsx-workflow:<stage> <slug>` 給。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/rules.sh"

render_agents_md() { # <interactive|autopilot>
  local mode_rule grant_note=""
  case "$1" in
    autopilot) mode_rule="$(rule_autopilot)" ;;
    interactive)
      mode_rule="$(rule_interactive)"
      grant_note='本卡是 interactive：下表凡寫「寫 gate」「一律 gate」處，一律改成在 pane 直接問人，不寫 gate。' ;;
    *) echo "render_agents_md: 模式只收 interactive|autopilot，拿到「$1」" >&2; return 1 ;;
  esac
  printf '# opsx 規則\n\n'
  printf '這張卡由 opsx 派工。下面的規則與 Claude Code 端每句 prompt 注入的是同一份；codex 沒有注入機制，靠這份文字遵守。\n'
  printf '每句 prompt 是 `/opsx-workflow:<stage> <slug>`（舊的 `/<stage> <slug>` 同義）：讀 %s/skills/<stage>/SKILL.md 照做。接續規則裡「用 Skill 工具呼叫下一個 skill」在 codex 是讀那個 skill 檔照做。\n\n' "$OPSX_ROOT"
  printf '## 這張卡的模式\n\n'
  printf '%s\n' "$mode_rule" | awk -F' · ' '{ for (i = 1; i <= NF; i++) print "- " $i }'
  printf '\n## 接續規則\n\n'
  cat "$OPSX_ROOT/references/continue.md"
  printf '\n## 授權\n\n'
  [ -z "$grant_note" ] || printf '%s\n\n' "$grant_note"
  cat "$OPSX_ROOT/references/grants.md"
  printf '\n## 合併\n\nmerge 永遠是人：不自己 merge，不替自己的 MR 按核准；到「等合併」就停。\n'
}

# 把渲染結果放進 worktree 根並排除出 git。repo 自己追蹤了 AGENTS.md 就不動它，改寫 AGENTS.override.md（原內容 + opsx 區塊）。
# info/exclude 在共用 git dir，主 checkout 也會排除這兩個名字。
place_agents_md() { # <worktree> <mode>
  local wt="$1" body excl name
  body="$(render_agents_md "$2")" || return 1
  if git -C "$wt" ls-files --error-unmatch AGENTS.md >/dev/null 2>&1; then
    { cat "$wt/AGENTS.md"; printf '\n%s\n' "$body"; } > "$wt/AGENTS.override.md"
  else
    printf '%s\n' "$body" > "$wt/AGENTS.md"
  fi
  excl="$(git -C "$wt" rev-parse --path-format=absolute --git-path info/exclude)"
  mkdir -p "$(dirname "$excl")"
  for name in /AGENTS.md /AGENTS.override.md; do
    grep -qxF "$name" "$excl" 2>/dev/null || printf '%s\n' "$name" >> "$excl"
  done
}
