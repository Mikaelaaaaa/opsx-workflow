#!/usr/bin/env bash
# opsx init：repo 層與 --global。對應要求檔 §3.6「CLI helper」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# 取 JSON 裡某個路徑（點分隔）的值，印成 JSON；不存在印 MISSING
cj() { python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    if not isinstance(d, dict) or k not in d:
        print("MISSING"); sys.exit(0)
    d = d[k]
print(json.dumps(d))' "$1" "$2"; }
# repo 層會把 repo 路徑寫進使用者層 settings：這段用自己的 settings 目錄，與後面 --global 的斷言分開
export CLAUDE_CONFIG_DIR="$FX/cc-repo"; CR="$CLAUDE_CONFIG_DIR/settings.json"

# --- 邊界：不在 git repo 裡 → 拒絕，什麼都不建 ---
mkdir -p "$FX/plain"; cd "$FX/plain"
assert_rc 2 opsx init
assert_no_file "$FX/plain/openspec"

# --- 邊界：沒參數的 opsx → 印用法，rc 2；未知子命令 rc 2 ---
assert_rc 2 opsx
assert_rc 2 opsx nope

# --- repo 層：gitlab remote ---
R="$(mk_repo Agentory-CS git@gitlab.tsg-navigator.com:agentory/Agentory-CS.git)"
cd "$R"
out="$(opsx init 2>&1)"; rc=$?
assert_eq "$rc" 0 "init rc: $out"
assert_dir "$R/openspec/changes/archive"                 # openspec init 做的
assert_file "$R/openspec/schemas/opsx/schema.yaml"       # 我們的 schema 裝進 repo
assert_grep "id: inbox" "$R/openspec/schemas/opsx/schema.yaml"
assert_grep "id: explore" "$R/openspec/schemas/opsx/schema.yaml"
assert_grep "id: grill" "$R/openspec/schemas/opsx/schema.yaml"
assert_file "$R/openspec/schemas/opsx/templates/inbox.md"
assert_file "$R/openspec/schemas/opsx/templates/explore.md"
assert_file "$R/openspec/schemas/opsx/templates/grill.md"
assert_grep "驗收：" "$R/openspec/schemas/opsx/templates/tasks.md"   # tasks 模板帶 驗收 / 測試 兩行
assert_grep "測試：" "$R/openspec/schemas/opsx/templates/tasks.md"
assert_grep "## Out of Scope" "$R/openspec/schemas/opsx/templates/proposal.md"   # proposal 模板蓋掉 fork 的
assert_grep "去重" "$R/openspec/schemas/opsx/schema.yaml"
( cd "$R" && openspec schema validate opsx >/dev/null 2>&1 ) || fail "forked schema invalid"
assert_grep "^openspec/$" "$R/.git/info/exclude"           # 不進 git，不動 .gitignore
assert_no_file "$R/.gitignore"
assert_file "$OPSX_STATE_DIR/sources.toml"
assert_grep 'kind = "gitlab"' "$OPSX_STATE_DIR/sources.toml"
assert_grep 'repo = "Agentory-CS"' "$OPSX_STATE_DIR/sources.toml"
assert_grep "path = \"$R\"" "$OPSX_STATE_DIR/sources.toml"
assert_file "$OPSX_STATE_DIR/workspaces.toml"               # 非互動：建檔但不掛
assert_not_grep "Agentory-CS" "$OPSX_STATE_DIR/workspaces.toml"
# 該 repo 加進使用者層可寫目錄；範圍只到 repo，不含父目錄
assert_eq "$(cj "$CR" permissions.additionalDirectories)" "[\"$R\"]"

# 資料夾沒信任過（沒有 .claude.json）：警告，說怎麼處理，也說 opsx 不替你改
case "$out" in *還沒信任*) ;; *) fail "沒信任的 repo 要警告：$out" ;; esac
case "$out" in *不會替你改*) ;; *) fail "警告要說 opsx 不改信任紀錄：$out" ;; esac
printf '{"projects": {"%s": {"hasTrustDialogAccepted": true}}}' "$R" > "$CLAUDE_CONFIG_DIR/.claude.json"
trust_before="$(cat "$CLAUDE_CONFIG_DIR/.claude.json")"

# --- 重跑是 no-op：檔案內容不變、不重複登記 ---
before="$(cat "$OPSX_STATE_DIR/sources.toml" "$R/.git/info/exclude" "$CR")"
out2="$(opsx init 2>&1)"; assert_eq "$?" 0 "rerun rc"
case "$out2" in *還沒信任*) fail "已信任的 repo 不該警告：$out2" ;; esac
assert_eq "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" "$trust_before" "opsx 不能改信任紀錄"
after="$(cat "$OPSX_STATE_DIR/sources.toml" "$R/.git/info/exclude" "$CR")"
assert_eq "$after" "$before" "rerun changed files"
assert_eq "$(grep -c 'repo = "Agentory-CS"' "$OPSX_STATE_DIR/sources.toml")" 1 "duplicate registration"

# --- 邊界：已有 openspec/（既有 repo）→ 不重跑 openspec init，只補 schema 和登記 ---
R2="$(mk_repo scam-guard https://github.com/Mikaelaaaaa/scam-guard.git)"
mkdir -p "$R2/openspec/changes/archive" "$R2/openspec/specs"; echo keep > "$R2/openspec/specs/marker"
cd "$R2"; opsx init >/dev/null 2>&1 || fail "init on existing openspec"
assert_file "$R2/openspec/specs/marker"
assert_grep 'kind = "github"' "$OPSX_STATE_DIR/sources.toml"
assert_grep 'repo = "scam-guard"' "$OPSX_STATE_DIR/sources.toml"

# --- origin 是 GitHub 鏡像、gitlab 才是開 MR 的 remote → 登記 gitlab ---
R4="$(mk_repo Agentory-AI https://github.com/agentory-ai/Agentory-AI.git)"
git -C "$R4" remote add gitlab https://gitlab.tsg-navigator.com/agentory/agentory-ai.git
cd "$R4"; opsx init >/dev/null 2>&1 || fail "init with two remotes"
assert_grep 'project = "agentory/agentory-ai"' "$OPSX_STATE_DIR/sources.toml"
assert_not_grep 'project = "agentory-ai/Agentory-AI"' "$OPSX_STATE_DIR/sources.toml"
assert_eq "$(grep -A3 'repo = "Agentory-AI"' "$OPSX_STATE_DIR/sources.toml" | grep -c 'kind = "gitlab"')" 0 "kind line is above repo line"
assert_eq "$(grep -B1 'repo = "Agentory-AI"' "$OPSX_STATE_DIR/sources.toml" | grep -c 'kind = "gitlab"')" 1 "Agentory-AI should be gitlab"

# --- 邊界：只有 origin 且 URL 帶尾斜線 → project 不帶尾斜線 ---
R5="$(mk_repo slashy https://github.com/x/slashy/)"
cd "$R5"; opsx init >/dev/null 2>&1 || fail "init with trailing slash"
assert_grep 'project = "x/slashy"' "$OPSX_STATE_DIR/sources.toml"
assert_not_grep 'project = "x/slashy/"' "$OPSX_STATE_DIR/sources.toml"

# --- 邊界：沒 remote 的 repo → 仍可 init，sources 不登記，印一行說明 ---
R3="$(mk_repo local-only)"; cd "$R3"
out3="$(opsx init 2>&1)"; assert_eq "$?" 0 "no-remote rc"
assert_not_grep 'repo = "local-only"' "$OPSX_STATE_DIR/sources.toml"
echo "$out3" | grep -q "remote" || fail "should mention no remote: $out3"

# --- 邊界：在 worktree 裡跑 → exclude 寫到共用的 .git/info/exclude，不是 worktree 自己的 ---
cd "$R"; git -C "$R" worktree add -q "$FX/wt" -b feat/x/mikaela
cd "$FX/wt"; out="$(opsx init 2>&1)" || fail "init in worktree: $out"
assert_eq "$(grep -c '^openspec/$' "$R/.git/info/exclude")" 1 "exclude duplicated or missing via worktree"
# linked worktree 加的是主 repo，不是 worktree 自己；多個 repo 各出現一次
dirs="$(cj "$CR" permissions.additionalDirectories)"
case "$dirs" in *"\"$FX/wt\""*) fail "不該把 worktree 路徑加進可寫目錄：$dirs" ;; esac
assert_eq "$(printf '%s' "$dirs" | grep -o "\"$R\"" | wc -l | tr -d ' ')" 1 "主 repo 要剛好出現一次：$dirs"
for r in "$R2" "$R3" "$R4" "$R5"; do
  case "$dirs" in *"\"$r\""*) ;; *) fail "$r 沒進可寫目錄：$dirs" ;; esac
done

# --- 守衛：可寫目錄不能是 $HOME、$HOME 的上層、state 目錄的上層（家目錄是 git repo 的人跑 opsx init）---
RH="$(mk_repo hrepo)"; cd "$RH"
outh="$(HOME="$RH" opsx init 2>&1)" && fail "repo 就是 \$HOME 時 opsx init 要失敗：$outh"
case "$outh" in *"$RH"*) ;; *) fail "訊息要點名路徑：$outh" ;; esac
RP="$(mk_repo pp)"; mkdir -p "$RP/home"; cd "$RP"
outh="$(HOME="$RP/home" opsx init 2>&1)" && fail "repo 是 \$HOME 的上層時 opsx init 要失敗：$outh"
RS="$(mk_repo sp)"; cd "$RS"
outh="$(OPSX_STATE_DIR="$RS/state" opsx init 2>&1)" && fail "repo 是 state 目錄的上層時 opsx init 要失敗：$outh"
dirs="$(cj "$CR" permissions.additionalDirectories)"
for r in "$RH" "$RP" "$RS"; do
  case "$dirs" in *"\"$r\""*) fail "$r 不該進可寫目錄：$dirs" ;; esac
done
assert_no_file "$RH/openspec"   # 守衛在寫任何東西之前

# --- --global ---
export CLAUDE_CONFIG_DIR="$FX/claude-config"   # repo 層那段用 $FX/cc-repo，這裡換回乾淨的
cd "$FX"; use_fakes herdr launchctl; export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_LAUNCHCTL=launchctl   # lib.sh 預設沒有 launchctl；這裡用 fake 測安裝
rm -f "$OPSX_STATE_DIR/python"
outg="$(opsx init --global 2>&1)"; assert_eq "$?" 0 "global rc: $outg"
PY="$(python3 -I -c 'import sys;print(sys.executable)')"
assert_eq "$(cat "$OPSX_STATE_DIR/python")" "$PY" "init --global 要記下 python3 的 sys.executable"
[ -x "$(cat "$OPSX_STATE_DIR/python")" ] || fail "記下的 python 不能執行"
case "$outg" in *"$PY"*) ;; *) fail "輸出要說寫了哪個 python：$outg" ;; esac
case "$outg" in *"herdr plugin link"*) ;; *) fail "should say plugin linked: $outg" ;; esac
case "$outg" in *'"linked"'*) fail "herdr JSON leaked into output: $outg" ;; esac
assert_file "$OPSX_STATE_DIR/grants.toml"
assert_file "$OPSX_STATE_DIR/workspaces.toml"
[ -L "$OPSX_BIN_DIR/opsx" ] || fail "symlink missing"
assert_eq "$(readlink "$OPSX_BIN_DIR/opsx")" "$OPSX_ROOT/bin/opsx"
# 重跑：symlink 不報錯、檔案不清空
echo 'x = 1' >> "$OPSX_STATE_DIR/grants.toml"
opsx init --global >/dev/null 2>&1 || fail "global rerun"
assert_grep "x = 1" "$OPSX_STATE_DIR/grants.toml"

# --- 沙盒權限：裝進 CLAUDE_CONFIG_DIR/settings.json（specs/opsx-init「--global 把沙盒權限裝進使用者層」）---
CS="$CLAUDE_CONFIG_DIR/settings.json"
assert_file "$CS"
assert_eq "$(cj "$CS" permissions.additionalDirectories)" "[\"$OPSX_STATE_DIR\"]"
assert_eq "$(cj "$CS" sandbox.network.allowUnixSockets)" "[\"$HOME/.config/herdr/herdr.sock\"]"
assert_eq "$(cj "$CS" sandbox.excludedCommands)" '["gh pr *"]' "只排除 gh pr *，不是整個 gh *"
assert_eq "$(cj "$CS" sandbox.filesystem.denyWrite)" "[\"$OPSX_STATE_DIR/grants.toml\", \"$OPSX_STATE_DIR/dispatch.json\", \"$OPSX_STATE_DIR/dispatch.json.lock\", \"$OPSX_STATE_DIR/python\"]" "授權檔與 hook 執行的 interpreter 路徑要拒絕沙盒寫入"
assert_eq "$(cj "$CS" sandbox.enabled)" MISSING "不替使用者開關沙盒"
assert_no_file "$CS.opsx-bak"        # 第一次裝，原檔不存在，沒有東西可備份
before="$(cat "$CS")"
outs="$(opsx init --global 2>&1)"; assert_eq "$?" 0 "settings rerun: $outs"
assert_eq "$(cat "$CS")" "$before" "重跑改了 settings.json"
assert_no_file "$CS.opsx-bak"        # no-op 不產生備份

# CLAUDE_CONFIG_DIR 沒設：寫 $HOME/.claude/settings.json
mkdir -p "$FX/home"
env HOME="$FX/home" CLAUDE_CONFIG_DIR= opsx init --global >/dev/null 2>&1 || fail "global without CLAUDE_CONFIG_DIR"
assert_file "$FX/home/.claude/settings.json"
assert_eq "$(cj "$FX/home/.claude/settings.json" sandbox.network.allowUnixSockets)" "[\"$FX/home/.config/herdr/herdr.sock\"]"

# 使用者已有設定：保留、追加、備份原檔
mkdir -p "$FX/cc2"
printf '{"sandbox":{"enabled":true,"network":{"allowUnixSockets":["/other.sock"]}},"theme":"dark"}' > "$FX/cc2/settings.json"
orig="$(cat "$FX/cc2/settings.json")"
CLAUDE_CONFIG_DIR="$FX/cc2" opsx init --global >/dev/null 2>&1 || fail "global with existing settings"
assert_eq "$(cj "$FX/cc2/settings.json" theme)" '"dark"'
assert_eq "$(cj "$FX/cc2/settings.json" sandbox.enabled)" true
assert_eq "$(cj "$FX/cc2/settings.json" sandbox.network.allowUnixSockets)" "[\"/other.sock\", \"$HOME/.config/herdr/herdr.sock\"]"
assert_eq "$(cat "$FX/cc2/settings.json.opsx-bak")" "$orig" "備份要是原內容"

# 標準設定（templates/settings.opsx.json）是唯一來源：裝出來的 allow 與範本逐項相同，兩個乾淨環境裝出來一模一樣
assert_eq "$(cj "$CS" permissions.allow)" "$(cj "$OPSX_ROOT/templates/settings.opsx.json" permissions.allow)"
CLAUDE_CONFIG_DIR="$FX/cc3" opsx init --global >/dev/null 2>&1 || fail "global second dir"
assert_eq "$(cat "$FX/cc3/settings.json")" "$(cat "$CS")" "兩個環境裝出來的 settings 要一致"

# settings.json 壞掉：整個 init --global 失敗，檔案不動
mkdir -p "$FX/cc4"; printf '{"sandbox": ' > "$FX/cc4/settings.json"
outb="$(CLAUDE_CONFIG_DIR="$FX/cc4" opsx init --global 2>&1)" && fail "壞 JSON 時 init --global 要失敗：$outb"
case "$outb" in *"$FX/cc4/settings.json"*) ;; *) fail "訊息要含檔名：$outb" ;; esac
assert_eq "$(cat "$FX/cc4/settings.json")" '{"sandbox": ' "壞 JSON 被改了"
assert_no_file "$FX/cc4/settings.json.opsx-bak"

# --- init --check：比對機器 / repo 的設定與標準設定，只讀 ---
cd "$FX"
outc="$(opsx init --check 2>&1)"; assert_eq "$?" 0 "裝完的機器 --check 要過：$outc"
case "$outc" in *一致*) ;; *) fail "一致時要說一致：$outc" ;; esac
mkdir -p "$FX/cc5"; printf '{"theme":"dark"}' > "$FX/cc5/settings.json"
before="$(cat "$FX/cc5/settings.json")"
outc="$(CLAUDE_CONFIG_DIR="$FX/cc5" opsx init --check 2>&1)"; rc=$?
assert_eq "$rc" 1 "沒裝的機器 --check 要失敗：$outc"
case "$outc" in *permissions.additionalDirectories*"$OPSX_STATE_DIR"*) ;; *) fail "要印缺哪一項：$outc" ;; esac
case "$outc" in *opsx\ init\ --global*) ;; *) fail "要說怎麼補：$outc" ;; esac
assert_eq "$(cat "$FX/cc5/settings.json")" "$before" "--check 改了檔"
assert_no_file "$FX/cc5/settings.json.opsx-bak"
# repo 層：該 repo 在可寫目錄才算齊；沒信任的 repo 多一行警告但不算不一致
CLAUDE_CONFIG_DIR="$FX/cc6" opsx init --global >/dev/null 2>&1 || fail "global for cc6"
cd "$R"
outc="$(CLAUDE_CONFIG_DIR="$FX/cc6" opsx init --check 2>&1)"; rc=$?
assert_eq "$rc" 1 "repo 沒登記時 --check 要失敗：$outc"
case "$outc" in *"$R"*) ;; *) fail "要印缺的 repo 路徑：$outc" ;; esac
CLAUDE_CONFIG_DIR="$FX/cc6" opsx init >/dev/null 2>&1 || fail "init in cc6"
outc="$(CLAUDE_CONFIG_DIR="$FX/cc6" opsx init --check 2>&1)"; assert_eq "$?" 0 "登記後 --check 要過：$outc"
case "$outc" in *還沒信任*) ;; *) fail "cc6 沒有信任紀錄，--check 要警告：$outc" ;; esac
cd "$FX"

# --- 每日同步 launchd：第一次安裝 ---
PL="$OPSX_LAUNCH_AGENTS_DIR/com.opsx.sync.plist"
assert_file "$PL"
case "$outg" in *每日同步*) ;; *) fail "輸出要有每日同步那行：$outg" ;; esac
pl() { python3 -I -c 'import json,plistlib,sys
d=plistlib.load(open(sys.argv[1],"rb"))
for k in sys.argv[2].split("."): d=d[k]
print(d if isinstance(d,str) else json.dumps(d))' "$PL" "$1"; }
assert_eq "$(pl ProgramArguments)" "[\"$OPSX_BIN_DIR/opsx\", \"sync\"]"
assert_eq "$(pl StartCalendarInterval)" '{"Hour": 9, "Minute": 0}'
assert_eq "$(pl StandardOutPath)" "$OPSX_STATE_DIR/sync.out"; assert_eq "$(pl StandardErrorPath)" "$OPSX_STATE_DIR/sync.out"
assert_eq "$(pl EnvironmentVariables.OPSX_STATE_DIR)" "$OPSX_STATE_DIR"
P="$(pl EnvironmentVariables.PATH)"
for d in "$OPSX_BIN_DIR" /opt/homebrew/bin "$(dirname "$(cat "$OPSX_STATE_DIR/python")")" "$(dirname "$(command -v openspec)")"; do
  case ":$P:" in *":$d:"*) ;; *) fail "plist 的 PATH 少了 $d：$P" ;; esac
done
assert_grep "^bootstrap gui/$(id -u) $PL\$" "$OPSX_FAKE_LOG"

# --- 已經裝過：launchctl print 成功就不重載 ---
: > "$OPSX_FAKE_LOG"
OPSX_TEST_LAUNCHCTL_LOADED=1 opsx init --global >/dev/null 2>&1 || fail "global with loaded job"
assert_grep '^print gui/' "$OPSX_FAKE_LOG"; assert_not_grep '^bootstrap' "$OPSX_FAKE_LOG"

# --- 已載入但 plist 內容變了（例如 nvm / pyenv 升級後重跑）：先 bootout 再 bootstrap，launchd 才會讀新的 ---
printf '<!-- 舊的 -->\n' > "$PL"; : > "$OPSX_FAKE_LOG"
OPSX_TEST_LAUNCHCTL_LOADED=1 opsx init --global >/dev/null 2>&1 || fail "global with changed plist"
assert_grep "^bootout gui/$(id -u)/com.opsx.sync\$" "$OPSX_FAKE_LOG"; assert_grep '^bootstrap' "$OPSX_FAKE_LOG"

# --- 沒有 launchctl：印一行略過，退出 0 ---
outn="$(OPSX_LAUNCHCTL="$FX/no-such-launchctl" opsx init --global 2>&1)"; assert_eq "$?" 0 "no launchctl rc: $outn"
case "$outn" in *略過*) ;; *) fail "沒有 launchctl 要說略過：$outn" ;; esac

# python 路徑：相同就不動，不同就覆寫並印新舊
outg="$(opsx init --global 2>&1)"; case "$outg" in *"python 已有"*) ;; *) fail "路徑相同要說已有：$outg" ;; esac
printf '/nonexistent/python3\n' > "$OPSX_STATE_DIR/python"
outg="$(opsx init --global 2>&1)"; assert_eq "$?" 0 "global with stale python: $outg"
assert_eq "$(cat "$OPSX_STATE_DIR/python")" "$PY" "路徑變了要覆寫"
case "$outg" in *"/nonexistent/python3"*"$PY"*) ;; *) fail "覆寫要印舊路徑與新路徑：$outg" ;; esac

# python 路徑：PATH 上的 python3 在 venv 裡 → 記 base，venv 刪掉後 opsx 照常（python-venv-guard）
"$PY" -m venv --without-pip "$FX/venv" || fail "建 fixture venv 失敗"
VBASE="$("$FX/venv/bin/python3" -I -c 'import sys; print(sys._base_executable)')"
case "$VBASE" in "$FX/venv"/*) fail "fixture 的 base 不該在 venv 裡：$VBASE" ;; esac
outg="$(PATH="$FX/venv/bin:$PATH" opsx init --global 2>&1)"; assert_eq "$?" 0 "venv 裡 init --global: $outg"
assert_eq "$(cat "$OPSX_STATE_DIR/python")" "$VBASE" "venv 裡要記 base interpreter"
case "$outg" in *venv*"$VBASE"*) ;; *) fail "輸出要提 venv 和改記的 base：$outg" ;; esac
rm -rf "$FX/venv"
opsx collect --root "$FX" > /dev/null 2> "$FX/err" || fail "venv 刪掉後 collect 失敗：$(cat "$FX/err")"

# python 路徑：venv 裡拿不到可用的 base → 失敗，不動 python 檔
# 假 python3 照常跑 -I -c 的程式，只先把 sys.prefix、sys._base_executable 換成 FAKE_PREFIX、FAKE_BASE
mkdir -p "$FX/fakevenv"
cat > "$FX/fakevenv/python3" <<EOF
#!/usr/bin/env bash
[ "\$1" = -I ] && [ "\$2" = -c ] || { echo "fake python3 只支援 -I -c：\$*" >&2; exit 2; }
exec "$PY" -I -c "import sys; sys.prefix = '\$FAKE_PREFIX'; sys._base_executable = '\$FAKE_BASE'
\$3"
EOF
chmod +x "$FX/fakevenv/python3"
printf '/sentinel/python3\n' > "$OPSX_STATE_DIR/python"
outg="$(PATH="$FX/fakevenv:$PATH" FAKE_PREFIX=/fake/venv FAKE_BASE=/nonexistent/base3 opsx init --global 2>&1)" \
  && fail "base 不存在時 init --global 要失敗：$outg"
case "$outg" in *"/fake/venv"*"/nonexistent/base3"*|*"/nonexistent/base3"*"/fake/venv"*) ;; *) fail "訊息要寫 venv prefix 和拿到的 base：$outg" ;; esac
assert_eq "$(cat "$OPSX_STATE_DIR/python")" "/sentinel/python3" "base 不存在時 python 檔不能動"
outg="$(PATH="$FX/fakevenv:$PATH" FAKE_PREFIX=/fake/venv FAKE_BASE="$PY" opsx init --global 2>&1)" \
  && fail "base 等於 sys.executable 時 init --global 要失敗：$outg"
case "$outg" in *"/fake/venv"*"$PY"*) ;; *) fail "訊息要寫 venv prefix 和拿到的 base：$outg" ;; esac
assert_eq "$(cat "$OPSX_STATE_DIR/python")" "/sentinel/python3" "base 等於 sys.executable 時 python 檔不能動"
printf x > "$FX/noexec"; chmod 644 "$FX/noexec"
for b in "$FX/noexec" "$FX"; do   # 存在但不能執行、是目錄：都算拿不到
  outg="$(PATH="$FX/fakevenv:$PATH" FAKE_PREFIX=/fake/venv FAKE_BASE="$b" opsx init --global 2>&1)" \
    && fail "base 是 $b 時 init --global 要失敗：$outg"
  assert_eq "$(cat "$OPSX_STATE_DIR/python")" "/sentinel/python3" "base 是 $b 時 python 檔不能動"
done

# python 路徑：base 是 symlink 時原樣記，不解開（uv、brew 的 base 是 minor 版號的 symlink，解開會釘死 patch 版）
mkdir -p "$FX/baselink"; ln -s "$PY" "$FX/baselink/python3"
outg="$(PATH="$FX/fakevenv:$PATH" FAKE_PREFIX=/fake/venv FAKE_BASE="$FX/baselink/python3" opsx init --global 2>&1)"
assert_eq "$?" 0 "base 是 symlink 時 init --global: $outg"
assert_eq "$(cat "$OPSX_STATE_DIR/python")" "$FX/baselink/python3" "base 要原樣記，不解 symlink"
echo ok
