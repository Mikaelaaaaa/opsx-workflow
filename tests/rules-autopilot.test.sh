#!/usr/bin/env bash
# rules-autopilot：rule_autopilot 寫明 worktree 的 openspec 路徑與測試指令寫法，測試指令依 repo 有沒有 tests/run.sh 決定。
# 驗收：openspec/changes/me-20261111-1326/specs/opsx-autonomy/spec.md「agent 規則寫明 worktree 的 openspec 路徑」
#       openspec/changes/agent-20261116-1405/specs/opsx-autonomy/spec.md「agent 規則規定測試指令的寫法」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$OPSX_ROOT/bin/lib/rules.sh"
has() { case "$1" in *"$2"*) ;; *) fail "rule_autopilot 缺 [$2]" ;; esac; }
gone() { case "$1" in *"$2"*) fail "rule_autopilot 不該有 [$2]" ;; esac; }

r="$(rule_autopilot "$OPSX_ROOT")"
# Scenario：autopilot 規則提到主 checkout
has "$r" '主 checkout'
has "$r" 'openspec/changes/<slug>/'
has "$r" 'worktree 裡沒有 `openspec/`'
# cd 會留到後面每個 Bash 呼叫：跑完 openspec 要回 worktree 根，否則測試、opsx、router 都在主 checkout 上看 cwd
has "$r" 'cd <主 checkout 絕對路徑> && openspec'
has "$r" 'cd <worktree 根>'
# Scenario：有 tests/run.sh 的 repo 注入 bash tests/run.sh
has "$r" 'bash tests/run.sh'
has "$r" '不加 `VAR=…` 或 `export`'
gone "$r" 'OPSX_ROOT='
# opsx-workflow 的 decision 由協調者照建議答，其餘 gate 由使用者答；操作類題不開 gate（coordinate-answer-opsx-gates D3、me-20261112-1415 D4）
has "$r" 'opsx-workflow 的 decision 由協調者照建議答'
has "$r" '其餘 gate 由使用者答'
gone "$r" '協調者不代答'
has "$r" '不開 gate'
# 沙盒擋掉、跑一次就解掉的 needs: run 題標 by: coordinator；ring3、要人看、裝依賴的不標（coordinator-run-owned）
has "$r" 'by: coordinator'
has "$r" '跑一次'
has "$r" 'push'
has "$r" 'ring3'
has "$r" '重開 pane'
BY="$(printf '%s' "$r" | tr '；' '\n' | grep -F 'by: coordinator')"
case "$BY" in *代答*) fail "寫 by: coordinator 的那句不該說代答：$BY" ;; esac
# 段與段用 ' · ' 隔開，AGENTS.md 依它拆條列：「Bash 會被 dontAsk 拒的寫法」要是自己的一段
has "$r" ' · Bash 會被 dontAsk 拒的寫法'
gone "$r" ' ·Bash'
# 新增的是 ' · ' 段，不是另一行
case "$r" in *$'\n'*) fail "rule_autopilot 要維持單行" ;; esac

# Scenario：沒有 tests/run.sh 的 repo 不注入 bash tests/run.sh
N="$(mk_repo NoRunner)"
n="$(rule_autopilot "$N")"
gone "$n" 'bash tests/run.sh'
has "$n" 'CLAUDE.md'
has "$n" 'package.json / pyproject'
has "$n" 'pnpm test'
has "$n" 'pytest'
has "$n" '主 checkout'
case "$n" in *$'\n'*) fail "rule_autopilot 要維持單行" ;; esac
# test-run-rule-edges Scenario Outline：否分支列出前綴規則與清單外做法（一般 4 列、邊界 1 列）
has "$n" '不加 `VAR=…` 或 `export`'
has "$n" '`TEST_DATABASE_URL=`'
has "$n" 'needs: run gate'
has "$n" '不換寫法重試'
has "$n" 'pnpm vitest'
case "$n" in *'TEST_DATABASE_URL='*'pnpm test / pnpm vitest 除外'*) ;; *) fail "TEST_DATABASE_URL 例外要點名 pnpm test 與 pnpm vitest: $n" ;; esac
# test-run-rule-edges Scenario：有 run.sh 分支寫明只認檔名；否分支不提
U="$(mk_repo UnrelatedRunner)"
mkdir -p "$U/tests"; printf '#!/usr/bin/env bash\nmake test\n' > "$U/tests/run.sh"
u="$(rule_autopilot "$U")"
has "$u" 'bash tests/run.sh'
has "$u" '只認 `tests/run.sh` 這個檔名'
gone "$n" '只認 `tests/run.sh` 這個檔名'
# 反例：有 tests/run.sh 時不出現否分支的字句
gone "$r" 'TEST_DATABASE_URL='
gone "$r" '不換寫法重試'
# Scenario Outline 邊界：沒有 package.json 的 repo 不提醒 pnpm docs:api
gone "$n" 'pnpm docs:api'
gone "$r" 'pnpm docs:api'

# Scenario：package.json 有 docs:api script 時提醒單獨下（me-20261116-1650-2）
D="$(mk_repo DocsApi)"
printf '{"scripts":{"build":"tsc","docs:api":"tsx scripts/api-docs/gen.ts"}}\n' > "$D/package.json"
d="$(rule_autopilot "$D")"
has "$d" ' · `pnpm docs:api` 要單獨下'
# openspec 規則會 cd 到主 checkout；沒先回 worktree 根，沙箱外的產生器就寫進主 checkout 的 docs/api/
has "$d" '先單獨 cd 到 worktree 根'
# 提醒看 worktree 的 package.json、allow 看主 checkout 的，兩邊對不上時 dontAsk 會拒
has "$d" '被 dontAsk 拒就開 needs: run gate，不換寫法重試'
has "$d" '不接 `cd … &&`'
has "$d" '不接 pipe'
gone "$d" ' ·  · '
case "$d" in *' · ') fail "rule_autopilot 不該以分隔符結尾" ;; esac
case "$d" in *$'\n'*) fail "rule_autopilot 要維持單行" ;; esac
# Scenario Outline 一般：package.json 只有 build 與 test 不提醒
B="$(mk_repo BuildTestOnly)"
printf '{"scripts":{"build":"tsc","test":"vitest"}}\n' > "$B/package.json"
gone "$(rule_autopilot "$B")" 'pnpm docs:api'

# Scenario：沒給 repo 根目錄就失敗
assert_rc 1 rule_autopilot
rule_autopilot 2>&1 | grep -q 'repo 根目錄' || fail "沒給參數的錯誤訊息要說缺 repo 根目錄"
echo ok
