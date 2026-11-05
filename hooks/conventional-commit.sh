#!/usr/bin/env bash
# PostToolUse hook: warn if commit message doesn't follow conventional format
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

if ! echo "$COMMAND" | grep -qE '(^|\s|&&|\|\||;)git\s+commit(\s|$)'; then
  exit 0
fi

MSG=$(git log -1 --format='%s' 2>/dev/null || true)
[[ -z "$MSG" ]] && exit 0

if ! echo "$MSG" | grep -qE '^(feat|fix|chore|refactor|docs|test|perf|ci|build|style)(\(.+\))?(!)?: '; then
  echo "WARNING: Commit message does not follow conventional format. Expected: feat:|fix:|chore:|refactor:|docs:|test:|perf:|ci:|build:|style:"
fi

exit 0
