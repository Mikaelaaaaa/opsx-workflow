#!/usr/bin/env bash
# Scan every ~/code/*/ repo that has an openspec/ directory for deliberate
# shortcut comments and print one JSON line per hit.
#
# Source: ponytail skills/ponytail-debt/SKILL.md @ 96608e0 (the grep and the
# ceiling / upgrade-trigger parse). The board's daily sync turns each line into
# an inbox card (type: debt) whose source id is
#   shortcut:<repo>:<file>:<sha1(comment text)[:8]>
# The line number is not part of the id (it drifts); it is carried separately.
#
# Output fields:
#   repo        repo directory name under ~/code
#   file        path relative to the repo root
#   line        line number at scan time
#   comment     the comment text after the marker, trimmed
#   hash        first 8 hex chars of sha1(comment)
#   limit       text before the first comma (the ceiling)
#   trigger     text after the first comma (when to upgrade), "" if absent
#   no_trigger  true when trigger is ""
#
# Usage: debt.sh [code-root]        default ~/code
set -euo pipefail

root="${1:-$HOME/code}"

json_escape() {
	# Escape backslash, double quote, and control characters for a JSON string.
	printf '%s' "$1" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))'
}

for repo_dir in "$root"/*/; do
	[ -d "$repo_dir/openspec" ] || continue
	[ -d "$repo_dir/.git" ] || continue
	repo="$(basename "$repo_dir")"

	# The grep from ponytail-debt, run with the repo as cwd so paths are relative.
	# --no-index --exclude-standard: respect .gitignore, skip .git.
	# Agent worktrees under .claude/worktrees/ are copies of the same tree; skip them.
	(cd "$repo_dir" && git grep --no-index --exclude-standard -nE '(#|//|/[*]) ?(shortcut|ponytail):' -- . ':!.claude/worktrees' 2>/dev/null || true) |
	while IFS= read -r hit; do
		file="${hit%%:*}"
		rest="${hit#*:}"
		line="${rest%%:*}"
		text="${rest#*:}"

		# Comment text after the marker word, closing */ stripped, trimmed.
		comment="$(printf '%s' "$text" | sed -E 's/.*(shortcut|ponytail):[[:space:]]*//; s#[[:space:]]*\*/[[:space:]]*$##; s/^[[:space:]]+//; s/[[:space:]]+$//')"
		[ -n "$comment" ] || continue

		hash="$(printf '%s' "$comment" | shasum -a 1 | cut -c1-8)"

		# Convention: shortcut: <ceiling>, <upgrade trigger>
		if printf '%s' "$comment" | grep -q ','; then
			limit="$(printf '%s' "$comment" | sed -E 's/^([^,]*),.*$/\1/; s/[[:space:]]+$//')"
			trigger="$(printf '%s' "$comment" | sed -E 's/^[^,]*,[[:space:]]*//')"
		else
			limit="$comment"
			trigger=""
		fi
		if [ -z "$trigger" ]; then
			no_trigger=true
		else
			no_trigger=false
		fi

		printf '{"repo":%s,"file":%s,"line":%s,"comment":%s,"hash":%s,"limit":%s,"trigger":%s,"no_trigger":%s}\n' \
			"$(json_escape "$repo")" "$(json_escape "$file")" "$line" "$(json_escape "$comment")" \
			"$(json_escape "$hash")" "$(json_escape "$limit")" "$(json_escape "$trigger")" "$no_trigger"
	done
done
