#!/usr/bin/env bash
# rules-autopilot：rule_autopilot 寫明 worktree 的 openspec 路徑與測試指令寫法。
# 驗收：openspec/changes/me-20261111-1326/specs/opsx-autonomy/spec.md「agent 規則寫明 worktree 的 openspec 路徑」「agent 規則規定測試指令的寫法」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$OPSX_ROOT/bin/lib/rules.sh"
has() { case "$1" in *"$2"*) ;; *) fail "rule_autopilot 缺 [$2]" ;; esac; }
gone() { case "$1" in *"$2"*) fail "rule_autopilot 不該有 [$2]" ;; esac; }

r="$(rule_autopilot)"
# Scenario：autopilot 規則提到主 checkout
has "$r" '主 checkout'
has "$r" 'openspec/changes/<slug>/'
has "$r" 'worktree 裡沒有 `openspec/`'
# Scenario：autopilot 規則含測試寫法
has "$r" 'bash tests/run.sh'
has "$r" '不加 `VAR=…` 或 `export`'
gone "$r" 'OPSX_ROOT='
# 新增的是 ' · ' 段，不是另一行
case "$r" in *$'\n'*) fail "rule_interactive 之外的規則要維持單行" ;; esac
echo ok
