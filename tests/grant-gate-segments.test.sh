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

# 命令替換與反引號裡的指令也逐段查：藏在允許的前綴或 echo 底下也要擋
for c in 'git push && git add $(rm -rf important)' 'git push && git add `rm -r important`' 'git push $(rm -rf important)' 'git push && echo $(./evil.sh)' 'git push && git status $(touch .env)' 'git push && (./evil.sh)' 'git push && cat <(./evil.sh)'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "命令替換裡沒涵蓋的指令要擋（${c}）: $(reason "$out")"
done
# heredoc、算術、小指令帶重導向、分行、前綴子串：後面的指令仍逐段查（骨架已移掉 heredoc，這一層不能再移一次）
for c in $'git push\ncat <<EOF\nx\nEOF\n./evil' $'git push && cat <<EOF > notes.txt\nhello\nEOF\ngit status; ./evil' $'git push\ncat <<<foo\n./evil\nfoo' $'git push\necho $((1<<2))\n./evil\necho 2' $'git push && cd /tmp && bash <<EOF\n./evil\nEOF' 'git push && echo $((1+$(./evil)))' 'git push && echo $((./evil) )' 'git push && echo $(( $(./evil) ))' 'git push && echo x > .husky/pre-commit' 'git push && cd . > src/important.ts' $'git push\n./evil' 'git push && git status `./evil`' 'git push && echo "`./evil`"' 'git push && git addx'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "要擋（${c}）: $(reason "$out")"
done
for c in $'git push && cat <<EOF > notes.txt\nhello\nEOF\ngit status' 'git push && echo $((1+2))'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" allow "涵蓋的要放行（${c}）: $(reason "$out")"
done
# 命令替換裡是涵蓋的指令、子 shell 裡是涵蓋的指令：放行
for c in 'git push origin $(git branch --show-current)' 'git push && echo $(date)' '( cd /x && git push )' 'git push origin "$(git branch --show-current)"'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" allow "涵蓋的命令替換與子 shell 要放行（${c}）: $(reason "$out")"
done
# 只有 mr 授權：管線與背景符號緊接在前面的 push、rebase、rm 一樣要授權
printf '[repos."Agentory-AI"]\npush = false\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
card_grants '["mr"]'
for c in 'gh pr create --title x; echo |git push' 'gh pr create --title x ||git push origin feat' 'gh pr create --title x &git push' 'gh pr create --title x; echo|rm -rf important' 'gh pr create --title x; git status|git rebase main'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "沒授權的類別不能跟著 mr 授權放行（${c}）: $(reason "$out")"
done
card_grants '[]'
printf '[repos."Agentory-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"

# 單段指令不需要 settings：沒有 settings 檔也照放行
rm -f "$SETTINGS"
out="$(gg 'git push')"; assert_eq "$(decision "$out")" allow "單段不讀 settings: $(reason "$out")"
out="$(gg 'cd /x && git push')"; assert_eq "$(decision "$out")" allow "cd 與授權的段不讀 settings: $(reason "$out")"
# 串了需要查 settings 的段、settings 讀不到：deny，說明原因
out="$(gg 'git add a.txt && git push')"; assert_eq "$(decision "$out")" deny "讀不到 settings 要擋: $(reason "$out")"
reason "$out" | grep -qF "$SETTINGS" || fail "deny 要點名 settings 路徑: $(reason "$out")"
# feature session：dispatch 條目的 herdr_name 是 feature 名，settings 檔在 feature 名之下（dispatch.sh 以 feature 當 slug 寫）
printf '{"Agentory-AI/eval-core":{"mode":"autopilot","grants":[],"herdr_name":"fsess","feature":"fsess","via":"@fsess"}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '{"permissions":{"allow":["Bash(git add:*)","Bash(git commit:*)"]}}' > "$OPSX_STATE_DIR/settings/Agentory-AI-fsess-autopilot.json"
out="$(gg 'git add a.txt && git commit -m x && git push')"; assert_eq "$(decision "$out")" allow "feature session 要用 feature 名找 settings: $(reason "$out")"
out="$(gg 'git -C . merge origin/main && git push')"; assert_eq "$(decision "$out")" deny "feature session 的 settings 也要擋 allow 外的段"
echo "grant-gate-segments ok"
