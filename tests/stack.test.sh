#!/usr/bin/env bash
# opsx stack <主> <子> <sha>：把 subagent 在子殼分支上的 commit 疊回 PR 分支，勾主殼 tasks.md。
# 驗收：openspec/changes/apply-fanout/specs/subchange-stack/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo stk)"; mkdir -p "$OPSX_STATE_DIR"
printf 'openspec/\n' >> "$R/.git/info/exclude"   # 跟真的 repo 一樣，openspec/ 不進 git
M="$R/openspec/changes/m"; mkdir -p "$M"; printf 'schema: opsx\nkind: dev\n' > "$M/.openspec.yaml"
cat > "$R/openspec/workplan.yaml" <<'EOF'
features:
  - name: f
    prs:
      - name: m
        branch: feat/m/u
        status: in-progress
        depends-on: []
        changes:
          - name: s1
            status: pending
            depends-on: []
          - name: s2
            status: pending
            depends-on: [s1]
          - name: s3
            status: pending
            depends-on: []
EOF
cat > "$M/tasks.md" <<'EOF'
## 1. 子 change

- [ ] 1.1 `s1`：改 a.txt
  - 驗收：x
  - 測試：x
- [ ] 1.2 `s2`：也改 a.txt（依賴 1.1）
  - 驗收：x
  - 測試：x
- [ ] 1.3 `s3`：加 b.txt
  - 驗收：x
  - 測試：x
EOF
cd "$R"
git checkout -q -b feat/m/u
printf 'base\n' > a.txt; git add a.txt; git commit -q -m "chore: base"
# 三個子 change 都從 PR 分支目前的 HEAD 開（subagent 的起點）
git checkout -q -b feat/m--s1/u feat/m/u; printf 's1\n' > a.txt; git commit -q -am "feat: s1"; S1="$(git rev-parse HEAD)"
git checkout -q -b feat/m--s2/u feat/m/u; printf 's2\n' > a.txt; git commit -q -am "feat: s2"; S2="$(git rev-parse HEAD)"
git checkout -q -b feat/m--s3/u feat/m/u; printf 'b\n' > b.txt; git add b.txt; git commit -q -m "feat: s3"; S3="$(git rev-parse HEAD)"
git checkout -q -b other feat/m/u

# --- Scenario：不在 PR 分支上 ---
before="$(git rev-parse HEAD)"
out="$(opsx stack m s1 "$S1" 2>&1)"; rc=$?
[ $rc -ne 0 ] || fail "不在 PR 分支要拒絕: $out"
echo "$out" | grep -q 'feat/m/u' || fail "訊息要說 PR 分支: $out"
assert_eq "$(git rev-parse HEAD)" "$before" "不在 PR 分支不動歷史"

git checkout -q feat/m/u
base="$(git rev-parse HEAD)"

# --- Scenario：依賴的子 change 還沒疊回 ---
out="$(opsx stack m s2 "$S2" 2>&1)"; rc=$?
[ $rc -ne 0 ] || fail "依賴沒疊回要拒絕: $out"
echo "$out" | grep -q 's1' || fail "訊息要列出 s1: $out"
assert_eq "$(git rev-parse HEAD)" "$base" "依賴沒疊回不動歷史"

# --- 邊界：sha 不存在、子 change 不在 workplan、參數不對 ---
assert_rc 2 opsx stack m s1 0000000000000000000000000000000000000000
assert_rc 2 opsx stack m nope "$S1"
assert_rc 2 opsx stack m s1
assert_eq "$(git rev-parse HEAD)" "$base" "邊界都不動歷史"
assert_eq "$(git status --porcelain)" "" "邊界都不留髒 tree"

# --- Scenario：乾淨疊回 ---
out="$(opsx stack m s1 "$S1" 2>&1)"; assert_eq "$?" 0 "乾淨疊回: $out"
assert_eq "$(git rev-list --count "$base"..HEAD)" 1 "PR 分支多一個 commit"
assert_eq "$(git log -1 --format=%s)" "feat: s1" "subject 跟子 change 的 commit 一樣"
grep -q '^- \[x\] 1.1 `s1`' "$M/tasks.md" || fail "s1 要勾: $(cat "$M/tasks.md")"
grep -q '^- \[ \] 1.2 `s2`' "$M/tasks.md" || fail "s2 不該勾"
grep -q '^- \[ \] 1.3 `s3`' "$M/tasks.md" || fail "s3 不該勾"

# --- Scenario：兩個子 change 改同一行 ---
head="$(git rev-parse HEAD)"
out="$(opsx stack m s2 "$S2" 2>&1)"; rc=$?
assert_eq "$rc" 3 "衝突退出 3: $out"
echo "$out" | grep -q 'a.txt' || fail "要印衝突檔: $out"
assert_eq "$(git status --porcelain)" "" "衝突後工作目錄乾淨"
assert_eq "$(git rev-parse HEAD)" "$head" "衝突後 HEAD 不變"
assert_grep 's2' "$M/decisions.tsv"
assert_grep '疊回衝突' "$M/decisions.tsv"
grep -q '^- \[ \] 1.2 `s2`' "$M/tasks.md" || fail "衝突的 s2 不勾"

# 衝突之後沒依賴的子 change 照疊
out="$(opsx stack m s3 "$S3" 2>&1)"; assert_eq "$?" 0 "s3 疊回: $out"
grep -q '^- \[x\] 1.3 `s3`' "$M/tasks.md" || fail "s3 要勾"
echo ok
