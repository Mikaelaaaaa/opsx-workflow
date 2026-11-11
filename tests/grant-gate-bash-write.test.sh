#!/usr/bin/env bash
# Bash 寫檔套用 Edit / Write 同一套第二級判斷：env 檔要 env 授權、沒有既有測試的目錄寫測試檔要 test-path 授權。
# 驗收：openspec/changes/me-20261111-1824/specs/grant-gate-segments/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/grant-gate-fixture.sh"

mkdir -p "$R/tests" "$R/src/newdir" "$R/app"
printf 'x\n' > "$R/tests/a.test.sh"; git -C "$R" add tests/a.test.sh; git -C "$R" commit -q -m "fixture: tests"

# test-path：沒有既有測試的目錄
for c in 'cp /tmp/a.test.ts src/newdir/a.test.ts' 'mv /tmp/a.spec.ts src/newdir/a.spec.ts' 'git mv x.ts src/newdir/test_x.py' 'echo x > src/newdir/b_test.go' 'echo x >> src/newdir/c.test.ts' 'echo x | tee src/newdir/d.test.ts' 'echo x | tee -a src/newdir/e.test.ts'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "Bash 寫測試檔要 test-path（${c}）: $(cat "$FX/hook.err")"
  reason "$out" | grep -qF 'action: test-path' || fail "deny 要帶 action: test-path（${c}）: $(reason "$out")"
done
out="$(gg 'cat > src/newdir/f.test.ts <<EOF
x
EOF')"; assert_eq "$(decision "$out")" deny "heredoc 寫測試檔"
# 有既有測試的目錄、檔名不像測試：不管
for c in 'cp /tmp/b.test.ts tests/b.test.ts' 'echo x > src/newdir/helper.ts' 'cp a.txt src/newdir/' 'echo hi > out.log' 'echo hi > /dev/null' 'cmd 2>&1' 'echo hi > "$OUT"'; do
  out="$(gg "$c")"; assert_eq "$out" "" "不該出聲（${c}）: $(reason "$out")"
done
# 授權之後放行
card_grants '["test-path"]'
out="$(gg 'cp /tmp/a.test.ts src/newdir/a.test.ts')"; assert_eq "$(decision "$out")" allow "有 test-path 授權: $(reason "$out")"
card_grants '[]'

# env
for c in 'cat > app/.env.local <<EOF
K=v
EOF' 'echo K=v >> app/.env' 'cp /tmp/x app/prod.env'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "Bash 寫 env 檔要 env 授權（${c}）"
  reason "$out" | grep -qF 'action: env' || fail "deny 要帶 action: env（${c}）: $(reason "$out")"
done
out="$(gg 'cp /tmp/x app/.env.example')"; assert_eq "$out" "" ".env.example 不管"
card_grants '["env"]'
out="$(gg 'echo K=v >> app/.env')"; assert_eq "$(decision "$out")" allow "有 env 授權: $(reason "$out")"
card_grants '[]'

# 偵測的洞：重導向黏在字後、命令字前有前綴或括號、tab、整個被引號包住的目標
for c in 'echo K=v>app/.env' 'cat /tmp/k>app/.env' 'echo x>src/newdir/a.test.ts' '(cp a app/x.env)' 'FOO=1 cp a app/x.env' '/bin/cp a app/x.env' 'command cp a app/x.env' "$(printf 'cp\ta app/x.env')" 'echo ok && echo K=v&>app/.env' 'git --git-dir x mv a src/newdir/a.test.ts'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "Bash 寫入偵測要認得（${c}）: $(cat "$FX/hook.err")"
done
out="$(gg 'echo K=v >> "$APP/.env"')"; assert_eq "$(decision "$out")" deny "整個被引號包住的 env 目標要擋"
reason "$out" | grep -qF '讀不到' || fail "deny 要說讀不到: $(reason "$out")"
out="$(gg 'echo hi > "$OUT"')"; assert_eq "$out" "" "原文沒提到 env 或測試檔就不管"

# >&檔名是寫檔、大小寫與 /dev 路徑
for c in 'echo x >&src/newdir/a.test.ts' 'cat k > app/.Env' 'echo x > src/newdir/a.TEST.ts' 'echo x > /dev/../tmp/app/.env' "echo x > $R/app/.env"; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "要擋（${c}）: $(cat "$FX/hook.err")"
done
for c in 'cmd >&2' 'cmd 2>&1' 'echo x > /dev/null' 'echo x 2> /dev/stderr'; do
  out="$(gg "$c")"; assert_eq "$out" "" "不該出聲（${c}）: $(reason "$out")"
done
# 已授權的寫檔只涵蓋寫它的那一段（有 env 授權）
card_grants '["env"]'
for c in 'echo K=v >> app/.env && ./evil.sh app/.env' 'echo K=v >> app/.env && node run.js app/.env' 'cp /tmp/x app/.env && chmod +x app/.env'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "已授權的寫檔不能涵蓋別的段（${c}）: $(reason "$out")"
done
for c in 'echo K=v >> app/.env' 'cp /tmp/x app/.env'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" allow "已授權的寫檔本身要放行（${c}）: $(reason "$out")"
done
card_grants '[]'

# 取不到字面目錄：deny 並說明
for c in 'cp x.txt "$DEST"/a.test.ts' 'cp x.txt src/*/a.test.ts' 'echo x > $(pwd)/a.test.ts' 'cp x.txt ../a.test.ts'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "讀不到目錄要 deny（${c}）"
  reason "$out" | grep -qF '讀不到' || fail "deny 要說讀不到（${c}）: $(reason "$out")"
done
echo "grant-gate-bash-write ok"
