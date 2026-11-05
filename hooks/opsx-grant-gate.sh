#!/usr/bin/env bash
# PreToolUse(Bash / Edit / Write)：自動 / 開到可合併 模式下的授權閘門。要求檔 §3.6 授權三級、§8.5。
#   第三級（永遠要人）一律 deny；第二級查 grants.toml（repo 永遠）與 dispatch.json（這張卡）；
#   互動模式或不在卡上 → 不管。deny 訊息要 worker 寫 gates.md 然後做能做的。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

top="$(repo_top)"; slug="$(card_slug)"
[ -n "$top" ] && [ -n "$slug" ] || exit 0
repo="$(repo_name)"
mode="$(card_mode "$repo" "$slug")"
case "$mode" in autopilot|drive) ;; *) exit 0 ;; esac

tool="$(hook_tool)"; cmd="$(hook_cmd)"; file="$(hook_file)"
GATE_MSG="寫 gates.md（type、問題、建議、證據、風險、沒回答的預設），然後做能做的；人在板上回了會自動繼續"

level3() { deny "opsx 授權閘門：「$1」是永遠要人的動作（第三級），任何授權蓋不掉。$GATE_MSG"; }
level2() { # <action> <label>
  if has_grant "$repo" "$slug" "$1"; then exit 0; fi
  deny "opsx 授權閘門：「$2」要授權（第二級），$repo 沒有長期授權、這張卡也沒有。$GATE_MSG"
}

if [ "$tool" = "Bash" ]; then
  [ -n "$cmd" ] || exit 0
  c="$(printf '%s' "$cmd" | tr '\n' ' ')"
  # 第三級
  printf '%s' "$c" | grep -qE '(glab mr merge|gh pr merge)' && level3 "merge"
  printf '%s' "$c" | grep -qE 'git\s+push.*(--force|-f\b|\+[a-zA-Z])' && level3 "force-push"
  printf '%s' "$c" | grep -qE 'git\s+push.*\b(main|master)\b' && level3 "push main"
  printf '%s' "$c" | grep -qiE '(^|\s|/)deploy(\.sh)?(\s|$)' && level3 "deploy"
  printf '%s' "$c" | grep -qiE 'drop\s+(table|database|schema)|truncate\s+table|db:reset' && level3 "刪資料"
  printf '%s' "$c" | grep -qE 'sops\s+(-e|--encrypt|edit)|\.gitlab-ci\.yml|\.github/workflows' && level3 "改 CI / secrets"
  # 第二級
  printf '%s' "$c" | grep -qE '(^|\s|&&|;)git\s+push(\s|$)' && level2 push "git push"
  printf '%s' "$c" | grep -qE '(glab mr (create|update)|gh pr (create|edit))' && level2 mr "開 / 改 MR"
  printf '%s' "$c" | grep -qE 'db:migrate|drizzle-kit (migrate|push)|alembic upgrade' && level2 migrate "本機 migrate"
  printf '%s' "$c" | grep -qE '(^|\s|&&|;)rm\s+-(r|f|rf|fr)\b' && level2 delete "刪檔（rm -r/-f）"
  printf '%s' "$c" | grep -qE '(pnpm (add|install|i)\b|npm (install|i|ci)\b|uv (add|sync)|pip install|yarn add|brew install)' && level2 install "裝套件"
  printf '%s' "$c" | grep -qE '(^|\s|&&|;)git\s+rebase(\s|$)' && level2 rebase "git rebase"
  printf '%s' "$c" | grep -qE '(curl|wget|http)\s+' && ! printf '%s' "$c" | grep -qE 'localhost|127\.0\.0\.1|litellm\.agentory\.cc' && level2 external "呼叫外部 API"
  exit 0
fi

if [ "$tool" = "Edit" ] || [ "$tool" = "Write" ]; then
  [ -n "$file" ] || exit 0
  case "$file" in
    *.gitlab-ci.yml|*/.github/workflows/*|*secrets*|*.sops.*|*/sops/*) level3 "改 CI / secrets（${file}）" ;;
    *.env.example) exit 0 ;;
    *.env|*.env.*) level2 env "寫 $file" ;;
  esac
fi
exit 0
