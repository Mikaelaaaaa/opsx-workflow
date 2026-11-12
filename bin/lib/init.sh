#!/usr/bin/env bash
# opsx init：repo 層（在 repo 根目錄跑）與 --global（裝一次）。要求檔 §3.6「CLI helper」。
# 重跑冪等：設定與登記已有就印「已有」不動；openspec/schemas/opsx 的範本與 specs 區塊每次都覆寫成插件版。

opsx_init() {
  case "${1:-}" in
    --global) init_global ;;
    --check) init_check || exit 1 ;;
    "") init_repo ;;
    *) die "init 只接受 --global 或 --check，收到：$1" ;;
  esac
}

# ---------- 全域 ----------
init_global() {
  local state="$OPSX_STATE_DIR" bindir="${OPSX_BIN_DIR:-$HOME/.local/bin}"
  # collect / answer / hooks 用 tomllib，要 3.11+；macOS 內建 /usr/bin/python3 是 3.9。現在不講，第二台機器會 502 到底。
  python3 -I -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null \
    || die "init --global: PATH 上的 python3 要 3.11 以上（有 tomllib），現在是 $(python3 --version 2>&1)。pyenv 或 brew 裝一個再跑"
  ensure_dir "$state"; ensure_dir "$bindir"
  # 授權閘門信任的核准與授權（bin/lib/authz.py）。放在 state 目錄的兄弟，不在任何 session 的 additionalDirectories 內，沙盒內寫不進去
  ensure_dir "${state%/}-protected"; chmod 700 "${state%/}-protected"

  # 記下 python3 背後真正的執行檔，opsx 和 hooks 只叫它（bin/lib/python.sh）。路徑不同就覆寫：
  # pyenv 換版本後舊路徑會失效，重跑這裡是唯一的修法。
  # 在 venv（含 pyenv-virtualenv）裡改記 base：venv 一刪記下的路徑就失效，而 opsx 只用 stdlib，base 不缺東西。
  # base 原樣記、不 realpath：brew 的 opt/ symlink 解開會指到帶 patch 版號的 Cellar 目錄，brew upgrade 就失效。
  local probe venv_prefix exe base py old=""
  probe="$(python3 -I -c 'import sys; print(sys.prefix if sys.prefix != sys.base_prefix else ""); print(sys.executable); print(sys._base_executable)')" \
    || die "init --global: 問不到 PATH 上 python 的路徑（上面是 python 的錯誤）"
  { IFS= read -r venv_prefix; IFS= read -r exe; IFS= read -r base; } <<< "$probe"
  py="$exe"
  if [ -n "$venv_prefix" ]; then
    [ "$base" != "$exe" ] && [ -f "$base" ] && [ -x "$base" ] \
      || die "init --global: PATH 上的 python 在 venv（${venv_prefix}）裡，拿不到可用的 base interpreter（sys._base_executable = ${base}）。離開 venv 再跑"
    py="$base"; say "init --global: 偵測到 venv（${venv_prefix}），改記它的 base interpreter"
  fi
  [ -f "$state/python" ] && IFS= read -r old < "$state/python" || true
  if [ "$old" = "$py" ]; then say "init --global: python 已有（${py}）"
  else
    printf '%s\n' "$py" > "$state/python"
    if [ -n "$old" ]; then say "init --global: python 從 $old 換成 $py"; else say "init --global: python 記為 $py"; fi
  fi

  write_if_missing "$state/sources.toml" '# opsx 同步來源。opsx init 在每個 repo 跑時會自動補 gitlab / github；obsidian 在這裡填。
# customer 來源尚未支援（on-hold），填了 opsx sync 也不會同步。
# [obsidian]
# vault = "/path/to/vault"
# folder = "01-Projects/inbox"
'
  write_if_missing "$state/grants.toml" '# 「這個 repo 永遠」那級的授權。每 repo 一個表：push / mr / migrate 三個布林。merge 永遠不可寫。
# [repos."Agentory-AI"]
# push = true
# mr = true
# migrate = false
'
  write_if_missing "$state/workspaces.toml" '# repo ↔ herdr workspace。opsx init 在 repo 裡跑時問一次；指派時也會自動記。
[repos]
'
  local term_line='# terminal_app = "Warp"'
  case "${TERM_PROGRAM:-}" in
    WarpTerminal) term_line='terminal_app = "Warp"' ;;
    ghostty) term_line='terminal_app = "Ghostty"' ;;
    iTerm.app) term_line='terminal_app = "iTerm"' ;;
    Apple_Terminal) term_line='terminal_app = "Terminal"' ;;
  esac
  write_if_missing "$state/config.toml" "# opsx 全域設定。terminal_app：看板「開啟 pane」切完 herdr 焦點後帶到前景的終端機 app（open -a 認得的名稱）。
$term_line
"
  local link="$bindir/opsx"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$OPSX_ROOT/bin/opsx" ]; then
    say "init --global: $link 已有"
  elif [ -e "$link" ]; then
    warn "$link 已存在且不是 opsx 的 symlink，沒動它"
  else
    ln -s "$OPSX_ROOT/bin/opsx" "$link"
    say "init --global: ln -s $OPSX_ROOT/bin/opsx → $link"
  fi
  case ":$PATH:" in *":$bindir:"*) ;; *) warn "$bindir 不在 PATH 裡，記得加" ;; esac

  if interactive; then
    ask_global_sources "$state/sources.toml"
  else
    say "init --global: 非互動，obsidian 來源略過（之後改 $state/sources.toml）"
  fi
  # herdr 看板：把這個 plugin 根目錄掛進 herdr（herdr-plugin.toml 在根目錄）。沒裝 herdr 就跳過。
  if command -v herdr >/dev/null 2>&1; then
    local plist
    if ! plist="$(herdr plugin list 2>&1)"; then
      warn "herdr 在但叫不到（${plist}）；看板 plugin 沒掛，herdr 起來後再跑一次 opsx init --global"
    elif printf '%s' "$plist" | grep -q 'opsx-board'; then say "init --global: herdr plugin opsx-board 已掛"
    elif herdr plugin link "$OPSX_ROOT" >/dev/null; then say "init --global: herdr plugin link ${OPSX_ROOT}（看板 action open-board、pane board）"
    else die "init --global: herdr plugin link 失敗（上面是 herdr 的錯誤）"; fi
  else
    say "init --global: 沒有 herdr，看板 plugin 略過（裝了 herdr 再跑一次）"
  fi
  merge_claude_settings "$py" --template "$OPSX_ROOT/templates/settings.opsx.json"
  warn_skill_clashes
  write_coordinator_settings "$py" "$state"
  install_launch_jobs "$state" "$bindir"
  say "init --global: 設定在 $state"
  say "init --global: 開協調者：在 herdr pane 跑 opsx lead"
}

# 使用者層 Claude Code settings：CLAUDE_CONFIG_DIR 優先，沒設才用 ~/.claude。
# 沙盒不讓沒登記的目錄可寫，裝完 opsx 的 session 才不用人手動開權限（herdr socket 只給主控 session，見 write_coordinator_settings）。
claude_settings_file() { printf '%s/settings.json' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# 插件 skill 名 → 撞到的 Claude Code 內建指令；沒撞印空。
# shortcut: [已評估] 手維護的已知表，內建指令改名或新增時更新；Claude Code 沒有可查的清單
builtin_command_for() { # <skill 名>
  case "$1" in
    review) printf 'code-review' ;;
  esac
}

# 使用者層、專案層（在 repo 裡時）的 skills 目錄名跟插件 skills/ 同名就警告。只警告：可能是刻意留的個人版本，opsx 不動使用者的檔案。
# 另外列出插件 skill 名撞內建指令的：手打短名會跑到內建。
warn_skill_clashes() {
  local top plugin_skills dirs=() dir skill name real builtin advice paths seen=$'\n' hit=$'\n' found=""
  top="$(git_toplevel)"
  plugin_skills="$(cd "$OPSX_ROOT/skills" && pwd -P)"
  dirs+=("$(dirname "$(claude_settings_file)")/skills")
  [ -z "$top" ] || dirs+=("$top/.claude/skills")
  for dir in "${dirs[@]}"; do
    for skill in "$dir"/*/; do
      [ -f "$skill/SKILL.md" ] || continue
      name="$(basename "$skill")"
      [ -d "$OPSX_ROOT/skills/$name" ] || continue
      real="$(cd "$skill" && pwd -P)"
      case "$real/" in "$plugin_skills"/*) continue ;; esac
      case "$seen" in *$'\n'"$real"$'\n'*) continue ;; esac
      seen="$seen$real"$'\n'
      case "$hit" in *$'\n'"$name"$'\n'*) ;; *) hit="$hit$name"$'\n' ;; esac
      found="$found$name"$'\t'"${skill%/}"$'\n'
    done
  done
  # 同一個名字兩層各有一份時只警告一次、列出全部路徑；Claude Code 的同名優先順序沒有查證，不說哪份會贏
  for name in $hit; do
    builtin="$(builtin_command_for "$name")"
    advice="要用插件的就把它們搬走或改名"
    [ -z "$builtin" ] || advice="把這些都搬走後手打斜線加短名「${name}」會跑到內建指令「${builtin}」，一律打 /opsx-workflow:${name}"
    paths="$(awk -F'\t' -v n="$name" '$1 == n { printf "%s%s", sep, $2; sep = "、" }' <<< "$found")"
    warn "skill 同名：${paths} 跟 opsx 插件的 skills/${name} 同名，手打斜線加短名「${name}」可能跑到其中一份，模型也可能選錯。${advice}；刻意留的就忽略這行"
  done
  for skill in "$OPSX_ROOT"/skills/*/; do
    name="$(basename "$skill")"
    case "$hit" in *$'\n'"$name"$'\n'*) continue ;; esac
    builtin="$(builtin_command_for "$name")"
    [ -z "$builtin" ] || warn "插件 skill ${name} 與內建指令「${builtin}」撞名：手打斜線加短名「${name}」會跑到內建指令，要用 /opsx-workflow:${name}"
  done
}

merge_claude_settings() { # <python> <claude-settings.py 的參數…>
  local py="$1" file out; shift
  file="$(claude_settings_file)"
  out="$("$py" -I "$OPSX_ROOT/bin/lib/claude-settings.py" --file "$file" "$@")" \
    || die "init: 沒改 ${file}（上面是原因）"
  case "$out" in
    created) say "init: 建 ${file}（標準設定）" ;;
    changed) say "init: 標準設定合併進 ${file}（原檔備份在 ${file}.opsx-bak）" ;;
    *) say "init: ${file} 的設定已有" ;;
  esac
}

# 主控 session（opsx coordinator）要呼叫 herdr，沙盒預設擋 herdr socket；使用者層標準設定不開它（任何 session 連上 herdr
# 就能用 herdr pane run 在沒有沙盒的 pane 裡跑指令），所以只給主控 session：渲染成一個檔，啟動時用 claude --settings 帶。
# 一般 agent 照 main 原設計走 hooks/opsx-herdr-queue.sh。這個檔在標準設定的 denyWrite 裡。
write_coordinator_settings() { # <python> <state>
  local py="$1" f="$2/coordinator-settings.json" new
  new="$("$py" -I "$OPSX_ROOT/bin/lib/claude-settings.py" --render --template "$OPSX_ROOT/templates/settings.coordinator.json")" \
    || die "init --global: 渲染主控 session 的設定失敗（上面是原因）"
  if [ -f "$f" ] && [ "$(cat "$f")" = "$new" ]; then say "init --global: ${f} 已有"
  else
    printf '%s\n' "$new" > "$f"
    say "init --global: 寫 ${f}；主控 session 用 opsx lead 啟動（它帶 --settings ${f}，開 herdr socket，一般 agent 不給）"
  fi
}

# repo 根目錄會變成每個 session 的可寫目錄：它是 $HOME、$HOME 的上層、或 state 目錄的上層（家目錄是 git repo 時就會發生）
# 就等於把家目錄或授權檔開給所有 session，直接拒絕。openspec/、sources.toml 與 settings 都還沒寫；state 目錄要先建好才能解析實體路徑。
refuse_broad_writable() { # <repo 主 checkout 根>
  local top="$1" d
  for d in "$HOME" "$OPSX_STATE_DIR"; do
    case "$(cd "$d" && pwd -P)/" in
      "$top"/*) die "init: $top 是 ${d} 的上層（或就是它），開成可寫目錄範圍太大；到更深的 repo 根目錄再跑 opsx init" ;;
    esac
  done
  # opsx 自己的 repo 本來就要登記，所以這裡只警告：登記後所有 session 都能改 opsx 程式碼，之後在沙盒外跑它就是執行被改過的程式
  case "$(cd "$OPSX_ROOT" && pwd -P)/" in
    "$top"/*) warn "$top 裡有 opsx 程式碼（OPSX_ROOT=${OPSX_ROOT}）：登記後所有 session 都能改它，之後在沙盒外跑 opsx（看板、opsx answer --grant）就是執行被改過的程式碼；這是 opsx 自己的 repo 就照做，否則請確認" ;;
  esac
}

# opsx init --check：只讀。使用者層 settings 缺標準設定的項目就逐項印出、exit 1；在 repo 裡再看該 repo 是否在可寫目錄、有沒有信任，
# 裝了 opsx schema 的 repo 再比 spec 範本與 specs 區塊是不是插件版
init_check() {
  local file out rc=0 top args=()
  file="$(claude_settings_file)"
  top="$(git_toplevel)"
  [ -z "$top" ] || args+=(--add-dir "$top")
  out="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/claude-settings.py" --file "$file" --template "$OPSX_ROOT/templates/settings.opsx.json" ${args[@]+"${args[@]}"} --check)" || rc=$?
  case "$rc" in
    0) say "init --check: ${file} 與標準設定一致" ;;
    3) printf '%s\n' "$out"; say "init --check: ${file} 和標準設定不一致，上面是缺的項目。全域的跑 opsx init --global，repo 的在那個 repo 根目錄跑 opsx init" ;;
    *) die "init --check: 比對失敗（上面是原因）" ;;
  esac
  warn_skill_clashes
  # rehash 正常只持續數秒；5 分鐘內的可能還在跑，不報
  local lock="$HOME/.pyenv/shims/.pyenv-shim"
  if [ -n "$(find "$lock" -mmin +5 2>/dev/null)" ]; then
    say "init --check: ${lock} 是 pyenv rehash 的鎖檔，已存在超過 5 分鐘，多半是 rehash 被中斷後殘留；它會讓每個新 shell 卡在等鎖（dispatch 的新 pane 起不來）。確認沒有 rehash 在跑再刪掉它"
    rc=1
  fi
  [ -z "$top" ] || warn_untrusted "$top"
  local dst="$top/openspec/schemas/opsx" overlay="$OPSX_ROOT/schemas/opsx" spec_rc=0 block
  if [ -n "$top" ] && [ -d "$dst" ]; then
    cmp -s "$dst/templates/spec.md" "$overlay/templates/spec.md" \
      || { say "init --check: $dst/templates/spec.md 的 spec 範本與插件版不同"; spec_rc=1; }
    if [ ! -f "$dst/schema.yaml" ]; then
      say "init --check: $dst/schema.yaml 不在"; spec_rc=1
    elif ! block="$(specs_block "$dst/schema.yaml" 2>&1)"; then
      say "init --check: $dst/schema.yaml 讀不到 specs 區塊（${block}）"; spec_rc=1
    elif [ "$block" != "$(cat "$overlay/artifacts-specs.yaml")" ]; then
      say "init --check: $dst/schema.yaml 的 specs instruction 與插件版不同"; spec_rc=1
    fi
    [ "$spec_rc" = 0 ] || say "init --check: 在 $top 跑 opsx init 換成插件版"
  fi
  [ "$rc" = 0 ] && [ "$spec_rc" = 0 ]
}

# 兩支 launchd job：每天 09:00 跑 opsx sync（board-inbox），每 5 分鐘跑一輪 opsx coordinate（opsx-coordinate）。
# launchd 的 PATH 只有 /usr/bin:/bin，找不到 glab / gh、pyenv 的 python3（要 3.11 的 tomllib）、nvm 的 openspec，所以把這些目錄寫進 plist。
# coordinate 另帶 HERDR_ENV=1：collect 已不看它，留著只因無害（status.sh 的 pane metadata 鏡像才認它）。
# OPSX_LAUNCH_AGENTS_DIR / OPSX_LAUNCHCTL 讓測試不碰真的 ~/Library 與 launchctl。
install_launch_jobs() { # <state> <bindir>
  local state="$1" bindir="$2" lc="${OPSX_LAUNCHCTL:-launchctl}"
  if ! command -v "$lc" >/dev/null 2>&1; then say "init --global: 沒有 launchctl（不是 macOS），每日同步與 coordinate 略過，要跑就手動 opsx sync / opsx coordinate"; return; fi
  local path d
  path="$bindir:/opt/homebrew/bin"
  for d in "$(dirname "$(cat "$state/python")")" "$(dirname "$(command -v openspec 2>/dev/null || echo /usr/bin/x)")" /usr/local/bin /usr/bin /bin; do
    case ":$path:" in *":$d:"*) ;; *) path="$path:$d" ;; esac
  done
  install_launch_job "$lc" "$state" "$bindir" "$path" com.opsx.sync sync 每日同步 "每天 09:00" \
    '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>' ''
  install_launch_job "$lc" "$state" "$bindir" "$path" com.opsx.coordinate coordinate coordinate "每 5 分鐘" \
    '<key>StartInterval</key><integer>300</integer>' '<key>HERDR_ENV</key><string>1</string>'
}

install_launch_job() { # <launchctl> <state> <bindir> <PATH> <label> <opsx 子命令> <名稱> <時間說明> <排程 plist 片段> <額外環境變數 plist 片段>
  local lc="$1" state="$2" bindir="$3" path="$4" label="$5" cmd="$6" name="$7" when="$8" schedule="$9" env="${10}"
  local dir="${OPSX_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
  local plist="$dir/$label.plist" domain="gui/$(id -u)" out="$state/$cmd.out"
  ensure_dir "$dir"
  cat > "$plist.tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$bindir/opsx</string><string>$cmd</string></array>
  $schedule
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$path</string><key>OPSX_STATE_DIR</key><string>$state</string>$env</dict>
  <key>StandardOutPath</key><string>$out</string>
  <key>StandardErrorPath</key><string>$out</string>
</dict>
</plist>
EOF
  local changed=1
  if cmp -s "$plist.tmp" "$plist"; then changed=0; rm "$plist.tmp"; say "init --global: $plist 已有"
  else mv "$plist.tmp" "$plist"; say "init --global: 寫 ${plist}（${name}，${when}）"; fi
  # launchd 只在 bootstrap 時讀 plist：已載入而內容變了，要先 bootout 才會用新的 PATH
  if "$lc" print "$domain/$label" >/dev/null 2>&1 && [ "$changed" = 1 ]; then
    "$lc" bootout "$domain/$label" || die "init --global: launchctl bootout $domain/$label 失敗"
  fi
  if "$lc" print "$domain/$label" >/dev/null 2>&1 && [ "$changed" = 0 ]; then
    say "init --global: ${name} $label 已載入"
  elif "$lc" bootstrap "$domain" "$plist"; then
    say "init --global: ${name} $label 載入了，${when}跑 opsx ${cmd}，輸出在 $out"
  else
    die "init --global: launchctl bootstrap $domain $plist 失敗"
  fi
}

ask_global_sources() {
  local f="$1" ans folder
  if ! grep -q '^\[obsidian\]' "$f"; then
    printf 'obsidian vault 的絕對路徑（直接 Enter 跳過）：'
    read -r ans
    if [ -n "$ans" ]; then
      printf 'vault 裡當收件夾的子資料夾（例 01-Projects/inbox）：'
      read -r folder
      if [ -z "$folder" ]; then
        say "init --global: 沒給子資料夾，obsidian 沒登記（整個 vault 不當收件夾）"
      else
        case "$ans$folder" in
          *[[:cntrl:]]*)
            warn "init --global: vault 或子資料夾含控制字元（可能是打字時按了方向鍵），obsidian 沒登記；重跑 opsx init --global 再答一次" ;;
          *)
            printf '\n[obsidian]\nvault = "%s"\nfolder = "%s"\n' "$(toml_escape "$ans")" "$(toml_escape "$folder")" >> "$f"
            say "init --global: obsidian 已登記"
            # 照原樣寫入，不替使用者解讀路徑；拖進終端機的路徑帶的 \ 會原樣留著，在這裡就讓人看到
            [ -d "$ans/$folder" ] || warn "init --global: $ans/$folder 現在不是資料夾，同步時會記錯；路徑裡的 \\ 不會被當成跳脫，要改就編 $f" ;;
        esac
      fi
    fi
  fi
}

# TOML basic string 裡的 \ 與 " 要跳脫，不然含這兩個字元的路徑會寫出解析不了的 sources.toml
toml_escape() { # <text>
  local s="${1//\\/\\\\}"
  printf '%s' "${s//\"/\\\"}"
}

write_if_missing() { # <file> <content>
  if [ -f "$1" ]; then say "init --global: $(basename "$1") 已有"; else printf '%s' "$2" > "$1"; say "init --global: 建 $1"; fi
}

# ---------- repo 層 ----------
init_repo() {
  local top; top="$(git_toplevel)"
  [ -n "$top" ] || die "這裡不是 git repo（沒有 .git）。到 repo 根目錄再跑。"
  [ "$(git_worktree_top)" = "$(pwd -P)" ] || die "請在 repo 根目錄跑（linked worktree 的根也可以，openspec/ 會放在主 repo）：$top"
  command -v openspec >/dev/null || die "找不到 openspec CLI（npm i -g @fission-ai/openspec）"
  ensure_dir "$OPSX_STATE_DIR"
  refuse_broad_writable "$top"
  [ -f "$OPSX_STATE_DIR/sources.toml" ] || printf '# opsx 同步來源\n' > "$OPSX_STATE_DIR/sources.toml"
  [ -f "$OPSX_STATE_DIR/workspaces.toml" ] || printf '# repo ↔ herdr workspace\n[repos]\n' > "$OPSX_STATE_DIR/workspaces.toml"

  local name; name="$(basename "$top")"

  if [ -d "$top/openspec" ]; then
    say "init: openspec/ 已有"
  else
    openspec init --tools none "$top" >/dev/null
    say "init: openspec init 完成（--tools none，skill 由 opsx plugin 提供）"
  fi

  install_schema "$top"

  # openspec/ 不進 git：寫共用的 .git/info/exclude，不動 .gitignore
  local common; common="$(git_common_dir)"
  ensure_dir "$common/info"
  if grep -qxF 'openspec/' "$common/info/exclude" 2>/dev/null; then
    say "init: .git/info/exclude 已有 openspec/"
  else
    append_line_once "$common/info/exclude" 'openspec/'
    say "init: openspec/ 寫進 $common/info/exclude"
  fi

  register_source "$top" "$name"
  merge_claude_settings "$OPSX_PY" --add-dir "$top"
  warn_untrusted "$top"
  register_workspace "$name"
}

# fork 與 head 插入只做一次；範本與 specs 區塊每次都用插件版覆寫，插件更新後重跑 init 就會帶進 repo
install_schema() { # <top>
  local top="$1" dst="$1/openspec/schemas/opsx" overlay="$OPSX_ROOT/schemas/opsx"
  if [ -f "$dst/schema.yaml" ] && grep -q '^  - id: grill' "$dst/schema.yaml"; then
    say "init: schema opsx 已裝"
  else
    if [ ! -f "$dst/schema.yaml" ]; then
      ( cd "$top" && openspec schema fork spec-driven opsx >/dev/null )
    fi
    patch_schema "$dst/schema.yaml" "$overlay/artifacts-head.yaml"
    say "init: schema opsx 裝好（fork spec-driven + inbox / explore / grill）"
  fi
  # openspec/ 不進 git，覆寫前留一份；換區塊或驗證失敗就還原，已裝好的 repo 不會停在壞掉的 schema
  local bak; bak="$(mktemp -d "${TMPDIR:-/tmp}/opsx-schema.XXXXXX")"
  cp -R "$dst/templates" "$dst/schema.yaml" "$bak/"
  if ! refresh_schema "$top" "$dst" "$overlay"; then
    rm -rf "$dst/templates"; cp -R "$bak/templates" "$dst/templates"; cp "$bak/schema.yaml" "$dst/schema.yaml"
    rm -rf "$bak"
    die "init: 把 specs 區塊換成 $overlay/artifacts-specs.yaml 之後 schema opsx 驗證失敗（上面是原因），$dst/schema.yaml 與 templates/ 已還原"
  fi
  rm -rf "$bak"
  say "init: spec 範本與 specs instruction 更新為插件版"
}

refresh_schema() { # <top> <dst> <overlay>
  cp "$3/templates/"*.md "$2/templates/" \
    && specs_block "$2/schema.yaml" "$3/artifacts-specs.yaml" \
    && ( cd "$1" && openspec schema validate opsx >/dev/null )
}

# schema.yaml 的 specs 區塊：從 "  - id: specs" 起，連續縮排 4 格以上或空白的行，不含結尾的空行；
# 下一個 artifact 或任何頂層 key（例如 apply:）都在區塊外。
# 只給 <schema.yaml> 就印出區塊；多給 <new> 就把區塊換成那個檔的內容，寫 tmp 再換名。找不到區塊就失敗並點名檔案。
specs_block() { # <schema.yaml> [<new>]
  "$OPSX_PY" -I - "$@" <<'PY'
import os, re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
m = re.search(r'^  - id: specs\n(?:(?:    .*)?\n)*', s, re.M)
if not m: sys.exit(f"schema.yaml 沒有 '  - id: specs'：{p}")
end = m.start() + len(m.group(0).rstrip('\n')) + 1
if len(sys.argv) == 2: sys.stdout.write(s[m.start():end]); sys.exit()
new = open(sys.argv[2], encoding='utf-8').read()
open(p + '.tmp', 'w', encoding='utf-8').write(s[:m.start()] + new + s[end:])
os.replace(p + '.tmp', p)
PY
}

# 在 fork 出來的 schema.yaml 的 artifacts: 後面插入我們的三個 artifact；proposal 改成 requires explore。
# 純文字插入，不靠 yaml 函式庫；插完交給 openspec schema validate 把關。
patch_schema() { # <schema.yaml> <head.yaml>
  local f="$1" head="$2" tmp="$1.tmp"
  grep -q '^artifacts:' "$f" || die "schema.yaml 沒有 artifacts: 行：$f"
  awk -v head="$head" '
    /^artifacts:/ && !done { print; while ((getline line < head) > 0) print line; done=1; next }
    { print }
  ' "$f" > "$tmp"
  # proposal 改成 requires explore
  "$OPSX_PY" -I - "$tmp" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
m=re.search(r'(  - id: proposal\n(?:(?!  - id: ).*\n)*?)    requires: \[\]\n', s)
if not m: sys.exit("proposal artifact 的 requires: [] 找不到")
s=s[:m.start()]+m.group(1)+'    requires:\n      - explore\n'+s[m.end():]
s=s.replace('description: Default OpenSpec workflow - proposal → specs → design → tasks','description: opsx workflow - inbox → explore → (grill) → proposal → specs → design → tasks',1)
open(p,'w',encoding='utf-8').write(s)
PY
  mv "$tmp" "$f"
}

register_source() { # <top> <name>
  local top="$1" name="$2" f="$OPSX_STATE_DIR/sources.toml" url kind project
  if grep -qF "path = \"$top\"" "$f"; then say "init: sources.toml 已有 $name"; return; fi
  # Agentory-AI / Infrastructure 的 origin 是 GitHub 鏡像，MR 在名為 gitlab 的 remote；有它就以它為準
  url="$(git -C "$top" remote get-url gitlab 2>/dev/null || true)"
  [ -z "$url" ] && url="$(git -C "$top" remote get-url origin 2>/dev/null || true)"
  if [ -z "$url" ]; then say "init: 這個 repo 沒有 remote，sources.toml 不登記（之後加了 remote 再跑一次）"; return; fi
  case "$url" in
    *gitlab*) kind=gitlab ;;
    *github.com*) kind=github ;;
    *) say "init: remote 不是 gitlab / github（${url}），sources.toml 不登記"; return ;;
  esac
  project="$(printf '%s' "$url" | sed -E 's#^(git@|https?://)[^:/]+[:/]##; s#/$##; s#\.git$##')"
  printf '\n[[source]]\nkind = "%s"\nrepo = "%s"\nproject = "%s"\npath = "%s"\n' "$kind" "$name" "$project" "$top" >> "$f"
  say "init: sources.toml +$kind:$project"
}

register_workspace() { # <name>
  local name="$1" f="$OPSX_STATE_DIR/workspaces.toml" ans
  grep -q '^\[repos\]' "$f" || printf '\n[repos]\n' >> "$f"
  if grep -qE "^\"?$name\"? *=" "$f"; then say "init: workspaces.toml 已有 $name"; return; fi
  if interactive; then
    printf 'repo %s 掛哪個 herdr workspace？（填 herdr 的 workspace label，`herdr workspace list` 看得到；直接 Enter 跳過）：' "$name"
    read -r ans
    if [ -n "$ans" ]; then
      printf '"%s" = "%s"\n' "$name" "$ans" >> "$f"
      say "init: workspaces.toml $name → $ans"
      return
    fi
  fi
  say "init: workspace 沒掛（指派時會自動記，或改 ${f}）"
}
