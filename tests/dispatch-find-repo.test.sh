#!/usr/bin/env bash
# opsx dispatch 沒給 --repo 時在已登記 repo 找卡（specs/opsx-dispatch「沒給 --repo 時在已登記 repo 找卡」「找不到唯一的 repo 就不派」）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela

# 已登記 repo：OPSX_CODE_ROOT 底下兩個，加上 sources.toml 登記、不在 root 底下的一個
A="$(mk_repo code/Acmecorp-AI)"
C="$(mk_repo code/Acmecorp-CS)"
S="$(mk_repo extra/Acmecorp-Ext)"
P="$FX/plain"; mkdir -p "$P"
printf '[[source]]\nkind = "gitlab"\nrepo = "Acmecorp-Ext"\nproject = "g/ext"\npath = "%s"\n' "$S" > "$OPSX_STATE_DIR/sources.toml"
# Acmecorp-Ext 沒掛 workspace：派它的卡時 dispatch 以它的 repo 名開新 workspace，看得出 workspace 跟著卡所在的 repo
# AI 與 CS 掛不同 workspace（假 herdr 的 workspace list：acmecorp-ai 是 w1，rag-demo 是 w2）
printf '[repos]\n"Acmecorp-AI" = "acmecorp-ai"\n"Acmecorp-CS" = "rag-demo"\n' > "$OPSX_STATE_DIR/workspaces.toml"
mkdir -p "$A/openspec/changes" "$C/openspec/changes" "$S/openspec/changes"
# 只有 Acmecorp-AI 的 workplan 給 card-a 指定分支；feature featx 的主 change 是 card-h
cat > "$A/openspec/workplan.yaml" <<'EOF'
features:
  - name: fa
    prs:
      - name: card-a
        branch: fix/card-a-from-ai/mikaela
        status: pending
        changes:
          - name: card-a
            status: pending
  - name: featx
    prs:
      - name: card-h
        branch: feat/card-h/mikaela
        status: pending
        depends-on: []
        changes:
          - name: card-h
            status: pending
  - name: archive
    prs:
      - name: card-j
        branch: feat/card-j/mikaela
        status: pending
        depends-on: []
        changes:
          - name: card-j
            status: pending
EOF

card() { # card <repo-dir> <slug>
  mkdir -p "$1/openspec/changes/$2"
  printf 'schema: opsx\ncreated: 2026-11-17\n' > "$1/openspec/changes/$2/.openspec.yaml"
  printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$1/openspec/changes/$2/explore.md"
  # 不在 workplan 的卡派工前會掛進去、寫 priority 覆寫，要有 opsx new 建的 frontmatter
  printf -- '---\ntype: 功能\nsource: me\nkind_of_work: planned\n---\n' > "$1/openspec/changes/$2/inbox.md"
}
key() { jq -r --arg k "$1" 'has($k)' "$OPSX_STATE_DIR/dispatch.json" 2>/dev/null || echo false; }
dispatch_ok() { # dispatch_ok <cwd> <slug> [args…]：rc 0，回傳 stdout
  local cwd="$1"; shift
  local out; out="$(cd "$cwd" && opsx dispatch "$@" --agent claude --mode interactive --kind dev 2>"$FX/err")" || fail "dispatch $* 從 $cwd 應該成功：$out $(cat "$FX/err")"
  printf '%s' "$out"
}
dispatch_refused() { # dispatch_refused <cwd> <slug> [args…]：rc 非 0，herdr 沒被叫，stderr 留在 $FX/err
  local cwd="$1"; shift
  : > "$OPSX_FAKE_LOG"
  if (cd "$cwd" && opsx dispatch "$@" --agent claude --mode interactive --kind dev >"$FX/out" 2>"$FX/err"); then fail "dispatch $* 從 $cwd 應該被拒：$(cat "$FX/out")"; fi
  assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "被拒的派工不該碰 herdr"
}

# --- 卡在已登記 repo 裡，cwd 的位置不同：一般場景，cwd 是另一個 repo ---
card "$A" card-a
: > "$OPSX_FAKE_LOG"
out="$(dispatch_ok "$C" card-a)"
assert_grep '^tab create --workspace w1 ' "$OPSX_FAKE_LOG"
assert_not_grep '^tab create --workspace w2 ' "$OPSX_FAKE_LOG"
case "$out" in *"卡在 $A"*) ;; *) fail "stdout 要說卡在 ${A}：$out" ;; esac
assert_dir "$A/.claude/worktrees/card-a"
assert_no_file "$C/.claude/worktrees/card-a"
assert_eq "$(key Acmecorp-AI/card-a)" true "dispatch.json 要用卡所在 repo 的 key"
assert_eq "$(key Acmecorp-CS/card-a)" false "不該寫 cwd repo 的 key"
assert_eq "$(git -C "$A/.claude/worktrees/card-a" rev-parse --abbrev-ref HEAD)" "fix/card-a-from-ai/mikaela" "分支要取自卡所在 repo 的 workplan"

# --- cwd 是 cwd repo 的 linked worktree：算 cwd 的 repo 有卡，不去別的 repo ---
card "$A" card-w; card "$C" card-w
out="$(dispatch_ok "$A/.claude/worktrees/card-a" card-w)"
case "$out" in *"卡在 $A"*) ;; *) fail "linked worktree 裡派要用主 repo ${A}：$out" ;; esac
assert_eq "$(key Acmecorp-AI/card-w)" true
assert_eq "$(key Acmecorp-CS/card-w)" false

# --- 邊界：cwd 是 sources.toml 登記、不在 OPSX_CODE_ROOT 底下的 repo ---
card "$A" card-a3
out="$(dispatch_ok "$S" card-a3)"
case "$out" in *"卡在 $A"*) ;; *) fail "stdout 要說卡在 ${A}：$out" ;; esac
assert_dir "$A/.claude/worktrees/card-a3"
assert_eq "$(key Acmecorp-AI/card-a3)" true

# --- 邊界：cwd 不是 git repo ---
card "$A" card-a2
out="$(dispatch_ok "$P" card-a2)"
case "$out" in *"卡在 $A"*) ;; *) fail "stdout 要說卡在 ${A}：$out" ;; esac
assert_dir "$A/.claude/worktrees/card-a2"
assert_eq "$(key Acmecorp-AI/card-a2)" true

# --- 邊界：卡在 sources.toml 登記、不在 OPSX_CODE_ROOT 底下的 repo ---
card "$S" card-g
: > "$OPSX_FAKE_LOG"
out="$(dispatch_ok "$C" card-g)"
case "$out" in *"卡在 $S"*) ;; *) fail "stdout 要說卡在 ${S}：$out" ;; esac
assert_dir "$S/.claude/worktrees/card-g"
assert_eq "$(key Acmecorp-Ext/card-g)" true
assert_grep '^workspace create.*Acmecorp-Ext' "$OPSX_FAKE_LOG"

# --- cwd 的 repo 有卡就用 cwd 的 repo，stdout 也說卡在哪 ---
card "$A" card-b; card "$C" card-b
out="$(dispatch_ok "$C" card-b)"
case "$out" in *"卡在 $C"*) ;; *) fail "cwd 的 repo 有卡也要說卡在 ${C}：$out" ;; esac
assert_eq "$(key Acmecorp-CS/card-b)" true
assert_eq "$(key Acmecorp-AI/card-b)" false
assert_no_file "$A/.claude/worktrees/card-b"

# --- 已歸檔的同名卡不算 ---
mkdir -p "$A/openspec/changes/archive/2026-11-01-card-c"
printf 'schema: opsx\n' > "$A/openspec/changes/archive/2026-11-01-card-c/.openspec.yaml"
dispatch_refused "$C" card-c
assert_grep '沒有這張卡' "$FX/err"

# --- 兩個已登記 repo 都有這張卡 ---
card "$A" card-d; card "$C" card-d
dispatch_refused "$P" card-d
assert_grep "$A" "$FX/err"
assert_grep "$C" "$FX/err"
assert_grep '--repo' "$FX/err"
assert_eq "$(key Acmecorp-AI/card-d)" false
assert_eq "$(key Acmecorp-CS/card-d)" false
assert_no_file "$A/.claude/worktrees/card-d"

# --- 哪個 repo 都沒有這張卡 ---
dispatch_refused "$P" card-none
assert_grep '沒有這張卡' "$FX/err"

# --- 給了 --repo 就不去別的 repo 找 ---
card "$A" card-e
dispatch_refused "$P" card-e --repo "$C"
assert_grep '沒有這張卡' "$FX/err"
assert_eq "$(key Acmecorp-AI/card-e)" false

# --- 給了 --repo 且那個 repo 有卡 ---
card "$A" card-f; card "$C" card-f
dispatch_ok "$P" card-f --repo "$A" >/dev/null
assert_eq "$(key Acmecorp-AI/card-f)" true
assert_eq "$(key Acmecorp-CS/card-f)" false

# --- 格式不合法的 slug 先擋下，不去找卡 ---
dispatch_refused "$P" ..
assert_grep 'slug 要符合' "$FX/err"
assert_not_grep '沒有這張卡' "$FX/err"
assert_not_grep '--repo' "$FX/err"
dispatch_refused "$P" Foo_Bar
assert_grep 'slug 要符合' "$FX/err"
assert_not_grep '沒有這張卡' "$FX/err"

# --- archive 不是卡：cwd repo 與已登記 repo 兩條路都擋（A 有 changes/archive/）---
dispatch_refused "$A" archive
assert_grep 'archive' "$FX/err"
assert_not_grep '--repo' "$FX/err"
dispatch_refused "$P" archive
assert_grep 'archive' "$FX/err"
assert_not_grep '--repo' "$FX/err"
assert_no_file "$A/openspec/changes/archive/.openspec.yaml"

# --- --feature 不走找卡：feature 名沒有卡目錄，別的 repo 有同名卡目錄也不去 ---
card "$A" card-h; printf -- '- [ ] 1.1 x\n' > "$A/openspec/changes/card-h/tasks.md"
card "$C" featx
out="$(cd "$A" && opsx dispatch --feature featx --agent claude --mode interactive 2>&1)" || fail "dispatch --feature 應該成功：$out"
case "$out" in *"卡在 /"*|*沒有這張卡*) fail "--feature 不該找卡：$out" ;; esac
assert_eq "$(key Acmecorp-AI/card-h)" true
assert_eq "$(jq '[keys[] | select(startswith("Acmecorp-CS/") and contains("featx"))] | length' "$OPSX_STATE_DIR/dispatch.json")" 0 "--feature 不該寫到 Acmecorp-CS"

# --- archive 只擋卡名：叫 archive 的 feature 照舊派（D4）---
card "$A" card-j; printf -- '- [ ] 1.1 x\n' > "$A/openspec/changes/card-j/tasks.md"
out="$(cd "$A" && opsx dispatch --feature archive --agent claude --mode interactive 2>&1)" || fail "feature archive 應該照常派：$out"
assert_eq "$(key Acmecorp-AI/card-j)" true

# --- 卡在同名的 repo（登記的 dup/Acmecorp-CS 跟 code/Acmecorp-CS 同名）：說同名、列兩個路徑，不派（opsx-dispatch「找卡時遇到同名衝突的 repo 要說衝突」）---
DUP="$(mk_repo dup/Acmecorp-CS)"; mkdir -p "$DUP/openspec/changes"
printf '\n[[source]]\nkind = "gitlab"\nrepo = "dup-cs"\nproject = "g/dupcs"\npath = "%s"\n' "$DUP" >> "$OPSX_STATE_DIR/sources.toml"
card "$DUP" card-k
dispatch_refused "$P" card-k
assert_grep "$C" "$FX/err"
assert_grep "$DUP" "$FX/err"
assert_grep '改名' "$FX/err"
assert_not_grep '沒有這張卡' "$FX/err"
assert_no_file "$DUP/.claude/worktrees/card-k"
# 不同名的已登記 repo 照派
card "$A" card-l
dispatch_ok "$P" card-l >/dev/null
assert_eq "$(key Acmecorp-AI/card-l)" true
# 站在同名的 repo 裡派它自己的卡、或 --repo 指到同名的 repo：一樣不派（D8）
card "$DUP" card-m
dispatch_refused "$DUP" card-m
assert_grep "$C" "$FX/err"
assert_grep "$DUP" "$FX/err"
assert_grep '改名' "$FX/err"
assert_no_file "$DUP/.claude/worktrees/card-m"
card "$C" card-n
dispatch_refused "$P" card-n --repo "$C"
assert_grep "$DUP" "$FX/err"
assert_grep '改名' "$FX/err"
assert_eq "$(key Acmecorp-CS/card-n)" false
assert_no_file "$C/.claude/worktrees/card-n"
# --repo 指到沒登記、但跟已登記的 Acmecorp-AI 同名的資料夾：不派，列兩個路徑（D13）
U="$(mk_repo unreg/Acmecorp-AI)"; mkdir -p "$U/openspec/changes"
card "$U" card-o
dispatch_refused "$P" card-o --repo "$U"
assert_grep "$A" "$FX/err"
assert_grep "$U" "$FX/err"
assert_no_file "$U/.claude/worktrees/card-o"
# --repo 指到第三個沒登記、跟同名衝突的 Acmecorp-CS 同名的資料夾：一樣不派（D15）
T="$(mk_repo third/Acmecorp-CS)"; mkdir -p "$T/openspec/changes"
card "$T" card-q
dispatch_refused "$P" card-q --repo "$T"
assert_grep '改名' "$FX/err"
assert_no_file "$T/.claude/worktrees/card-q"
# 卡同時在同名的 dup/Acmecorp-CS 與沒衝突的 Acmecorp-AI：照舊不派，但說可以用 --repo 派 Acmecorp-AI 那張（D14）
card "$DUP" card-p; card "$A" card-p
dispatch_refused "$P" card-p
assert_grep '同名' "$FX/err"
assert_grep "--repo $A" "$FX/err"

# --- sources.toml 壞了就不找（放最後：之後不再用到登記清單）---
printf 'not = [valid\n' > "$OPSX_STATE_DIR/sources.toml"
card "$A" card-i
dispatch_refused "$P" card-i
assert_grep 'sources.toml 壞了' "$FX/err"

echo ok
