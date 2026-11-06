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

interactive() { [ -z "${OPSX_NONINTERACTIVE:-}" ] && [ -t 0 ]; }

# 一句話：只准單行、去掉空白後非空（會寫進 inbox.md 的 ## 一句話）
single_line() { # <text>，不合格就 die
  case "$1" in *$'\n'*|*$'\r'*) die "一句話不能有換行" ;; esac
  [ -n "${1//[[:space:]]/}" ] || die "一句話是空的"
}

# repo 根：有 openspec/changes/ 的目錄，印實體路徑
opsx_repo_top() { # <path>
  [ -d "$1/openspec/changes" ] || die "不是 opsx repo（沒有 openspec/changes/）：$1"
  ( cd "$1" && pwd -P )
}

# 在 <top> 用 openspec 建殼，inbox.md 寫成 <內容檔>；slug 已存在就依序加 -2、-3。印實際的 slug。
# 總長超過 32 時截中段、保留最後一段（issue 編號）：gh-<repo>-1 撞名要變 gh-<re>-1-2，不能變成 issue #2 的 gh-<repo>-2。
new_shell() { # <top> <slug> <inbox 內容檔>
  local top="$1" slug="$2" n=1 head tail
  while [ -e "$top/openspec/changes/$slug" ]; do
    n=$((n+1)); slug="$2-$n"
    if [ ${#slug} -gt 32 ]; then
      head="${2%-*}"; tail="${2##*-}"; head="${head:0:$((32 - ${#tail} - ${#n} - 2))}"
      slug="${head%-}-$tail-$n"
    fi
  done
  ( cd "$top" && openspec new change "$slug" --schema opsx >/dev/null ) || die "openspec new change $slug 失敗（${top}）"
  cp "$3" "$top/openspec/changes/$slug/inbox.md"
  printf '%s\n' "$slug"
}
