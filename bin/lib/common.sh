#!/usr/bin/env bash
# 共用：訊息、git 位置、TOML 小工具。被 bin/opsx source。

COORDINATOR_AGENT=opsx-coordinator   # 協調者 session 在 herdr 的名字；bin/lib/coordinate.py 的 COORDINATOR 是同一個

# 回報一行給協調者 session。送不出去（它不在、herdr 掛了）記 coordinator.log 並回 1；成功回 0。
coordinator_say() { # <一行>
  local err
  err="$(herdr agent prompt "$COORDINATOR_AGENT" "$1" 2>&1 >/dev/null)" && return 0
  printf '%s ?? 回報 %s 送不出去：%s\n' "$(now_iso)" "$COORDINATOR_AGENT" "$(printf '%s' "$err" | head -c 200 | tr '\n' ' ')" | opsx_append "$OPSX_STATE_DIR/coordinator.log" || true
  return 1
}

# 在剛開的 tab 的 pane 起 agent。shell 還沒到 prompt 時 herdr 回 agent_pane_busy，同一個 pane 最多試六次；
# 起不來就收掉剛開的 tab（不留空 tab 給人收）並以 <who> 開頭的訊息結束。dispatch 與 lead 共用。
# 名字已被占用（agent_name_taken）時收掉 tab、把另一個的位置放進 HERDR_TAKEN_AT、回 3：該怎麼說由呼叫者決定。
herdr_start_agent() { # <who> <agent 名> <kind> <pane> <tab> [agent 參數…]
  local who="$1" name="$2" kind="$3" pane="$4" tab="$5" out try=1 screen
  shift 5
  until out="$(herdr agent start "$name" --kind "$kind" --pane "$pane" -- "$@" 2>&1)"; do
    case "$out" in
      *agent_pane_busy*)
        if [ "$try" -lt 6 ]; then try=$((try + 1)); sleep "${OPSX_DISPATCH_RETRY_SLEEP:-1}"; continue; fi
        # pane 已壞時 pane read 會失敗，當成沒輸出，不讓診斷擋住錯誤回報
        screen="$(herdr pane read "$pane" 2>/dev/null | tail -20)" || screen=""
        [ -n "${screen//[[:space:]]/}" ] || screen="pane 沒有任何輸出"
        # 間隔可以是小數（sleep 吃 0.5），shell 算術只吃整數
        out="${out}
新 pane 的 shell 超過 $(awk -v n="$((try - 1))" -v s="${OPSX_DISPATCH_RETRY_SLEEP:-1}" 'BEGIN { print n * s }') 秒沒有出現提示字元，可能是 shell 啟動卡住。常見原因：pyenv 鎖檔 ~/.pyenv/shims/.pyenv-shim 殘留（opsx init --check 會檢查）
pane 畫面：
${screen}" ;;
      *agent_name_taken*)
        HERDR_TAKEN_AT="$(printf '%s' "$out" | grep -oE '(workspace_id|tab_id|pane_id|status)=[^ "]*' | tr '\n' ' ')"
        herdr tab close "$tab" >/dev/null 2>&1 || true
        return 3 ;;
      *agent_not_ready*)
        # Claude Code 在沒信任過的目錄先問 trust，herdr 判成 blocked；名字已記下，按 Yes 等到 idle 就等於 start 成功
        if herdr pane wait-output --match "trust this folder" --timeout 3000 "$pane" >/dev/null 2>&1; then
          herdr pane send-keys "$pane" down enter >/dev/null
          if herdr agent wait "$name" --until idle --timeout 60000 >/dev/null 2>&1; then break; fi
          out="trust 按了但 agent 沒到 idle"
        else
          out="${out}
pane 畫面：
$(herdr pane read "$pane" 2>/dev/null | tail -20)"
        fi ;;
    esac
    herdr tab close "$tab" >/dev/null 2>&1 || true
    die "${who}: herdr agent start 失敗（第 ${try} 次）：${out}"
  done
}

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

# MR 所在的 remote：Acmecorp-AI / Infrastructure 的 origin 是 GitHub 鏡像，有 gitlab 就以它為準（同 init.sh 的 register_source）
primary_remote() { # <git dir>
  if git -C "$1" remote get-url gitlab >/dev/null 2>&1; then printf 'gitlab\n'; else printf 'origin\n'; fi
}

# agent 沒指定 model 時照 kind 給：要想的用 opus，照表操課的用 sonnet。dispatch 和 chain 共用
default_model() { # <agent> <kind>
  if [ "$1" = codex ]; then printf 'gpt-5\n'; return; fi
  case "$2" in dev|refactoring|perf|experiment) printf 'claude-opus-5-5\n' ;; *) printf 'claude-sonnet-5-5\n' ;; esac
}

interactive() { [ -z "${OPSX_NONINTERACTIVE:-}" ] && [ -t 0 ]; }

# 資料夾沒按過 Claude Code 的信任對話框時，專案層 settings 的 allow 與 additionalDirectories 不生效。
# 只警告；信任是使用者在對話框的安全確認，opsx 不替他按。worktree 看主 checkout 的根（傳 repo 的 top）。
warn_untrusted() { # <repo 主 checkout 根>
  local out
  out="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/claude-trust.py" "$1")" || die "沒讀到 Claude Code 的信任紀錄（上面是原因）"
  case "$out" in
    untrusted*) warn "$1 還沒信任過 Claude Code：專案層 settings 的 allow 與 additionalDirectories 會被忽略，agent 容易卡在權限。到那個資料夾開一次 claude、在對話框按信任；opsx 不會替你改信任紀錄。opsx 自己的設定寫在使用者層，不受影響" ;;
  esac
}

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
# 沒有 - 或最後一段太長（留不下開頭至少一個字）時，改成截尾再加 -N。
# 並行呼叫挑同一個 slug：先 mkdir <top>/openspec/.reserve-<slug>（原子）拿到保留，才建殼；建完或失敗都放掉。
# 不能預先 mkdir changes/<slug>：openspec new change 看到已存在會拒絕。
new_shell() { # <top> <slug> <inbox 內容檔>
  local top="$1" slug="$2" n=1 head tail keep res err
  while :; do
    res="$top/openspec/.reserve-$slug"
    if err="$(mkdir "$res" 2>&1)"; then
      [ -e "$top/openspec/changes/$slug" ] || break
      rmdir "$res"
    elif [ ! -w "$top/openspec" ]; then
      die "建不了保留目錄 ${res}（${top}/openspec 不可寫）"
    fi
    n=$((n+1))
    [ "$n" -le 1000 ] || die "試了 1000 個 slug 都拿不到保留（最後一個 ${res}）：${err}"
    slug="$2-$n"
    [ ${#slug} -gt 32 ] || continue
    head="${2%-*}"; tail="${2##*-}"; keep=$((32 - ${#tail} - ${#n} - 2))
    if [ "$head" != "$2" ] && [ "$keep" -ge 1 ]; then
      head="${head:0:$keep}"; slug="${head%-}-$tail-$n"
    else
      slug="${2:0:$((32 - ${#n} - 1))}"; slug="${slug%-}-$n"
    fi
  done
  ( cd "$top" && openspec new change "$slug" --schema opsx >/dev/null ) || { rmdir "$res"; die "openspec new change $slug 失敗（${top}）"; }
  cp "$3" "$top/openspec/changes/$slug/inbox.md" || { rmdir "$res"; die "寫不進 $top/openspec/changes/$slug/inbox.md"; }
  rmdir "$res"
  printf '%s\n' "$slug"
}
