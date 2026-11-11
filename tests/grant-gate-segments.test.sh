#!/usr/bin/env bash
# 複合指令逐段判斷：有一段有授權不能替整串放行；每一段都要有授權、或在 dispatch 給這個 agent 的 settings allow 裡。
# 驗收：openspec/changes/me-20261111-1824/specs/grant-gate-segments/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/grant-gate-fixture.sh"

# 有授權的段（repo 永遠 push）帶出 settings allow 外的段：deny，點名那一段
out="$(gg 'git -C . merge origin/main && git push')"; assert_eq "$(decision "$out")" deny "settings allow 外的段不能跟著放行: $(reason "$out")"
reason "$out" | grep -qF 'git -C . merge origin/main' || fail "deny 要點名沒涵蓋的那一段: $(reason "$out")"
out="$(gg 'git push; git -c core.x=y merge origin/main')"; assert_eq "$(decision "$out")" deny "順序反過來也一樣: $(reason "$out")｜$(head -c 300 "$FX/hook.err")"

# mr 有授權（這張卡），後面接沒分類、不在 allow 的 glab api 寫入：deny
card_grants '["mr"]'
out="$(gg 'gh pr create --title x; glab api --method PUT projects/1/merge_requests/999/merge')"
assert_eq "$(decision "$out")" deny "glab api 寫入不能跟著 mr 授權放行: $(reason "$out")"
reason "$out" | grep -qF 'glab api' || fail "deny 要點名 glab api: $(reason "$out")"
card_grants '[]'

# 都涵蓋的串接照放行
for c in 'git add a.txt && git commit -m x && git push' 'git merge -s ours origin/main && git push' 'cd /x && git push' 'git push && echo done' 'git push 2>&1' 'git status && git push 2>&1 | cat'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" allow "涵蓋的串接要放行（${c}）: $(reason "$out")"
  assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')" allow "要明說 allow（${c}）"
done

# 單段指令不需要 settings：沒有 settings 檔也照放行
rm -f "$SETTINGS"
out="$(gg 'git push')"; assert_eq "$(decision "$out")" allow "單段不讀 settings: $(reason "$out")"
out="$(gg 'cd /x && git push')"; assert_eq "$(decision "$out")" allow "cd 與授權的段不讀 settings: $(reason "$out")"
# 串了需要查 settings 的段、settings 讀不到：deny，說明原因
out="$(gg 'git add a.txt && git push')"; assert_eq "$(decision "$out")" deny "讀不到 settings 要擋: $(reason "$out")"
reason "$out" | grep -qF "$SETTINGS" || fail "deny 要點名 settings 路徑: $(reason "$out")"
echo "grant-gate-segments ok"
