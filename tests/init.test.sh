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
cd "$FX"; use_fakes herdr; export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
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
