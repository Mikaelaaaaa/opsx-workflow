#!/usr/bin/env bash
# PreToolUse hook: block dangerous git operations + credential leak scanning
# Covers: push to main, force push, AI attribution, .env staging, credential leaks
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

deny() {
  jq -n --arg reason "$1" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
  exit 0
}

# ── Block push to main/master ──
if echo "$COMMAND" | grep -qE '(^|\s|&&|\|\||;)git\s+push(\s|$)'; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    deny "Do not push directly to main/master. Create a feature branch and open a PR."
  fi
  if echo "$COMMAND" | grep -qE '\b(main|master)\b' && ! echo "$COMMAND" | grep -qE '(-u|--set-upstream)'; then
    deny "Do not push directly to main/master. Create a feature branch and open a PR."
  fi
  # Block force push
  if echo "$COMMAND" | grep -qE '\s(--force|-f)\b'; then
    deny "Force push is blocked. Use --force-with-lease if you must overwrite remote history."
  fi
fi

# ── Block git add of .env files ──
if echo "$COMMAND" | grep -qE '(^|\s|&&|\|\||;)git\s+add(\s|$)'; then
  if echo "$COMMAND" | grep -E '\.(env|env\.local|env\.docker)(\s|$)' | grep -qv 'example'; then
    deny "Adding .env files is blocked. Only .env.example files should be committed."
  fi
fi

# ── Block commits with AI attribution ──
if echo "$COMMAND" | grep -qE '(^|\s|&&|\|\||;)git\s+commit(\s|$)'; then
  # Drop directory arguments (the word after `cd` / `-C`) and every word containing `/`, so a path
  # like /private/tmp/claude-502/x is not mistaken for attribution.
  # shortcut: a message word containing `/` (e.g. Claude/x) is not scanned; fine as an accident guard, go back to parsing -m values if it must resist deliberate evasion
  SCANNED=$(echo "$COMMAND" | sed -E 's/(^|[[:space:]])(cd|-C)[[:space:]]+[^[:space:]]+/\1/g; s/[^[:space:]]*\/[^[:space:]]*//g')
  if echo "$SCANNED" | grep -iqE '(claude|anthropic|co-authored-by.*(claude|anthropic)|Generated with.*Claude)'; then
    deny "Commit must not reference Claude, Anthropic, or AI model names."
  fi
fi

# ── Credential leak scan on commit ──
if echo "$COMMAND" | grep -qE '(^|\s|&&|\|\||;)git\s+commit(\s|$)'; then
  DIFF=$(git diff --cached --unified=0 --no-color 2>/dev/null || true)
  [[ -z "$DIFF" ]] && exit 0

  ADDED=$(echo "$DIFF" | grep '^+' | grep -v '^+++' || true)
  [[ -z "$ADDED" ]] && exit 0

  PATTERNS=(
    "AWS Access Key:::AKIA[0-9A-Z]{16}"
    "OpenAI API Key:::sk-proj-[A-Za-z0-9_-]{80,}"
    "HuggingFace Token:::hf_[A-Za-z0-9]{34,}"
    "Slack Bot/User Token:::xox[bp]-[0-9]{10,}-[0-9A-Za-z-]{20,}"
    "Slack Webhook:::https://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+"
    "GitHub PAT:::gh[ps]_[A-Za-z0-9]{36}"
    "GitHub PAT (fine-grained):::github_pat_[A-Za-z0-9_]{82}"
    "Google API Key:::AIza[0-9A-Za-z_-]{35}"
    "Stripe Secret Key:::[sr]k_live_[0-9a-zA-Z]{24,}"
    "Anthropic API Key:::sk-ant-[A-Za-z0-9_-]{80,}"
    "Private Key Header:::-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"
    "Hardcoded Password:::(password|passwd|pwd)\s*[=:]\s*['\"][^'\"]{8,}"
    "Hardcoded Secret/Token:::(secret|api_secret|token|api_token)\s*[=:]\s*['\"][^'\"]{8,}"
    "Database URL:::(postgres|mysql|mongodb|redis)://[^\s'\"]{10,}"
  )

  FINDINGS=()
  COUNT=0

  for entry in "${PATTERNS[@]}"; do
    LABEL="${entry%%:::*}"
    PATTERN="${entry##*:::}"
    MATCHES=$(echo "$ADDED" | grep -P "$PATTERN" 2>/dev/null || true)
    if [[ -n "$MATCHES" ]]; then
      while IFS= read -r match_line; do
        COUNT=$((COUNT + 1))
        CLEAN=$(echo "$match_line" | sed 's/^\+//' | xargs)
        if [[ ${#CLEAN} -gt 20 ]]; then
          REDACTED="${CLEAN:0:6}...REDACTED...${CLEAN: -4}"
        else
          REDACTED="[REDACTED]"
        fi
        FINDINGS+=("  [$COUNT] $LABEL: $REDACTED")
      done <<< "$MATCHES"
    fi
  done

  if [[ $COUNT -gt 0 ]]; then
    DETAIL=""
    for f in "${FINDINGS[@]}"; do
      DETAIL="${DETAIL}\n${f}"
    done
    deny "CREDENTIAL LEAK — commit blocked.\n\nFound ${COUNT} potential secret(s):${DETAIL}\n\nRemove secrets before committing."
  fi
fi

exit 0
