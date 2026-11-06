#!/usr/bin/env bash
# 共用：訊息、git 位置、TOML 小工具。被 bin/opsx source。

say()  { printf '%s\n' "$*"; }
warn() { printf 'opsx: %s\n' "$*" >&2; }
die()  { printf 'opsx: %s\n' "$*" >&2; exit "${2:-2}"; }

# 主 repo 的根目錄：在 dispatch 開的 linked worktree（<top>/.claude/worktrees/<slug>）裡也回主 repo，
# 因為卡（openspec/）只在主 repo、dispatch.json 的 key 也是主 repo 的名字。不在 repo 裡回空字串。
git_toplevel() {
  local common; common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 0
  ( cd "$(dirname "$common")" && pwd -P )
}
# 目前所在 worktree 自己的根（要動 worktree 裡的檔才用這個）
git_worktree_top() { git rev-parse --show-toplevel 2>/dev/null || true; }
# 共用的 .git 目錄（worktree 時指向主 repo 的 .git）
git_common_dir() { git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true; }
git_branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null || true; }

# 從 {action}/{slug}/{user} 形式的 branch 名取出 slug；對不到回空字串
slug_from_branch() {
  local b="$1"
  case "$b" in
    */*/*) printf '%s' "$b" | cut -d/ -f2 ;;
    *) printf '' ;;
  esac
}

now_iso() {
  # ISO 8601 含時區，例 2026-11-05T15:03:00+08:00
  local raw; raw="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s:%s\n' "${raw:0:22}" "${raw:22:2}"
}

ensure_dir() { mkdir -p "$1"; }

# 檔案沒有這一行就加（整行比對）
append_line_once() { # <file> <line>
  touch "$1"
  grep -qxF -- "$2" "$1" || printf '%s\n' "$2" >> "$1"
}

# agent 沒指定 model 時照 kind 給：要想的用 opus，照表操課的用 sonnet。dispatch 和 chain 共用
default_model() { # <agent> <kind>
  if [ "$1" = codex ]; then printf 'gpt-5\n'; return; fi
  case "$2" in dev|refactoring|perf|experiment) printf 'claude-opus-5-5\n' ;; *) printf 'claude-sonnet-5-5\n' ;; esac
}

interactive() { [ -z "${OPSX_NONINTERACTIVE:-}" ] && [ -t 0 ]; }
