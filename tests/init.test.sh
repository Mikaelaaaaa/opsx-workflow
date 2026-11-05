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

# --- 邊界：沒 remote 的 repo → 仍可 init，sources 不登記，印一行說明 ---
R3="$(mk_repo local-only)"; cd "$R3"
out3="$(opsx init 2>&1)"; assert_eq "$?" 0 "no-remote rc"
assert_not_grep 'repo = "local-only"' "$OPSX_STATE_DIR/sources.toml"
echo "$out3" | grep -q "remote" || fail "should mention no remote: $out3"

# --- 邊界：在 worktree 裡跑 → exclude 寫到共用的 .git/info/exclude，不是 worktree 自己的 ---
cd "$R"; git -C "$R" worktree add -q "$FX/wt" -b feat/x/mikaela
cd "$FX/wt"; opsx init >/dev/null 2>&1 || fail "init in worktree"
assert_eq "$(grep -c '^openspec/$' "$R/.git/info/exclude")" 1 "exclude duplicated or missing via worktree"

# --- --global ---
cd "$FX"
outg="$(opsx init --global 2>&1)"; assert_eq "$?" 0 "global rc: $outg"
assert_file "$OPSX_STATE_DIR/grants.toml"
assert_file "$OPSX_STATE_DIR/workspaces.toml"
[ -L "$OPSX_BIN_DIR/opsx" ] || fail "symlink missing"
assert_eq "$(readlink "$OPSX_BIN_DIR/opsx")" "$OPSX_ROOT/bin/opsx"
# 重跑：symlink 不報錯、檔案不清空
echo 'x = 1' >> "$OPSX_STATE_DIR/grants.toml"
opsx init --global >/dev/null 2>&1 || fail "global rerun"
assert_grep "x = 1" "$OPSX_STATE_DIR/grants.toml"
echo ok
