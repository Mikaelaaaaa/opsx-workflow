#!/usr/bin/env bash
# launch_args：dispatch 與 relaunch 共用的 agent 啟動參數。主殼 relaunch-cmd D1。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$OPSX_ROOT/bin/lib/common.sh"
source "$OPSX_ROOT/bin/lib/python.sh"
opsx_python_load || fail "python 載不起來：$OPSX_PY_ERR"
source "$OPSX_ROOT/bin/lib/launch.sh"

# 主 repo 路徑帶空白：陣列元素不能被拆開
TOP="$FX/my repo"; mkdir -p "$TOP/openspec"
SD="$OPSX_STATE_DIR"

# --- claude autopilot ---
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-CS retry-backoff "$TOP"
S="$SD/settings/Acmecorp-CS-retry-backoff-autopilot.json"
assert_eq "${#LAUNCH_ARGS[@]}" 10 "claude autopilot 參數個數"
assert_eq "${LAUNCH_ARGS[*]}" "--model claude-sonnet-5-5 --permission-mode dontAsk --settings $S --add-dir $TOP/openspec --add-dir $SD"
assert_eq "${LAUNCH_ARGS[7]}" "$TOP/openspec" "含空白的路徑要是同一個元素"
assert_file "$S"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert "allow" in d and "deny" in d,d;assert d["additionalDirectories"]==[sys.argv[2],sys.argv[3]],d' "$S" "$TOP/openspec" "$SD" || fail "autopilot settings 內容不對"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["env"]=={"OPSX_CARD":"retry-backoff"},d' "$S" || fail "autopilot settings 要帶 env OPSX_CARD"
# 同一組輸入呼叫兩次（dispatch 一次、relaunch 一次）：逐字相同
first=("${LAUNCH_ARGS[@]}")
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-CS retry-backoff "$TOP"
assert_eq "${LAUNCH_ARGS[*]}" "${first[*]}" "dispatch 與 relaunch 要拿到同一串參數"
assert_eq "${#LAUNCH_ARGS[@]}" "${#first[@]}" "第二次呼叫不能接在上一次的陣列後面"

# --- claude interactive：沒有 --permission-mode，settings 檔按模式分名 ---
launch_args claude claude-opus-5-5 interactive Acmecorp-CS retry-backoff "$TOP"
SI="$SD/settings/Acmecorp-CS-retry-backoff-interactive.json"
assert_eq "${LAUNCH_ARGS[*]}" "--model claude-opus-5-5 --settings $SI --add-dir $TOP/openspec --add-dir $SD"
assert_file "$SI"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert d=={"additionalDirectories":[sys.argv[2],sys.argv[3]]},d' "$SI" "$TOP/openspec" "$SD" || fail "interactive settings 只該有可寫目錄"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["env"]=={"OPSX_CARD":"retry-backoff"},d' "$SI" || fail "interactive settings 要帶 env OPSX_CARD"
assert_file "$S"   # 另一個模式那份不被蓋掉

# --- codex：不寫 settings ---
launch_args codex gpt-5-codex autopilot Acmecorp-CS codex-card "$TOP"
assert_eq "${LAUNCH_ARGS[*]}" "-a never -s workspace-write --add-dir $TOP/openspec --add-dir $SD"
launch_args codex gpt-5-codex interactive Acmecorp-CS codex-card "$TOP"
assert_eq "${LAUNCH_ARGS[*]}" "-a on-request -s workspace-write --add-dir $TOP/openspec --add-dir $SD"
assert_no_file "$SD/settings/Acmecorp-CS-codex-card-autopilot.json"
assert_no_file "$SD/settings/Acmecorp-CS-codex-card-interactive.json"

# --- autopilot-test-allow：ring3 測試前綴只比對前綴，設定檔不含連線字串或密碼 ---
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];assert "Bash(TEST_DATABASE_URL=* pnpm vitest:*)" in a and "Bash(TEST_DATABASE_URL=* pnpm test:*)" in a,a' "$S" || fail "autopilot allow 缺 TEST_DATABASE_URL 前綴規則"
python3 -I -c 'import json,sys;a=[r for r in json.load(open(sys.argv[1]))["permissions"]["allow"] if r.startswith("Bash(TEST_DATABASE_URL=")];assert a and all(r.startswith("Bash(TEST_DATABASE_URL=* pnpm ") for r in a),a' "$S" || fail "TEST_DATABASE_URL 規則的值只能是 *"
assert_eq "$(grep -c 'TEST_DATABASE_URL' "$SI")" 0 "interactive 不放行 ring3 測試指令"

# --- orca-autopilot-allow：autopilot 放行 orca 子指令，interactive 不放行 ---
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];assert "Bash(orca:*)" in a,a' "$S" || fail "autopilot allow 缺 Bash(orca:*)"
assert_eq "$(grep -c 'orca' "$SI")" 0 "interactive 不放行 orca"
assert_eq "$(grep -c '://' "$S")" 0 "settings 不含連線字串（任何 scheme://）"

# --- migrate 授權：filter 寫法只在 grants.toml 開 migrate 時出現 ---
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-AI no-grant "$TOP"
assert_eq "$(grep -c 'db:migrate' "$SD/settings/Acmecorp-AI-no-grant-autopilot.json")" 0 "沒有 migrate 授權就沒有 migrate 規則"
printf '[repos.Acmecorp-AI]\nmigrate = true\n' > "$SD/grants.toml"
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-AI with-grant "$TOP"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];assert "Bash(pnpm --filter * run db:migrate:*)" in a and "Bash(pnpm db:migrate:*)" in a,a' "$SD/settings/Acmecorp-AI-with-grant-autopilot.json" || fail "migrate 授權要放行 filter 寫法與原本的 db:migrate"
rm -f "$SD/grants.toml"

echo ok
