#!/usr/bin/env bash
# PostToolUse hook: warn if Bash output contains potential secrets
set -euo pipefail

INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null)
[[ -z "$OUTPUT" ]] && exit 0

LEAKS=$(echo "$OUTPUT" | grep -icP \
  '(AKIA[0-9A-Z]{16}|sk-proj-[A-Za-z0-9_-]{80,}|hf_[A-Za-z0-9]{34,}|xox[bp]-[0-9]{10,}|gh[ps]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82}|AIza[0-9A-Za-z_-]{35}|[sr]k_live_[0-9a-zA-Z]{24,}|sk-ant-[A-Za-z0-9_-]{80,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|https://hooks\.slack\.com/services/)' \
  2>/dev/null || true)

if [[ "$LEAKS" -gt 0 ]]; then
  echo "SECURITY: Bash output may contain $LEAKS exposed secret(s). Do NOT paste these in responses."
fi

exit 0
