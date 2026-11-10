#!/usr/bin/env bash
# opsx next：feature session 做完一個主 change（開了 MR、等合併）後，印同 feature 下一個主 change 該跑的指令。
# 驗收：openspec/changes/apply-fanout/specs/session-dispatch/spec.md「session 做完一個主 change 接下一個」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo nx)"; mk_change "$R" m1; mkdir -p "$OPSX_STATE_DIR"
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
EOF
mkdir -p "$R/openspec/changes/m2"
printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/m2/.openspec.yaml"
printf -- '- [x] 1.1 x\n' > "$R/openspec/changes/m1/tasks.md"; printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/m2/tasks.md"
printf '# report\n\nhttps://github.com/o/r/pull/7\n' > "$R/openspec/changes/m1/report.md"
J="$OPSX_STATE_DIR/dispatch.json"
entry() { printf '"nx/%s":{"mode":"autopilot","pane":"w1:p1","agent":"claude","herdr_name":"fs","via":"fs","feature":"%s","branch":"feat/%s/mikaela"}' "$1" "$2" "$1"; }
cd "$R"

# --- Scenario：第一個主 change 開了 MR，接第二個 ---
printf '{%s,%s}' "$(entry m1 fs)" "$(entry m2 fs)" > "$J"
assert_eq "$(opsx next)" "/apply m2" "m1 等合併，接 m2"

# --- Scenario：沒有下一個（m2 也開了 MR）---
printf '# report\n\nhttps://github.com/o/r/pull/8\n' > "$R/openspec/changes/m2/report.md"
assert_eq "$(opsx next)" "none" "全部都開了 MR"
rm "$R/openspec/changes/m2/report.md"

# --- Scenario：沒有下一個（目前的卡不是 session 代管）---
printf '{"nx/m1":{"mode":"autopilot","pane":"w1:p1","agent":"claude"},%s}' "$(entry m2 fs)" > "$J"
assert_eq "$(opsx next)" "none" "不是 session 代管"

# --- 別的 feature 的條目不算、停掉的不算 ---
printf '{%s,%s}' "$(entry m1 fs)" "$(entry m2 other)" > "$J"
assert_eq "$(opsx next)" "none" "別的 feature 不接"
printf '{%s,%s}' "$(entry m1 fs)" "$(entry m2 fs | sed 's/"mode":"autopilot"/"mode":"stopped"/')" > "$J"
assert_eq "$(opsx next)" "none" "停掉的不接"

# --- 不在卡的分支上：rc 2 ---
git -C "$R" checkout -q -b scratch
assert_rc 2 opsx next
echo ok
