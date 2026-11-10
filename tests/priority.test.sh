#!/usr/bin/env bash
# opsx priority：milestone 欄位、收件卡事實欄位、等級計算、依賴繼承、--set 覆寫。
# 驗收：openspec/changes/workplan-priority/specs/opsx-priority/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

R="$(mk_repo prio)"; mkdir -p "$R/openspec/changes"
card() { # card <slug> [frontmatter 行…]：建殼與 inbox.md
  local d="$R/openspec/changes/$1"; shift
  mkdir -p "$d"; printf 'schema: opsx\nkind: dev\n' > "$d/.openspec.yaml"
  { printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-10\nrelated:\n'; printf '%s\n' "$@"; printf -- '---\n\n## 一句話\n\n%s\n' "$(basename "$d")"; } > "$d/inbox.md"
}
wp() { cat > "$R/openspec/workplan.yaml"; }
pr() { opsx priority "$@" --repo "$R"; }
ERR="$FX/err"
level_of() { pr "$1" | cut -f1; }
reason_of() { pr "$1" | cut -f2; }
expect() { # expect <slug> <level> <理由裡要有的字>
  local out; out="$(pr "$1" 2>"$ERR")" || fail "${1}：opsx priority 失敗：$(cat "$ERR")"
  assert_eq "${out%%$'\t'*}" "$2" "$1 的等級（${out}）"
  case "$out" in *"$3"*) ;; *) fail "$1 的理由要含「${3}」：${out}" ;; esac
}
expect_err() { # expect_err <slug> <stderr 要有的字…>
  local s="$1"; shift
  ! pr "$s" > /dev/null 2>"$ERR" || fail "$s 應該退出非 0"
  local w; for w in "$@"; do assert_grep "$w" "$ERR"; done
}

# --- Scenario：沒有 milestone 的 workplan 照讀；沒設目前 milestone（D8） ---
wp <<'EOF'
features:
  - name: f1
    prs:
      - name: p-plain
        branch: feat/p-plain/m
        status: pending
        depends-on: []
        changes:
          - name: plain
            status: pending
EOF
card plain
expect plain P1 "沒設目前 milestone"

# --- Scenario：沒寫 kind_of_work 當 planned；不在 workplan ---
card loose
expect loose P2 "不在 workplan"

# --- Scenario：在目前 milestone / 在別的 milestone ---
wp <<'EOF'
milestones:
  - name: "1.0"
    goal: "能開單出貨"
  - name: "2.0"
    goal: "能退貨"
current_milestone: "1.0"
features:
  - name: order
    milestone: "1.0"
    prs:
      - name: p-now
        branch: feat/p-now/m
        status: pending
        depends-on: []
        changes:
          - name: now
            status: pending
  - name: later
    milestone: "2.0"
    prs:
      - name: p-later
        branch: feat/p-later/m
        status: pending
        depends-on: []
        changes:
          - name: later
            status: pending
EOF
card now "kind_of_work: planned"; card later
expect now P1 "1.0"
expect later P2 "2.0"
expect loose P2 "不在 workplan"

# --- Scenario：feature / current_milestone 指到不存在的 milestone ---
cp "$R/openspec/workplan.yaml" "$FX/good.yaml"
sed 's/milestone: "2.0"/milestone: "9.9"/' "$FX/good.yaml" > "$R/openspec/workplan.yaml"
expect_err now later 9.9
sed 's/^current_milestone: "1.0"/current_milestone: "3.0"/' "$FX/good.yaml" > "$R/openspec/workplan.yaml"
expect_err now current_milestone 3.0
# workplan 讀不懂（形狀不對、不是 UTF-8）：報錯指名欄位，不丟 traceback
printf 'features: oops\n' > "$R/openspec/workplan.yaml"
expect_err now features
printf 'features:\n  - name: \xff\xfe\n' > "$R/openspec/workplan.yaml"
expect_err now workplan
! grep -q Traceback "$ERR" || fail "不是 UTF-8 不能丟 traceback：$(cat "$ERR")"
cp "$FX/good.yaml" "$R/openspec/workplan.yaml"

# --- Scenario：incident 的等級 ---
card sec "kind_of_work: incident" "impact: security" "evidence: 未登入可讀 /admin"
expect sec P0 "security"
card multi "kind_of_work: incident" "impact: data, prod_or_main" "evidence: log 在 ## 證據"
expect multi P0 "data"
card wa "kind_of_work: incident" "impact: workaround_exists" "evidence: 手動重跑可過"
expect wa P1 "workaround_exists"
card stuck "kind_of_work: incident" "impact: blocks_all_agents" "evidence: hook 全擋"
expect stuck P1 "blocks_all_agents"
card bare "kind_of_work: incident"
expect bare P2 "incident"

# --- Scenario：impact 沒有 evidence / 值域外 ---
card noev "kind_of_work: incident" "impact: security"
expect_err noev evidence noev
card blankev "kind_of_work: incident" "impact: security" "evidence:   "
expect_err blankev evidence blankev
card badimp "kind_of_work: incident" "impact: urgent" "evidence: x"
expect_err badimp impact urgent
card badkind "kind_of_work: hotfix"
expect_err badkind kind_of_work hotfix
# D3 字面的寫法：impact 底下縮排 <值>: true 與 evidence（真實卡 pane-reaper 的形狀）
card nested "kind_of_work: incident" "impact:" "  workaround_exists: true" '  evidence: "手動 opsx stop 可替代"'
expect nested P1 "workaround_exists"
card nestedsec "kind_of_work: incident" "impact:" "  security: true" "  data: false" "  evidence: x"
expect nestedsec P0 "security"
card nestednoev "kind_of_work: incident" "impact:" "  security: true"
expect_err nestednoev evidence nestednoev
card nestedbad "kind_of_work: incident" "impact:" "  security: maybe" "  evidence: x"
expect_err nestedbad security maybe
card nestedkind "kind_of_work:" "  incident: true"
expect_err nestedkind kind_of_work
card noreason "kind_of_work: incident" "priority: P0"
expect_err noreason priority_reason noreason
# 壞一張卡不影響別張
expect sec P0 "security"

# --- Scenario：依賴繼承（PR、間接、feature 層） ---
R0="$R";R="$(mk_repo inh)"; mkdir -p "$R/openspec/changes"
wp <<'EOF'
features:
  - name: f
    prs:
      - name: fix-auth
        branch: feat/fix-auth/m
        status: pending
        depends-on: [token-store]
        changes:
          - name: auth
            status: pending
      - name: token-store
        branch: feat/token-store/m
        status: pending
        depends-on: [crypto]
        changes:
          - name: token
            status: pending
      - name: crypto
        branch: feat/crypto/m
        status: pending
        depends-on: []
        changes:
          - name: crypto
            status: pending
  - name: g
    depends-on: [lone]
    prs:
      - name: g-pr
        branch: feat/g-pr/m
        status: pending
        changes:
          - name: g-card
            status: pending
      - name: lone
        branch: feat/lone/m
        status: pending
        changes:
          - name: lone
            status: pending
EOF
card auth "kind_of_work: incident" "impact: security" "evidence: 憑證外洩"
card token "kind_of_work: incident"
card crypto "kind_of_work: incident"
expect token P0 "auth 在等它"
expect crypto P0 "auth 在等它"
expect auth P0 "security"
card g-card "kind_of_work: incident" "impact: prod_or_main" "evidence: main 紅"
card lone "kind_of_work: incident"
expect lone P0 "g-card 在等它"

# --- Scenario：依賴有環不卡住 ---
R="$(mk_repo cyc)"; mkdir -p "$R/openspec/changes"
wp <<'EOF'
features:
  - name: f
    prs:
      - name: a
        branch: feat/a/m
        status: pending
        depends-on: [b]
        changes:
          - name: a
            status: pending
      - name: b
        branch: feat/b/m
        status: pending
        depends-on: [a]
        changes:
          - name: b
            status: pending
EOF
card a; card b
out="$(perl -e 'alarm 5; exec @ARGV' opsx priority a --repo "$R")" || fail "有環時 5 秒內要退出 0"
assert_eq "${out%%$'\t'*}" P1 "有環的卡照算"

# --- Scenario：使用者覆寫 ---
R="$R0"
INB="$R/openspec/changes/later/inbox.md"
opsx priority later --set P0 --reason "客戶明天上線" --repo "$R" > /dev/null || fail "--set 失敗"
assert_grep '^priority: P0$' "$INB"
assert_grep '^priority_reason: 客戶明天上線$' "$INB"
assert_grep '等級改 P0' "$R/openspec/changes/later/decisions.tsv"
expect later P0 "客戶明天上線"
head -1 "$INB" | grep -qx -- '---' || fail "frontmatter 開頭還在"
assert_grep '^## 一句話' "$INB"

cp "$INB" "$FX/inbox.before"; cp "$R/openspec/changes/later/decisions.tsv" "$FX/dec.before"
assert_rc 1 opsx priority later --set P1 --repo "$R"
assert_rc 1 opsx priority later --set P1 --reason "   " --repo "$R"
! opsx priority later --set P1 --repo "$R" 2>"$ERR" >/dev/null; assert_grep 理由 "$ERR"
assert_rc 1 opsx priority later --set P3 --reason x --repo "$R"
! opsx priority later --set P3 --reason x --repo "$R" 2>"$ERR" >/dev/null; assert_grep P3 "$ERR"
cmp -s "$INB" "$FX/inbox.before" || fail "拒絕時 inbox.md 不能變"
cmp -s "$R/openspec/changes/later/decisions.tsv" "$FX/dec.before" || fail "拒絕時 decisions.tsv 不能變"

opsx priority later --set P2 --reason "客戶延期" --repo "$R" > /dev/null || fail "第二次 --set"
assert_eq "$(grep -c '^priority:' "$INB")" 1 "只留一行 priority:"
assert_eq "$(grep -c '^priority_reason:' "$INB")" 1 "只留一行 priority_reason:"
assert_grep '^priority: P2$' "$INB"
expect later P2 "客戶延期"

# --- 覆寫的卡往它依賴的卡傳等級 ---
R="$(mk_repo ovr)"; mkdir -p "$R/openspec/changes"
wp <<'EOF'
features:
  - name: f
    prs:
      - name: top
        branch: feat/top/m
        status: pending
        depends-on: [base]
        changes:
          - name: top
            status: pending
      - name: base
        branch: feat/base/m
        status: pending
        depends-on: []
        changes:
          - name: base
            status: pending
EOF
card top "kind_of_work: incident"; card base "kind_of_work: incident"
opsx priority top --set P0 --reason "老闆說" --repo "$R" > /dev/null || fail "--set top"
expect base P0 "top 在等它"

# --- 沒有這張卡 ---
expect_err nope nope

echo ok
