#!/usr/bin/env bash
# opsx init：repo 層（在 repo 根目錄跑）與 --global（裝一次）。要求檔 §3.6「CLI helper」。
# 重跑一律 no-op。所有寫入前先檢查，已有就印「已有」。

opsx_init() {
  case "${1:-}" in
    --global) init_global ;;
    "") init_repo ;;
    *) die "init 只接受 --global，收到：$1" ;;
  esac
}

# ---------- 全域 ----------
init_global() {
  local state="$OPSX_STATE_DIR" bindir="${OPSX_BIN_DIR:-$HOME/.local/bin}"
  # collect / answer / hooks 用 tomllib，要 3.11+；macOS 內建 /usr/bin/python3 是 3.9。現在不講，第二台機器會 502 到底。
  python3 -I -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null \
    || die "init --global: PATH 上的 python3 要 3.11 以上（有 tomllib），現在是 $(python3 --version 2>&1)。pyenv 或 brew 裝一個再跑"
  ensure_dir "$state"; ensure_dir "$bindir"

  write_if_missing "$state/sources.toml" '# opsx 同步來源。opsx init 在每個 repo 跑時會自動補 gitlab / github；obsidian、customer 在這裡填。
# [obsidian]
# vault = "/path/to/vault"
# folder = "01-Projects/inbox"
# [customer]
# base_url = ""
# token_env = "CUSTOMER_API_TOKEN"
# list_endpoint = "/api/reports?status=open"
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
    say "init --global: 非互動，obsidian / customer 來源略過（之後改 $state/sources.toml）"
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
  say "init --global: launchd 每日同步在 board-inbox 那張卡才裝，略過"
  say "init --global: 設定在 $state"
}

ask_global_sources() {
  local f="$1" ans
  if ! grep -q '^\[obsidian\]' "$f"; then
    printf 'obsidian 要掃的資料夾（vault 絕對路徑/子資料夾，直接 Enter 跳過）：'
    read -r ans
    if [ -n "$ans" ]; then
      printf '\n[obsidian]\nvault = "%s"\nfolder = "%s"\n' "${ans%%/[0-9]*}" "${ans#*/}" >> "$f"
      say "init --global: obsidian 已登記（請打開檔案確認 vault / folder 切得對）"
    fi
  fi
  if ! grep -q '^\[customer\]' "$f"; then
    printf 'customer 平台 base URL（直接 Enter 跳過）：'
    read -r ans
    if [ -n "$ans" ]; then
      local tok ep
      printf 'token 的環境變數名：'; read -r tok
      printf '列表端點（例 /api/reports?status=open）：'; read -r ep
      printf '\n[customer]\nbase_url = "%s"\ntoken_env = "%s"\nlist_endpoint = "%s"\n' "$ans" "$tok" "$ep" >> "$f"
      say "init --global: customer 已登記"
    fi
  fi
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
  register_workspace "$name"
}

install_schema() { # <top>
  local top="$1" dst="$1/openspec/schemas/opsx" overlay="$OPSX_ROOT/schemas/opsx"
  if [ -f "$dst/schema.yaml" ] && grep -q '^  - id: grill' "$dst/schema.yaml"; then
    say "init: schema opsx 已裝"; return
  fi
  if [ ! -f "$dst/schema.yaml" ]; then
    ( cd "$top" && openspec schema fork spec-driven opsx >/dev/null )
  fi
  patch_schema "$dst/schema.yaml" "$overlay/artifacts-head.yaml"
  cp "$overlay/templates/"*.md "$dst/templates/"
  ( cd "$top" && openspec schema validate opsx >/dev/null ) || die "schema opsx 裝完驗證失敗：$dst/schema.yaml"
  say "init: schema opsx 裝好（fork spec-driven + inbox / explore / grill）"
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
  python3 -I - "$tmp" <<'PY'
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
