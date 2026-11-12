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
# cd 會留到後面每個 Bash 呼叫：跑完 openspec 要回 worktree 根，否則測試、opsx、router 都在主 checkout 上看 cwd
has "$r" 'cd <主 checkout 絕對路徑> && openspec'
has "$r" 'cd <worktree 根>'
# Scenario：autopilot 規則含測試寫法
has "$r" 'bash tests/run.sh'
has "$r" '不加 `VAR=…` 或 `export`'
gone "$r" 'OPSX_ROOT='
# gate 一律由使用者答；操作類題不開 gate（me-20261112-1415 D3、D4）
has "$r" '協調者不代答'
has "$r" '不開 gate'
# 段與段用 ' · ' 隔開，AGENTS.md 依它拆條列：「Bash 會被 dontAsk 拒的寫法」要是自己的一段
has "$r" ' · Bash 會被 dontAsk 拒的寫法'
gone "$r" ' ·Bash'
# 新增的是 ' · ' 段，不是另一行
case "$r" in *$'\n'*) fail "rule_autopilot 要維持單行" ;; esac
echo ok
