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
R="$(mk_repo Acmecorp-CS git@gitlab.example.com:acmecorp/Acmecorp-CS.git)"
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
assert_grep 'repo = "Acmecorp-CS"' "$OPSX_STATE_DIR/sources.toml"
assert_grep "path = \"$R\"" "$OPSX_STATE_DIR/sources.toml"
assert_file "$OPSX_STATE_DIR/workspaces.toml"               # 非互動：建檔但不掛
assert_not_grep "Acmecorp-CS" "$OPSX_STATE_DIR/workspaces.toml"
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
assert_eq "$(grep -c 'repo = "Acmecorp-CS"' "$OPSX_STATE_DIR/sources.toml")" 1 "duplicate registration"

# --- 邊界：已有 openspec/（既有 repo）→ 不重跑 openspec init，只補 schema 和登記 ---
R2="$(mk_repo scam-guard https://github.com/Mikaelaaaaa/scam-guard.git)"
mkdir -p "$R2/openspec/changes/archive" "$R2/openspec/specs"; echo keep > "$R2/openspec/specs/marker"
cd "$R2"; opsx init >/dev/null 2>&1 || fail "init on existing openspec"
assert_file "$R2/openspec/specs/marker"
assert_grep 'kind = "github"' "$OPSX_STATE_DIR/sources.toml"
assert_grep 'repo = "scam-guard"' "$OPSX_STATE_DIR/sources.toml"

# --- origin 是 GitHub 鏡像、gitlab 才是開 MR 的 remote → 登記 gitlab ---
R4="$(mk_repo Acmecorp-AI https://github.com/acmecorp-ai/Acmecorp-AI.git)"
git -C "$R4" remote add gitlab https://gitlab.example.com/acmecorp/acmecorp-ai.git
cd "$R4"; opsx init >/dev/null 2>&1 || fail "init with two remotes"
assert_grep 'project = "acmecorp/acmecorp-ai"' "$OPSX_STATE_DIR/sources.toml"
assert_not_grep 'project = "acmecorp-ai/Acmecorp-AI"' "$OPSX_STATE_DIR/sources.toml"
assert_eq "$(grep -A3 'repo = "Acmecorp-AI"' "$OPSX_STATE_DIR/sources.toml" | grep -c 'kind = "gitlab"')" 0 "kind line is above repo line"
assert_eq "$(grep -B1 'repo = "Acmecorp-AI"' "$OPSX_STATE_DIR/sources.toml" | grep -c 'kind = "gitlab"')" 1 "Acmecorp-AI should be gitlab"

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
case "$outh" in *"$RP"*上層*) ;; *) fail "要由守衛拒絕並點名路徑：$outh" ;; esac
RS="$(mk_repo sp)"; cd "$RS"
# state 目錄要先有 python 檔，不然 opsx 在進 init_repo 之前就因為找不到 python 而失敗，測到的不是守衛
mkdir -p "$RS/state"; cp "$OPSX_STATE_DIR/python" "$RS/state/python"
outh="$(OPSX_STATE_DIR="$RS/state" opsx init 2>&1)" && fail "repo 是 state 目錄的上層時 opsx init 要失敗：$outh"
case "$outh" in *"$RS"*上層*) ;; *) fail "要由守衛拒絕並點名路徑：$outh" ;; esac
dirs="$(cj "$CR" permissions.additionalDirectories)"
for r in "$RH" "$RP" "$RS"; do
  case "$dirs" in *"\"$r\""*) fail "$r 不該進可寫目錄：$dirs" ;; esac
done
assert_no_file "$RH/openspec"   # 守衛在寫任何東西之前

# $OPSX_ROOT 在被登記的 repo 裡（opsx 自己的 repo）：只警告，不拒絕，照常登記
RO="$(mk_repo oroot)"; mkdir "$RO/plug"; cp -R "$OPSX_ROOT/bin" "$OPSX_ROOT/templates" "$OPSX_ROOT/schemas" "$RO/plug/"
cd "$RO"
outo="$(OPSX_ROOT="$RO/plug" bash "$RO/plug/bin/opsx" init 2>&1)" || fail "opsx 程式碼在 repo 裡時要只警告、照常登記：$outo"
case "$outo" in *"opsx 程式碼"*"$RO"*) ;; *) fail "要警告 opsx 程式碼對所有 session 可寫：$outo" ;; esac
case "$(cj "$CR" permissions.additionalDirectories)" in *"\"$RO\""*) ;; *) fail "警告之後仍要登記 $RO" ;; esac

# --- 重跑 init 用插件版覆寫 spec 範本與 specs instruction；--check 比對兩者（specs/opsx-init）---
# init.sh 的 specs_block：只給 schema.yaml 印出區塊，多給一個檔就換成那個檔的內容
specs_block_of() { ( OPSX_PY=python3; source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/init.sh"; specs_block "$@" ); }
# 把 <dst> 的 specs 區塊換成 <src> 的
swap_specs() { specs_block_of "$2" > "$FX/swap-block" && specs_block_of "$1" "$FX/swap-block"; }
RF="$(mk_repo forkref)"; ( cd "$RF" && openspec schema fork spec-driven opsx >/dev/null 2>&1 ) || fail "fork spec-driven 失敗"
FS="$RF/openspec/schemas/opsx"; OS="$R/openspec/schemas/opsx"
assert_grep "with WHEN/THEN format" "$FS/schema.yaml"
cd "$R"
# settings 也裝齊，--check 的 exit code 才只反映 spec 範本與 instruction；用自己的 state 與 settings，不影響後面 --global 的斷言
export CLAUDE_CONFIG_DIR="$FX/cc-spec" OPSX_STATE_DIR="$FX/state-spec"
mkdir -p "$OPSX_STATE_DIR"; cp "$FX/state/python" "$OPSX_STATE_DIR/python"
opsx init --global >/dev/null 2>&1 || fail "init --global for cc-spec"
printf '{"projects": {"%s": {"hasTrustDialogAccepted": true}}}' "$R" > "$CLAUDE_CONFIG_DIR/.claude.json"
opsx init >/dev/null 2>&1 || fail "init in cc-spec"
cp "$FS/templates/spec.md" "$OS/templates/spec.md"; swap_specs "$OS/schema.yaml" "$FS/schema.yaml"
assert_grep "with WHEN/THEN format" "$OS/schema.yaml"
# init --check 抓到舊版 spec 範本（反例）
outc="$(opsx init --check 2>&1)"; rc=$?
assert_eq "$rc" 1 "舊版 spec 範本時 --check 要失敗：$outc"
case "$outc" in *"spec 範本"*) ;; *) fail "要說 spec 範本不同：$outc" ;; esac
case "$outc" in *"specs instruction"*) ;; *) fail "要說 specs instruction 不同：$outc" ;; esac
case "$outc" in *"跑 opsx init 換成插件版"*) ;; *) fail "要建議跑 opsx init 換成插件版：$outc" ;; esac
# 重跑 init 更新舊範本（正例）
outr="$(opsx init 2>&1)" || fail "已裝的 repo 重跑 init 失敗：$outr"
cmp -s "$OS/templates/spec.md" "$OPSX_ROOT/schemas/opsx/templates/spec.md" || fail "重跑後 spec.md 不是插件版"
assert_not_grep "with WHEN/THEN format" "$OS/schema.yaml"
assert_grep "written in Gherkin form" "$OS/schema.yaml"
( cd "$R" && openspec schema validate opsx >/dev/null 2>&1 ) || fail "重跑後 schema validate 失敗"
case "$outr" in *"spec 範本"*"插件版"*) ;; *) fail "要印一行說更新了 spec 範本與 specs instruction：$outr" ;; esac
# 重跑 init 不重複插入 artifact（反例）
cp "$OS/schema.yaml" "$FX/schema-1st"
opsx init >/dev/null 2>&1 || fail "第二次重跑 init 失敗"
cmp -s "$OS/schema.yaml" "$FX/schema-1st" || fail "第二次跑完 schema.yaml 跟第一次不同：$(diff "$FX/schema-1st" "$OS/schema.yaml")"
assert_eq "$(grep -c -- '- id: grill' "$OS/schema.yaml")" 1 "grill 重複"
assert_eq "$(grep -c -- '- id: specs' "$OS/schema.yaml")" 1 "specs 重複"
# init --check 在插件版時不報 spec（正例）
outc="$(opsx init --check 2>&1)"; rc=$?
case "$outc" in *"spec 範本"*|*"specs instruction"*) fail "插件版時不該報 spec：$outc" ;; esac
assert_eq "$rc" 0 "插件版、settings 一致時 --check 要過：$outc"
# 邊界：schema.yaml 沒有 specs artifact → init 失敗並點名 schema.yaml 路徑
python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); open(p,"w").write(s.replace("  - id: specs\n", "  - id: specz\n"))' "$OS/schema.yaml"
oute="$(opsx init 2>&1)" && fail "沒有 specs artifact 時 init 要失敗：$oute"
case "$oute" in *"$OS/schema.yaml"*) ;; *) fail "訊息要點名 schema.yaml 路徑：$oute" ;; esac
# --check 遇到沒有 specs artifact：逐項回報、exit 1，不 die
outc="$(opsx init --check 2>&1)"; rc=$?
assert_eq "$rc" 1 "沒有 specs artifact 時 --check 要 exit 1：$outc"
case "$outc" in *"$OS/schema.yaml"*"跑 opsx init"*) ;; *) fail "要點名 schema.yaml 並建議跑 opsx init：$outc" ;; esac
case "$outc" in *Traceback*) fail "--check 不該丟 traceback：$outc" ;; esac
# --check 遇到 schema.yaml 不在：同上
mv "$OS/schema.yaml" "$FX/schema-moved"
outc="$(opsx init --check 2>&1)"; rc=$?
assert_eq "$rc" 1 "schema.yaml 不在時 --check 要 exit 1：$outc"
case "$outc" in *"$OS/schema.yaml"*"跑 opsx init"*) ;; *) fail "要點名 schema.yaml 並建議跑 opsx init：$outc" ;; esac
case "$outc" in *Traceback*) fail "--check 不該丟 traceback：$outc" ;; esac
cp "$FX/schema-1st" "$OS/schema.yaml"

# 邊界：specs 是最後一個 artifact、後面接頂層 apply: → 換區塊時 apply: 逐字保留，讀出的區塊不含 apply:
printf 'artifacts:\n  - id: proposal\n    generates: proposal.md\n  - id: specs\n    generates: old\n\napply:\n  requires: [tasks]\n  tracks: tasks.md\n' > "$FX/last.yaml"
specs_block_of "$FX/last.yaml" > "$FX/last-block"
assert_not_grep 'apply:' "$FX/last-block"
specs_block_of "$FX/last.yaml" "$OPSX_ROOT/schemas/opsx/artifacts-specs.yaml" || fail "specs 排最後時換不了區塊"
assert_grep '^apply:$' "$FX/last.yaml"
assert_grep '^  tracks: tasks.md$' "$FX/last.yaml"
assert_grep '^  - id: proposal$' "$FX/last.yaml"
assert_not_grep 'generates: old' "$FX/last.yaml"

# 驗證失敗要還原：插件的 specs 區塊讓 validate 失敗時，init 非 0、點名 specs 區塊與 schema.yaml，schema.yaml 與 templates/ 跟跑之前逐位元相同
PB="$FX/plug-bad"; mkdir -p "$PB"; cp -R "$OPSX_ROOT/bin" "$OPSX_ROOT/templates" "$OPSX_ROOT/schemas" "$PB/"
printf 'proposal.md：插件改過\n' > "$PB/schemas/opsx/templates/proposal.md"
python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); open(p,"w").write(s.replace("      - proposal\n", "      - no-such-artifact\n"))' "$PB/schemas/opsx/artifacts-specs.yaml"
assert_grep 'no-such-artifact' "$PB/schemas/opsx/artifacts-specs.yaml"
cp -R "$OS" "$FX/opsx-before"
outb="$(OPSX_ROOT="$PB" bash "$PB/bin/opsx" init 2>&1)" && fail "specs 區塊驗證不過時 init 要失敗：$outb"
case "$outb" in *specs*"$OS/schema.yaml"*) ;; *) fail "訊息要點名 specs 區塊與 schema.yaml：$outb" ;; esac
diff -r "$FX/opsx-before" "$OS" >/dev/null || fail "驗證失敗後 schema 目錄沒還原：$(diff -r "$FX/opsx-before" "$OS")"
export OPSX_STATE_DIR="$FX/state"

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
# 受保護授權位置：state 目錄的兄弟（不在 additionalDirectories 內），0700（protected-authorization「init 建目錄」）
assert_dir "${OPSX_STATE_DIR}-protected"
assert_eq "$(stat -f %Lp "${OPSX_STATE_DIR}-protected" 2>/dev/null || stat -c %a "${OPSX_STATE_DIR}-protected")" 700 "受保護目錄要 0700"
echo '{"k":1}' > "${OPSX_STATE_DIR}-protected/authz.json"
# 重跑：symlink 不報錯、檔案不清空
echo 'x = 1' >> "$OPSX_STATE_DIR/grants.toml"
opsx init --global >/dev/null 2>&1 || fail "global rerun"
assert_grep "x = 1" "$OPSX_STATE_DIR/grants.toml"
assert_grep '"k":1' "${OPSX_STATE_DIR}-protected/authz.json"   # 重跑不清授權

# --- config.toml：terminal_app 依 TERM_PROGRAM 預填（specs/opsx-init「--global 建 config.toml 並預填終端機 app」）---
CT="$OPSX_STATE_DIR/config.toml"
rm -f "$CT"
TERM_PROGRAM=WarpTerminal opsx init --global >/dev/null 2>&1 || fail "global with Warp"
assert_grep '^terminal_app = "Warp"$' "$CT"
TERM_PROGRAM=ghostty opsx init --global >/dev/null 2>&1 || fail "global rerun with ghostty"
assert_grep '^terminal_app = "Warp"$' "$CT"   # 已有的檔不覆蓋
assert_not_grep 'Ghostty' "$CT"
rm -f "$CT"
TERM_PROGRAM=vscode opsx init --global >/dev/null 2>&1 || fail "global with vscode"
assert_file "$CT"
assert_not_grep '^terminal_app' "$CT"   # 對不出來不寫值
assert_grep '^# terminal_app' "$CT"
rm -f "$CT"
( unset TERM_PROGRAM; opsx init --global >/dev/null 2>&1 ) || fail "global without TERM_PROGRAM"
assert_not_grep '^terminal_app' "$CT"

# --- 沙盒權限：裝進 CLAUDE_CONFIG_DIR/settings.json（specs/opsx-init「--global 把沙盒權限裝進使用者層」）---
CS="$CLAUDE_CONFIG_DIR/settings.json"
assert_file "$CS"
assert_eq "$(cj "$CS" permissions.additionalDirectories)" "[\"$OPSX_STATE_DIR\"]"
assert_eq "$(cj "$CS" sandbox.network.allowUnixSockets)" MISSING "herdr socket 不放使用者層：一般 agent 走 hook 佇列，只有主控 session 用 coordinator-settings.json"
CO="$OPSX_STATE_DIR/coordinator-settings.json"
assert_file "$CO"
assert_eq "$(cj "$CO" sandbox.network.allowUnixSockets)" "[\"$HOME/.config/herdr/herdr.sock\"]" "主控 session 的設定要開 herdr socket"
case "$outg" in *"主控 session 用 opsx lead 啟動（它帶 --settings $CO"*) ;; *) fail "要印主控 session 用 opsx lead 啟動與設定檔路徑：$outg" ;; esac
case "$outg" in *"用 claude --settings"*) fail "不能再叫人直接跑 claude --settings（起來的協調者沒有 herdr 名）：$outg" ;; esac
assert_eq "$(printf '%s\n' "$outg" | tail -1)" "init --global: 開協調者：在 herdr pane 跑 opsx lead" "結尾要提示用 opsx lead 開協調者：$outg"
co_before="$(cat "$CO")"
assert_eq "$(cj "$CS" sandbox.excludedCommands)" '["gh pr *", "gh issue comment *", "orca *"]' "只排除 gh pr *、gh issue comment * 與 orca *，不是整個 gh *"
assert_eq "$(cj "$CS" sandbox.filesystem.denyWrite)" "[\"$OPSX_STATE_DIR/grants.toml\", \"$OPSX_STATE_DIR/python\", \"$OPSX_STATE_DIR/coordinator-settings.json\"]" "grants.toml、hook 的 interpreter 路徑、主控 session 的設定檔要拒絕沙盒寫入；dispatch.json 不能列（沙盒內的 chain / dispatch 要寫它）"
assert_eq "$(cj "$CS" sandbox.enabled)" MISSING "不替使用者開關沙盒"
assert_no_file "$CS.opsx-bak"        # 第一次裝，原檔不存在，沒有東西可備份
before="$(cat "$CS")"
outs="$(opsx init --global 2>&1)"; assert_eq "$?" 0 "settings rerun: $outs"
assert_eq "$(cat "$CS")" "$before" "重跑改了 settings.json"
assert_eq "$(cat "$CO")" "$co_before" "重跑改了主控 session 的設定檔"
case "$outs" in *"coordinator-settings.json 已有"*) ;; *) fail "內容沒變時要說已有、不重寫（沙盒內重寫會失敗）：$outs" ;; esac
assert_no_file "$CS.opsx-bak"        # no-op 不產生備份

# CLAUDE_CONFIG_DIR 沒設：寫 $HOME/.claude/settings.json
mkdir -p "$FX/home"
env HOME="$FX/home" CLAUDE_CONFIG_DIR= opsx init --global >/dev/null 2>&1 || fail "global without CLAUDE_CONFIG_DIR"
assert_file "$FX/home/.claude/settings.json"
assert_eq "$(cj "$FX/home/.claude/settings.json" permissions.additionalDirectories)" "[\"$OPSX_STATE_DIR\"]"

# 使用者已有設定：保留、追加、備份原檔
mkdir -p "$FX/cc2"
printf '{"sandbox":{"enabled":true,"network":{"allowUnixSockets":["/other.sock"]}},"theme":"dark"}' > "$FX/cc2/settings.json"
orig="$(cat "$FX/cc2/settings.json")"
CLAUDE_CONFIG_DIR="$FX/cc2" opsx init --global >/dev/null 2>&1 || fail "global with existing settings"
assert_eq "$(cj "$FX/cc2/settings.json" theme)" '"dark"'
assert_eq "$(cj "$FX/cc2/settings.json" sandbox.enabled)" true
assert_eq "$(cj "$FX/cc2/settings.json" sandbox.network.allowUnixSockets)" '["/other.sock"]' "使用者自己的 socket 保留，標準設定不加 herdr"
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
PYH="$FX/pyhome"; mkdir -p "$PYH"   # --check 會看 $HOME/.pyenv；不讓真機器的鎖檔影響結果
outc="$(HOME="$PYH" opsx init --check 2>&1)"; assert_eq "$?" 0 "裝完的機器 --check 要過：$outc"
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
outc="$(HOME="$PYH" CLAUDE_CONFIG_DIR="$FX/cc6" opsx init --check 2>&1)"; assert_eq "$?" 0 "登記後 --check 要過：$outc"
case "$outc" in *還沒信任*) ;; *) fail "cc6 沒有信任紀錄，--check 要警告：$outc" ;; esac
# 只缺 orca * 的 settings：--check 指出這一項、exit 1、不改檔
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["sandbox"]["excludedCommands"].remove("orca *");json.dump(d,open(p,"w"))' "$FX/cc6/settings.json"
before="$(cat "$FX/cc6/settings.json")"
outc="$(HOME="$PYH" CLAUDE_CONFIG_DIR="$FX/cc6" opsx init --check 2>&1)"; rc=$?
assert_eq "$rc" 1 "缺 orca * 時 --check 要失敗：$outc"
case "$outc" in *"缺 sandbox.excludedCommands: orca *"*) ;; *) fail "要印缺 orca *：$outc" ;; esac
assert_eq "$(cat "$FX/cc6/settings.json")" "$before" "--check 改了檔"
CLAUDE_CONFIG_DIR="$FX/cc6" opsx init --global >/dev/null 2>&1 || fail "global re-add orca for cc6"
cd "$FX"
# pyenv rehash 鎖檔殘留：超過 5 分鐘才報（rc 1、印路徑與 rehash）；剛建立的與不存在的都不提
case "$outc" in *pyenv*) fail "沒有鎖檔時不該提 pyenv：$outc" ;; esac
LOCK="$PYH/.pyenv/shims/.pyenv-shim"; mkdir -p "${LOCK%/*}"; : > "$LOCK"
python3 -I -c 'import os,sys,time;t=time.time()-60;os.utime(sys.argv[1],(t,t))' "$LOCK"
outc="$(HOME="$PYH" opsx init --check 2>&1)"; assert_eq "$?" 0 "1 分鐘內的鎖檔不算問題：$outc"
case "$outc" in *pyenv*) fail "剛建立的鎖檔不該提：$outc" ;; esac
python3 -I -c 'import os,sys,time;t=time.time()-600;os.utime(sys.argv[1],(t,t))' "$LOCK"
outc="$(HOME="$PYH" opsx init --check 2>&1)"; assert_eq "$?" 1 "10 分鐘前的鎖檔要失敗：$outc"
case "$outc" in *"$LOCK"*rehash*|*rehash*"$LOCK"*) ;; *) fail "要印鎖檔路徑與 rehash：$outc" ;; esac
rm "$LOCK"

# --- 與插件同名的 skill：--check 與 --global 警告，不改 rc、不動使用者的檔案 ---
CCS="$FX/cc-skills"
CLAUDE_CONFIG_DIR="$CCS" opsx init --global >/dev/null 2>&1 || fail "global for cc-skills"
mkdir -p "$CCS/skills/tdd" "$CCS/skills/pr" "$CCS/skills/mine"
printf -- '---\nname: tdd\n---\nmine\n' > "$CCS/skills/tdd/SKILL.md"
printf -- '---\nname: mine\n---\n' > "$CCS/skills/mine/SKILL.md"
ln -s "$OPSX_ROOT/skills/explore" "$CCS/skills/explore"      # 指回插件本身：不算
tdd_before="$(cat "$CCS/skills/tdd/SKILL.md")"
outk="$(CLAUDE_CONFIG_DIR="$CCS" opsx init --check 2>&1)"; assert_eq "$?" 0 "同名 skill 不改 --check 的 rc：$outk"
case "$outk" in *"$CCS/skills/tdd 跟 opsx 插件的 skills/tdd 同名"*) ;; *) fail "--check 要指名同名的 tdd 與路徑：$outk" ;; esac
case "$outk" in *搬走*|*改名*) ;; *) fail "警告要說怎麼處理：$outk" ;; esac
case "$outk" in *不受影響*|*已帶前綴*) fail "stage-cmd-prefix 未合時不能說 opsx 送的指令已帶前綴：$outk" ;; esac
# 有別的同名命中（tdd）時，review 的內建撞名警告仍要出現
case "$outk" in *"插件 skill review 與內建指令「code-review」撞名"*) ;; *) fail "有 tdd 同名時 review 的內建撞名警告不能被壓掉：$outk" ;; esac
case "$outk" in *"$CCS/skills/pr"*) fail "沒有 SKILL.md 的 pr 資料夾不算同名：$outk" ;; esac
case "$outk" in *"$CCS/skills/mine"*) fail "不同名的 mine 不該警告：$outk" ;; esac
case "$outk" in *"$CCS/skills/explore"*) fail "指回插件的 symlink 不該警告：$outk" ;; esac
outk="$(CLAUDE_CONFIG_DIR="$CCS" opsx init --global 2>&1)"; assert_eq "$?" 0 "同名 skill 不讓 --global 失敗：$outk"
case "$outk" in *"$CCS/skills/tdd 跟 opsx 插件的 skills/tdd 同名"*) ;; *) fail "--global 也要指名同名的 tdd：$outk" ;; esac
assert_eq "$(cat "$CCS/skills/tdd/SKILL.md")" "$tdd_before" "警告不能動使用者的 skill"
rm -r "$CCS/skills/tdd"
outk="$(CLAUDE_CONFIG_DIR="$CCS" opsx init --check 2>&1)"; assert_eq "$?" 0 "沒有同名時 --check 的 rc：$outk"
case "$outk" in *"$CCS/skills/tdd"*) fail "沒有同名時不該警告：$outk" ;; esac
# 專案層：只在 repo 裡掃
cd "$R"
CLAUDE_CONFIG_DIR="$CCS" opsx init >/dev/null 2>&1 || fail "init R in cc-skills"
mkdir -p "$R/.claude/skills/review"; printf -- '---\nname: review\n---\n' > "$R/.claude/skills/review/SKILL.md"
outk="$(CLAUDE_CONFIG_DIR="$CCS" opsx init --check 2>&1)"; assert_eq "$?" 0 "專案層同名不改 rc：$outk"
case "$outk" in *"$R/.claude/skills/review"*) ;; *) fail "repo 裡 --check 要警告專案層的 review：$outk" ;; esac
# 同名且撞內建：不能同時說「會跑到這份」和「會跑到內建」；搬走的後果要講
case "$outk" in *"與內建指令「code-review」撞名"*) fail "已有同名 review 時不該再說會跑到內建：$outk" ;; esac
case "$outk" in *"搬走後手打斜線加短名「review」會跑到內建指令「code-review」，一律打 /opsx-workflow:review"*) ;; *) fail "同名且撞內建時要說搬走後的後果：$outk" ;; esac
cd "$FX"
outk="$(CLAUDE_CONFIG_DIR="$CCS" opsx init --check 2>&1)"
case "$outk" in *"$R/.claude/skills/review"*) fail "repo 外不掃專案層：$outk" ;; esac
# 兩層各有一份 review：只印一行、列出兩個路徑，不說「會跑到這份」
mkdir -p "$CCS/skills/review"; printf -- '---\nname: review\n---\n' > "$CCS/skills/review/SKILL.md"
cd "$R"
outk="$(CLAUDE_CONFIG_DIR="$CCS" opsx init --check 2>&1)"
assert_eq "$(grep -c '的 skills/review 同名' <<< "$outk")" 1 "兩層各一份 review 只警告一行：$outk"
case "$outk" in *"$CCS/skills/review"*"$R/.claude/skills/review"*) ;; *) fail "那一行要列出兩個路徑：$outk" ;; esac
case "$outk" in *會跑到這份*) fail "兩層並存時不能說會跑到這份：$outk" ;; esac
case "$outk" in *"與內建指令「code-review」撞名"*) fail "兩層各一份時不該另印內建撞名：$outk" ;; esac
cd "$FX"
# 只有使用者層有 review（stage-cmd-prefix 事故的情境）：說搬走後的後果，不另印內建撞名
outk="$(CLAUDE_CONFIG_DIR="$CCS" opsx init --check 2>&1)"
case "$outk" in *"搬走後手打斜線加短名「review」會跑到內建指令「code-review」"*) ;; *) fail "使用者層的 review 要說搬走後的後果：$outk" ;; esac
case "$outk" in *"與內建指令「code-review」撞名"*) fail "使用者層有同名 review 時不該另印內建撞名：$outk" ;; esac
rm -r "$CCS/skills/review"
# 去重：使用者層與專案層是同一個目錄時，同名警告只出一次
cd "$R"
CLAUDE_CONFIG_DIR="$R/.claude" opsx init --global >/dev/null 2>&1 || fail "global for repo-local config dir"
outk="$(CLAUDE_CONFIG_DIR="$R/.claude" opsx init --check 2>&1)"
assert_eq "$(grep -c 'skill 同名：' <<< "$outk")" 1 "同一個 skill 路徑只警告一次：$outk"
cd "$FX"
# settings 不一致（rc=1）又有同名 skill：rc 仍是 1，警告照出
mkdir -p "$FX/cc7/skills/tdd"; printf '{"theme":"dark"}' > "$FX/cc7/settings.json"
printf -- '---\nname: tdd\n---\n' > "$FX/cc7/skills/tdd/SKILL.md"
outk="$(CLAUDE_CONFIG_DIR="$FX/cc7" opsx init --check 2>&1)"; assert_eq "$?" 1 "settings 不一致時 rc 要維持 1：$outk"
case "$outk" in *"$FX/cc7/skills/tdd 跟 opsx 插件的 skills/tdd 同名"*) ;; *) fail "rc=1 時也要有同名警告：$outk" ;; esac

# --- 插件 skill 名撞內建指令：查表，--check 與 --global 警告，不改 rc ---
assert_eq "$( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/init.sh"; builtin_command_for review )" "code-review" "review 撞內建 code-review"
assert_eq "$( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/init.sh"; builtin_command_for explore )" "" "表外的名字回空"
outk="$(CLAUDE_CONFIG_DIR="$CCS" opsx init --check 2>&1)"
case "$outk" in *"插件 skill review 與內建指令「code-review」撞名"*"/opsx-workflow:review"*) ;; *) fail "--check 要警告 review 撞 /code-review 並說用 /opsx-workflow:review：$outk" ;; esac
case "$outk" in *"插件 skill explore 與內建"*) fail "表外的 explore 不該警告：$outk" ;; esac
outk="$(CLAUDE_CONFIG_DIR="$CCS" opsx init --global 2>&1)"; assert_eq "$?" 0 "內建撞名不讓 --global 失敗：$outk"
case "$outk" in *"插件 skill review 與內建指令「code-review」撞名"*) ;; *) fail "--global 也要警告內建撞名：$outk" ;; esac
case "$outk" in *不受影響*|*已帶前綴*) fail "--global 也不能說 opsx 送的指令已帶前綴：$outk" ;; esac

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

# --- 每 5 分鐘一輪的 coordinate launchd：第一次安裝 ---
SYNC_PL="$PL"; PL="$OPSX_LAUNCH_AGENTS_DIR/com.opsx.coordinate.plist"
assert_file "$PL"
assert_eq "$(pl ProgramArguments)" "[\"$OPSX_BIN_DIR/opsx\", \"coordinate\"]"
assert_eq "$(pl StartInterval)" 300
assert_eq "$(pl EnvironmentVariables.HERDR_ENV)" 1
assert_eq "$(pl EnvironmentVariables.OPSX_STATE_DIR)" "$OPSX_STATE_DIR"
assert_eq "$(pl EnvironmentVariables.PATH)" "$P" "coordinate 的 PATH 跟每日同步同一份"
assert_eq "$(pl StandardOutPath)" "$OPSX_STATE_DIR/coordinate.out"
assert_grep "^bootstrap gui/$(id -u) $PL\$" "$OPSX_FAKE_LOG"
PL="$SYNC_PL"

# --- 已經裝過：launchctl print 成功就不重載（兩支都是） ---
: > "$OPSX_FAKE_LOG"
OPSX_TEST_LAUNCHCTL_LOADED=1 opsx init --global >/dev/null 2>&1 || fail "global with loaded job"
assert_grep '^print gui/' "$OPSX_FAKE_LOG"; assert_not_grep '^bootstrap' "$OPSX_FAKE_LOG"
assert_grep "^print gui/$(id -u)/com.opsx.coordinate\$" "$OPSX_FAKE_LOG"

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

# --- --global 問 obsidian 收件夾：vault 與子資料夾分兩題，原樣寫入（sync-obsidian / obsidian-source）---
# 互動模式要 tty，測試直接叫 ask_global_sources，stdin 依序答 vault、子資料夾
ask() { ( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/init.sh"; ask_global_sources "$1" ); }
obsidian_of() { python3 -I -c 'import sys,tomllib;o=tomllib.load(open(sys.argv[1],"rb"))["obsidian"];print(o["vault"]+"|"+o["folder"])' "$1"; }
ST="$FX/sources-ask.toml"
: > "$ST"; printf '/Users/me/vault\n01-Projects/inbox\n\n' | ask "$ST" >/dev/null
assert_eq "$(obsidian_of "$ST")" "/Users/me/vault|01-Projects/inbox"
: > "$ST"; printf '/Users/me/notes\nInbox\n\n' | ask "$ST" >/dev/null
assert_eq "$(obsidian_of "$ST")" "/Users/me/notes|Inbox"
: > "$ST"; printf '\n\n' | ask "$ST" >/dev/null
assert_not_grep '^\[obsidian\]' "$ST"
# 子資料夾空答案：不登記，免得整個 vault 變收件夾
: > "$ST"; printf '/Users/me/vault\n\n\n' | ask "$ST" >/dev/null
assert_not_grep '^\[obsidian\]' "$ST"
# 引號與反斜線（拖進終端機的路徑會有 \ ）：寫出的 TOML 解析得回原字串
: > "$ST"; printf '%s\n%s\n\n' '/Users/me/My "V"\x' 'in\box' | ask "$ST" >/dev/null
assert_eq "$(obsidian_of "$ST")" '/Users/me/My "V"\x|in\box'
# 控制字元（read -r 沒有 readline，打字時按方向鍵會存進 ESC）：不登記，免得 sources.toml 解析不了
: > "$ST"; printf '/Users/me/va\033[Dult\ninbox\n\n' | ask "$ST" >/dev/null
assert_not_grep '^\[obsidian\]' "$ST"
# vault/folder 不是資料夾：照樣寫入，但當場警告（拖進終端機的 Mobile\ Documents 反斜線會原樣留著）
: > "$ST"; outa="$(printf '/Users/me/Library/Mobile\\ Documents/v\ninbox\n\n' | ask "$ST" 2>&1)"
assert_grep '^\[obsidian\]' "$ST"
case "$outa" in *不是資料夾*) ;; *) fail "不存在的路徑要警告：$outa" ;; esac
mkdir -p "$FX/realvault/inbox"
: > "$ST"; outa="$(printf '%s\ninbox\n\n' "$FX/realvault" | ask "$ST" 2>&1)"
case "$outa" in *不是資料夾*) fail "存在的資料夾不該警告：$outa" ;; esac
printf '[obsidian]\nvault = "/v"\nfolder = "f"\n' > "$ST"; cp "$ST" "$FX/st-before"
outa="$(printf '\n' | ask "$ST")"
assert_eq "$(cat "$ST")" "$(cat "$FX/st-before")" "已登記不改"
case "$outa" in *obsidian*) fail "已登記不再問 obsidian：$outa" ;; esac

# --- --global 不引導人設定 customer（specs/opsx-init「--global 不引導人設定 customer」）---
: > "$ST"; outa="$(printf '/Users/me/vault\ninbox\n' | ask "$ST" 2>&1)"
case "$outa" in *customer*) fail "不該問 customer：$outa" ;; esac
assert_not_grep '^\[customer\]' "$ST"
printf '[customer]\nbase_url = "u"\n' > "$ST"; cp "$ST" "$FX/st-before"
printf '\n\n' | ask "$ST" >/dev/null 2>&1
assert_eq "$(cat "$ST")" "$(cat "$FX/st-before")" "既有 [customer] 不動"
outt="$(OPSX_STATE_DIR="$FX/st-tpl" opsx init --global 2>&1)"; assert_eq "$?" 0 "fresh state init --global: $outt"
assert_eq "$(printf '%s\n' "$outt" | grep '略過' | grep -c customer)" 0 "非互動訊息不提 customer"
assert_eq "$(printf '%s\n' "$outt" | grep -c '略過.*obsidian\|obsidian.*略過')" 1 "非互動訊息提 obsidian"
assert_not_grep '^# \[customer\]' "$FX/st-tpl/sources.toml"
assert_grep 'customer.*on-hold' "$FX/st-tpl/sources.toml"
echo ok
