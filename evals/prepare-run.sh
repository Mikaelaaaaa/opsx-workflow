#!/usr/bin/env bash
# 建一個情境的工作 repo，放進新版或舊版 skill。用法：prepare-run.sh <skill> <fixture> <new|old> <dest>
# new = 本 repo 的 skills/ 與 references/；old = opsx 0.1.0 的 skills/ 加 grill-me。
# skill 放在 .claude/ 底下並寫進 .git/info/exclude，工作 repo 的 git status 保持乾淨。
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="${1:?usage: prepare-run.sh <skill> <fixture> <new|old> <dest>}"
fixture="${2:?fixture}"
variant="${3:?new|old}"
dest="${4:?dest}"
old_skills="${OPSX_OLD_SKILLS:-$HOME/.claude/plugins/cache/opsx-workflow/opsx-workflow/0.1.0/skills}"
old_grill="${OPSX_OLD_GRILL:-$HOME/.claude/skills/grill-me}"

bash "$root/skills/$skill/evals/fixtures/$fixture/setup.sh" "$dest"
mkdir -p "$dest/.claude"
case "$variant" in
  new)
    cp -R "$root/skills" "$dest/.claude/skills"
    cp -R "$root/references" "$dest/.claude/references"
    ;;
  old)
    cp -R "$old_skills" "$dest/.claude/skills"
    cp -R "$old_grill" "$dest/.claude/skills/grill-me"
    ;;
  *)
    echo "variant must be new or old, got: $variant" >&2
    exit 2
    ;;
esac
find "$dest/.claude" -type d -name evals -prune -exec rm -rf {} +
echo ".claude/" >> "$dest/.git/info/exclude"
