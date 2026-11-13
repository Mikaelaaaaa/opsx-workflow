#!/usr/bin/env bash
# 協調者與 reap 的 herdr argv 由 runtime.py 產生：原始碼裡以 "herdr" 開頭的 list 字面值只剩 pane process-info 一處。
# 驗收：openspec/changes/runtime-py-callers/subs/runtime-coordinate/specs/agent-runtime/spec.md「原始碼不直接寫 herdr argv」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# 允許清單比對行內容，不比行號：行號一動就誤判
grep -nE '\[ *"herdr" *,' "$OPSX_ROOT/bin/lib/coordinate.py" "$OPSX_ROOT/bin/lib/reap.py" > "$FX/hits"
assert_eq "$(grep -c '"process-info"' "$FX/hits" || true)" 1 "coordinate.py 的 pane process-info 要留著直接呼叫：$(cat "$FX/hits")"
assert_eq "$(grep -vc '"process-info"' "$FX/hits" || true)" 0 "只准 pane process-info 直接寫 herdr argv：$(cat "$FX/hits")"

echo "ok runtime-py-callers"
