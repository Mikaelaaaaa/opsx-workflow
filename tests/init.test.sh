#!/usr/bin/env bash
# opsx init：repo 層與 --global。對應要求檔 §3.6「CLI helper」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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

# --- 重跑是 no-op：檔案內容不變、不重複登記 ---
before="$(cat "$OPSX_STATE_DIR/sources.toml" "$R/.git/info/exclude")"
out2="$(opsx init 2>&1)"; assert_eq "$?" 0 "rerun rc"
after="$(cat "$OPSX_STATE_DIR/sources.toml" "$R/.git/info/exclude")"
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

# --- --global ---
cd "$FX"; use_fakes herdr launchctl; export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_LAUNCHCTL=launchctl   # lib.sh 預設沒有 launchctl；這裡用 fake 測安裝
outg="$(opsx init --global 2>&1)"; assert_eq "$?" 0 "global rc: $outg"
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
for d in "$OPSX_BIN_DIR" /opt/homebrew/bin "$(dirname "$(command -v python3)")" "$(dirname "$(command -v openspec)")"; do
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
echo ok
