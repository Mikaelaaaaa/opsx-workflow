#!/usr/bin/env bash
# opsx next：feature session 做完一個主 change（開了 MR、等合併）後，印同 feature 下一個主 change 該跑的指令。
# 驗收：openspec/changes/session-entry-core/subs/session-next/specs/session-dispatch/spec.md「session 做完一個主 change 接下一個」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo nx)"; mk_change "$R" m1; mkdir -p "$OPSX_STATE_DIR"
git -C "$R" checkout -q -
# fs 是新形 PR（PR 名就是主殼名）；old 是舊形 PR（PR 名 p1、p2 ≠ change 名 o1、o2，branch 第二段對不到卡）
cat > "$R/openspec/workplan.yaml" <<'EOF'
features:
  - name: fs
    prs:
      - name: m1
        branch: feat/m1/mikaela
        status: in-progress
        depends-on: []
        changes:
          - name: a1
            status: done
      - name: m2
        branch: feat/m2/mikaela
        status: pending
        depends-on: []
        changes:
          - name: a2
            status: pending
      - name: m3
        branch: feat/m3/mikaela
        status: pending
        depends-on: []
        changes:
          - name: a3
            status: pending
  - name: old
    prs:
      - name: p1
        branch: feat/p1/mikaela
        status: in-progress
        depends-on: []
        changes:
          - name: o1
            status: done
      - name: p2
        branch: feat/p2/mikaela
        status: pending
        depends-on: []
        changes:
          - name: o2
            status: pending
EOF
mkdir -p "$R/openspec/changes/m2" "$R/openspec/changes/m3" "$R/openspec/changes/o1" "$R/openspec/changes/o2"
printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/m2/.openspec.yaml"
printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/m3/.openspec.yaml"
printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/o1/.openspec.yaml"
printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/o2/.openspec.yaml"
printf -- '- [x] 1.1 x\n' > "$R/openspec/changes/m1/tasks.md"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/m2/tasks.md"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/m3/tasks.md"
printf -- '- [x] 1.1 x\n' > "$R/openspec/changes/o1/tasks.md"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/o2/tasks.md"
printf '# report\n\nhttps://github.com/o/r/pull/7\n' > "$R/openspec/changes/m1/report.md"
printf '# report\n\nhttps://github.com/o/r/pull/9\n' > "$R/openspec/changes/o1/report.md"
# session 的 worktree 叫 feature 名，checkout 目前主 change 的 branch
git -C "$R" worktree add -q "$R/.claude/worktrees/fs" feat/m1/mikaela
git -C "$R" worktree add -q -b feat/p1/mikaela "$R/.claude/worktrees/old"
git -C "$R" worktree add -q -b feat/lone/mikaela "$R/.claude/worktrees/lone"
J="$OPSX_STATE_DIR/dispatch.json"
session() { printf '"nx/@%s":{"mode":"autopilot","pane":"w1:p1","agent":"claude","worktree":"%s/.claude/worktrees/%s"}' "$1" "$R" "$1"; }
entry() { printf '"nx/%s":{"mode":"autopilot","pane":"w1:p1","agent":"claude","herdr_name":"%s","via":"@%s","feature":"%s","branch":"feat/%s/mikaela"}' "$1" "$2" "$2" "$2" "$1"; }
cd "$R/.claude/worktrees/fs"

# --- Scenario：第一個主 change 開了 MR，接第二個（條目順序和 workplan 不同，照 workplan）---
printf '{%s,%s,%s,%s}' "$(session fs)" "$(entry m3 fs)" "$(entry m1 fs)" "$(entry m2 fs)" > "$J"
assert_eq "$(opsx next)" "/opsx-workflow:apply m2" "m1 等合併，接 m2"

# --- 三個兄弟：m2 也開了 MR，接 m3 ---
printf '# report\n\nhttps://github.com/o/r/pull/8\n' > "$R/openspec/changes/m2/report.md"
assert_eq "$(opsx next)" "/opsx-workflow:apply m3" "m1、m2 等合併，接 m3"

# --- Scenario：沒有下一個（全部都開了 MR）---
printf '# report\n\nhttps://github.com/o/r/pull/10\n' > "$R/openspec/changes/m3/report.md"
assert_eq "$(opsx next)" "none" "全部都開了 MR"
rm "$R/openspec/changes/m2/report.md" "$R/openspec/changes/m3/report.md"

# --- 已歸檔（卡資料夾不在）的成員不算 ---
mv "$R/openspec/changes/m2" "$FX/m2-archived"
assert_eq "$(opsx next)" "/opsx-workflow:apply m3" "m2 歸檔了，接 m3"
mv "$FX/m2-archived" "$R/openspec/changes/m2"

# --- 別的 feature 的條目不算、停掉的不算 ---
printf '{%s,%s,%s}' "$(session fs)" "$(entry m1 fs)" "$(entry m2 other)" > "$J"
assert_eq "$(opsx next)" "none" "別的 feature 不接"
printf '{%s,%s,%s}' "$(session fs)" "$(entry m1 fs)" "$(entry m2 fs | sed 's/"mode":"autopilot"/"mode":"stopped"/')" > "$J"
assert_eq "$(opsx next)" "none" "停掉的不接"

# --- Scenario：舊形 PR 在 session 裡接下一個（branch feat/p1 對不到卡 o1）---
printf '{%s,%s,%s}' "$(session old)" "$(entry o1 old)" "$(entry o2 old)" > "$J"
cd "$R/.claude/worktrees/old"
assert_eq "$(opsx next)" "/opsx-workflow:apply o2" "舊形 PR：o1 等合併，接 o2"

# --- Scenario：沒有下一個（所在 worktree 沒有 session 條目）---
cd "$R/.claude/worktrees/fs"
printf '{%s,%s}' "$(entry m1 fs)" "$(entry m2 fs)" > "$J"
assert_eq "$(opsx next)" "none" "沒有 session 條目"

# --- 不在 session worktree：worktree 沒有條目、主 checkout、不在 opsx 的 worktree 目錄 ---
cd "$R/.claude/worktrees/lone"
assert_eq "$(opsx next)" "none" "worktree 沒有對應的 session 條目"
cd "$R"
git -C "$R" checkout -q -b feat/m2/mikaela
assert_eq "$(opsx next)" "none" "主 checkout 不是 session worktree，branch 對得到卡也不推"
O="$FX/outside-wt"
git -C "$R" worktree add -q -b scratch "$O"
cd "$O"
assert_eq "$(opsx next)" "none" "不在 .claude/worktrees 底下"

# --- 單卡的 worktree 名剛好等於某個 feature 名：session 條目記的 worktree 不是這棵，就不是這個 session ---
printf '{"nx/@lone":{"mode":"autopilot","pane":"w1:p1","agent":"claude","worktree":"%s/.claude/worktrees/fs"},%s,%s}' "$R" "$(entry m1 lone)" "$(entry m2 lone)" > "$J"
cd "$R/.claude/worktrees/lone"
assert_eq "$(opsx next)" "none" "worktree 名撞 feature 名，但 session 記的是別棵"
cd "$R/.claude/worktrees/fs"
assert_eq "$(opsx next)" "/opsx-workflow:apply m2" "照 session 條目記下的 worktree 認，不照目錄名"

assert_rc 2 opsx next extra
echo ok
