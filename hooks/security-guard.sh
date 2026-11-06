#!/usr/bin/env bash
# PreToolUse hook: block dangerous git operations + credential leak scanning
# Covers: push to main, force push, AI attribution, .env staging, credential leaks
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-$PWD}"

OPSX_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OPSX_STATE_DIR="${OPSX_STATE_DIR:-$HOME/.local/state/opsx}"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/python.sh"

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
  if ! opsx_python_load; then
    deny "Cannot check the commit message: ${OPSX_PY_ERR}"
  fi
  PARSED=$(OPSX_CMD="$COMMAND" OPSX_CWD="$CWD" "$OPSX_PY" -I - <<'PY'
import json
import os
import shlex

SEPARATORS = set("&|;")


def is_separator(token):
    return bool(token) and set(token) <= SEPARATORS


def commit_segments(tokens):
    segments = []
    for i in range(len(tokens) - 1):
        if tokens[i] == "git" and tokens[i + 1] == "commit":
            segments.append(tokens[i + 2:])
    return segments


def read_message_file(flag, path, cwd):
    if path == "-":
        raise ValueError("%s: cannot read '-' (stdin)" % flag)
    try:
        with open(os.path.join(cwd, path), encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError) as e:
        raise ValueError("%s: cannot read '%s' (%s)" % (flag, path, e)) from e


def next_value(flag, args, i):
    if i >= len(args):
        raise ValueError("%s: missing value" % flag)
    return args[i]


def segment_messages(args, cwd):
    messages = []
    i = 0
    while i < len(args):
        arg = args[i]
        i += 1
        if is_separator(arg):
            break
        if arg.startswith("--message="):
            messages.append(arg[len("--message="):])
        elif arg.startswith("--file="):
            messages.append(read_message_file("--file", arg[len("--file="):], cwd))
        elif arg in ("--message", "-m"):
            messages.append(next_value(arg, args, i))
            i += 1
        elif arg in ("--file", "-F"):
            messages.append(read_message_file(arg, next_value(arg, args, i), cwd))
            i += 1
        elif arg.startswith("-") and not arg.startswith("--") and len(arg) > 2:
            for pos, char in enumerate(arg[1:], start=1):
                if char not in "mF":
                    continue
                rest = arg[pos + 1:]
                if not rest:
                    rest = next_value("-" + char, args, i)
                    i += 1
                if char == "m":
                    messages.append(rest)
                else:
                    messages.append(read_message_file("-F", rest, cwd))
                break
    return messages


def main():
    lex = shlex.shlex(os.environ["OPSX_CMD"], posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        tokens = list(lex)
    except ValueError as e:
        return {"error": "cannot parse command: %s" % e}
    messages = []
    try:
        for args in commit_segments(tokens):
            messages.extend(segment_messages(args, os.environ["OPSX_CWD"]))
    except ValueError as e:
        return {"error": str(e)}
    return {"messages": messages}


print(json.dumps(main()))
PY
)
  PARSE_ERROR=$(echo "$PARSED" | jq -r '.error // empty')
  [[ -n "$PARSE_ERROR" ]] && deny "Cannot check the commit message — $PARSE_ERROR"
  if echo "$PARSED" | jq -r '.messages[]' | grep -iqE '(claude|anthropic|co-authored-by.*(claude|anthropic)|Generated with.*Claude)'; then
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
