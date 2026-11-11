#!/usr/bin/env bash
# bin/lib/claude-settings.py：把標準設定（templates/settings.opsx.json 那種）與 repo 路徑合併進使用者層 settings。
# 對應 init-sandbox-perms 的 specs/opsx-init「合併既有 settings」「settings 不合法時拒絕寫入」「標準設定」「--check」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

H="$OPSX_ROOT/bin/lib/claude-settings.py"
S="$FX/cfg/settings.json"
T="$FX/tpl.json"
mkdir -p "$FX/cfg"
cat > "$T" <<'JSON'
{
  "permissions": {"allow": ["Bash(opsx status *)"], "additionalDirectories": ["${OPSX_STATE_DIR}"]},
  "sandbox": {"network": {"allowUnixSockets": ["${HOME}/herdr.sock"]}, "excludedCommands": ["gh pr *", "gh issue comment *"]}
}
JSON
# 範本裡的 ${HOME}、${OPSX_STATE_DIR} 由環境變數展開
run() { HOME=/h OPSX_STATE_DIR=/x/state python3 -I "$H" "$@"; }

# 取 JSON 裡某個路徑的值（點分隔），印成 JSON；不存在印 MISSING
jget() { python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    if not isinstance(d, dict) or k not in d:
        print("MISSING"); sys.exit(0)
    d = d[k]
print(json.dumps(d))' "$1" "$2"; }

# --- 缺檔：從範本建立（變數展開），再加 --add-dir；不備份 ---
out="$(run --file "$S" --template "$T" --add-dir /y/repo 2>&1)"; rc=$?
assert_eq "$rc" 0 "create rc: $out"
assert_file "$S"
assert_eq "$(jget "$S" permissions.additionalDirectories)" '["/x/state", "/y/repo"]'
assert_eq "$(jget "$S" permissions.allow)" '["Bash(opsx status *)"]'
assert_eq "$(jget "$S" sandbox.network.allowUnixSockets)" '["/h/herdr.sock"]'
assert_eq "$(jget "$S" sandbox.excludedCommands)" '["gh pr *", "gh issue comment *"]'
assert_eq "$(jget "$S" sandbox.enabled)" MISSING "不替使用者開關沙盒"
assert_eq "$(jget "$S" sandbox.allowUnsandboxedCommands)" MISSING
assert_no_file "$S.opsx-bak"

# --- 重跑：no-op，檔案與備份都不動 ---
before="$(cat "$S")"
out="$(run --file "$S" --template "$T" --add-dir /y/repo 2>&1)"; rc=$?
assert_eq "$rc" 0 "rerun rc: $out"
assert_eq "$(cat "$S")" "$before" "rerun changed settings"
assert_no_file "$S.opsx-bak"
case "$out" in *unchanged*) ;; *) fail "rerun 輸出應含 unchanged：$out" ;; esac

# --- 缺檔而且沒有東西要加：不建檔 ---
run --file "$FX/cfg/none.json" || fail "no-args rc"
assert_no_file "$FX/cfg/none.json"

# --- 既有設定：其他鍵與元素原樣保留，新項目追加，備份是原內容 ---
cat > "$S" <<'JSON'
{
  "permissions": {"allow": ["Bash(git log *)"], "defaultMode": "auto"},
  "sandbox": {"enabled": true, "network": {"allowLocalBinding": true, "allowUnixSockets": ["/other.sock"]}},
  "theme": "dark"
}
JSON
orig="$(cat "$S")"
run --file "$S" --template "$T" >/dev/null || fail "merge rc"
assert_eq "$(jget "$S" permissions.allow)" '["Bash(git log *)", "Bash(opsx status *)"]'
assert_eq "$(jget "$S" permissions.defaultMode)" '"auto"'
assert_eq "$(jget "$S" theme)" '"dark"'
assert_eq "$(jget "$S" sandbox.enabled)" true
assert_eq "$(jget "$S" sandbox.network.allowLocalBinding)" true
assert_eq "$(jget "$S" sandbox.network.allowUnixSockets)" '["/other.sock", "/h/herdr.sock"]'
assert_eq "$(jget "$S" permissions.additionalDirectories)" '["/x/state"]'
assert_eq "$(cat "$S.opsx-bak")" "$orig" "備份應是跑之前的原內容"

# --- 已有備份：不覆蓋 ---
printf 'sentinel' > "$S.opsx-bak"
run --file "$S" --add-dir /y/repo >/dev/null || fail "second merge rc"
assert_eq "$(cat "$S.opsx-bak")" sentinel "備份被覆蓋"
assert_eq "$(jget "$S" permissions.additionalDirectories)" '["/x/state", "/y/repo"]'

# --- --check：只比對不寫；缺什麼印什麼，全齊 exit 0 ---
before="$(cat "$S")"
run --file "$S" --template "$T" --add-dir /y/repo --check >/dev/null || fail "全齊時 --check 要 exit 0"
out="$(run --file "$S" --template "$T" --add-dir /z/other --check 2>&1)"; rc=$?
assert_eq "$rc" 3 "缺項時 --check 要 exit 3：$out"
case "$out" in *permissions.additionalDirectories*/z/other*) ;; *) fail "要印缺哪一項：$out" ;; esac
assert_eq "$(cat "$S")" "$before" "--check 改了檔"
out="$(run --file "$FX/cfg/absent.json" --template "$T" --check 2>&1)"; rc=$?
assert_eq "$rc" 3 "檔案不存在時 --check 要 exit 3：$out"
assert_no_file "$FX/cfg/absent.json"

# --- 寫入路徑：settings.json 是 symlink（dotfiles）且權限 0600 → 連結還在、真檔更新、權限不變、不留暫存檔 ---
mkdir -p "$FX/dot" "$FX/linkcfg"
printf '{"env":{"TOKEN":"x"}}' > "$FX/dot/settings.json"; chmod 600 "$FX/dot/settings.json"
ln -s "$FX/dot/settings.json" "$FX/linkcfg/settings.json"
run --file "$FX/linkcfg/settings.json" --add-dir /y/repo >/dev/null || fail "symlink merge rc"
[ -L "$FX/linkcfg/settings.json" ] || fail "symlink 被換成一般檔"
assert_eq "$(jget "$FX/dot/settings.json" permissions.additionalDirectories)" '["/y/repo"]' "真檔沒更新"
assert_eq "$(jget "$FX/dot/settings.json" env.TOKEN)" '"x"'
assert_eq "$(python3 -I -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$FX/dot/settings.json")" 0o600 "權限被改了"
assert_eq "$(ls -A "$FX/dot" | grep -c 'tmp$' || true)" 0 "留下暫存檔"

# --- 並行：12 個 helper 同時各加一個路徑，全部都在、不留暫存檔 ---
mkdir -p "$FX/par"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do run --file "$FX/par/settings.json" --add-dir "/p/$i" >/dev/null 2>&1 & done
wait
assert_eq "$(jget "$FX/par/settings.json" permissions.additionalDirectories | python3 -I -c 'import json,sys; print(len(set(json.load(sys.stdin))))')" 12 "並行寫入丟了項目"
assert_eq "$(ls -A "$FX/par" | grep -c 'tmp$' || true)" 0 "並行後留下暫存檔"

# --- --render：把範本的 ${NAME} 展開後整份印出（給單一 session 用 --settings 帶的檔），不需要 --file、不寫任何檔 ---
printf '%s' "$(run --render --template "$T")" > "$FX/rendered.json"
assert_eq "$(jget "$FX/rendered.json" sandbox.network.allowUnixSockets)" '["/h/herdr.sock"]'
assert_eq "$(jget "$FX/rendered.json" permissions.additionalDirectories)" '["/x/state"]'
printf '{"permissions": {"additionalDirectories": ["${NO_SUCH_VAR}/x"]}}' > "$FX/bad1.json"
out="$(run --render --template "$FX/bad1.json" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "--render 遇到未定義變數也要失敗"

# --- 壞 JSON：非 0、訊息含檔名、位元組不變、不備份 ---
rm -f "$S.opsx-bak"
printf '{"sandbox": ' > "$S"
before="$(cat "$S")"
out="$(run --file "$S" --add-dir /x 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "壞 JSON 應該失敗"
case "$out" in *"$S"*) ;; *) fail "訊息要含檔名：$out" ;; esac
assert_eq "$(cat "$S")" "$before" "壞 JSON 被改了"
assert_no_file "$S.opsx-bak"

# --- 型別不符：訊息含鍵路徑，檔案不變 ---
printf '{"sandbox": {"network": {"allowUnixSockets": "oops"}}}' > "$S"
before="$(cat "$S")"
out="$(run --file "$S" --template "$T" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "型別不符應該失敗"
case "$out" in *sandbox.network.allowUnixSockets*) ;; *) fail "訊息要含鍵路徑：$out" ;; esac
assert_eq "$(cat "$S")" "$before" "型別不符時檔案被改了"
assert_no_file "$S.opsx-bak"

printf '{"sandbox": []}' > "$S"
out="$(run --file "$S" --template "$T" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "sandbox 不是物件應該失敗"
case "$out" in *'sandbox'*) ;; *) fail "訊息要含 sandbox：$out" ;; esac

# --- 範本不合法：變數沒定義、葉節點不是字串陣列 → 失敗，訊息點名 ---
printf '{"permissions": {"additionalDirectories": ["${NO_SUCH_VAR}/x"]}}' > "$FX/bad1.json"
out="$(run --file "$FX/cfg/new.json" --template "$FX/bad1.json" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "未定義變數應該失敗"
case "$out" in *NO_SUCH_VAR*) ;; *) fail "訊息要點名變數：$out" ;; esac
assert_no_file "$FX/cfg/new.json"
printf '{"sandbox": {"enabled": true}}' > "$FX/bad2.json"
out="$(run --file "$FX/cfg/new.json" --template "$FX/bad2.json" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "範本葉節點不是陣列應該失敗"
case "$out" in *sandbox.enabled*) ;; *) fail "訊息要點名鍵路徑：$out" ;; esac
