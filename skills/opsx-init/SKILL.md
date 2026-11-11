---
name: opsx-init
description: |
  Set up opsx in the current repo (openspec/ + the opsx schema with inbox / explore / grill artifacts,
  openspec/ excluded from git, repo registered as a sync source, herdr workspace mapping) or install
  the opsx CLI globally. Use whenever the user says "opsx init", "init opsx", "把這個 repo 接上 opsx",
  "裝 opsx", "setup opsx", "initialize the workflow here", or starts working in a repo that has no
  openspec/schemas/opsx/. The first run also links the `opsx` command into ~/.local/bin so the user
  can call it from a terminal.
argument-hint: "[--global]"
compatibility: Requires the openspec CLI (npm i -g @fission-ai/openspec) and git.
---

# /opsx init

One script does the work: `${CLAUDE_PLUGIN_ROOT}/bin/opsx`. This skill is only the slash entry for it.

## Steps

1. If `~/.local/bin/opsx` is not a symlink yet, run the global setup once so the CLI exists for the terminal and the state files exist:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/bin/opsx" init --global
   ```

   It is interactive when run from a terminal (asks for the obsidian folder). From here it runs non-interactively and skips that; tell the user they can fill `~/.local/state/opsx/sources.toml` later.

2. Unless the user asked for `--global` only, run the repo-level init from the repo root:

   ```bash
   cd "$(git rev-parse --show-toplevel)" && bash "${CLAUDE_PLUGIN_ROOT}/bin/opsx" init
   ```

   It refuses outside a git repo and prints one line per thing it did or skipped. Rerunning it leaves settings and registrations as they are, but always overwrites the templates and the specs artifact in `openspec/schemas/opsx/` with the plugin's version, so hand edits there are lost.

3. Relay the script's output lines to the user as they are. If it asked nothing (non-interactive), say that the herdr workspace for this repo was not set and can be set with one line in `~/.local/state/opsx/workspaces.toml`, or will be recorded automatically on the first dispatch.

Do not reimplement any of the steps by hand: the script is the single source of truth, and its tests live in `tests/`.
