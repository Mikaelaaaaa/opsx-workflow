#!/usr/bin/env bash
# bin/lib/claude-trust.py：讀 Claude Code 的信任紀錄（projects[<path>].hasTrustDialogAccepted），只讀不寫。
# 對應 init-sandbox-perms 的 specs/opsx-init「資料夾信任」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

H="$OPSX_ROOT/bin/lib/claude-trust.py"
mkdir -p "$FX/cfg" "$FX/home"
cat > "$FX/cfg/.claude.json" <<'JSON'
{"projects": {"/a": {"hasTrustDialogAccepted": true}, "/b": {"hasTrustDialogAccepted": false}, "/c": {}}}
JSON
before="$(cat "$FX/cfg/.claude.json")"

# CLAUDE_CONFIG_DIR 設了：讀它底下的 .claude.json
assert_eq "$(CLAUDE_CONFIG_DIR="$FX/cfg" python3 -I "$H" /a)" "trusted /a"
assert_eq "$(CLAUDE_CONFIG_DIR="$FX/cfg" python3 -I "$H" /b)" "untrusted /b"
assert_eq "$(CLAUDE_CONFIG_DIR="$FX/cfg" python3 -I "$H" /c)" "untrusted /c" "有項目但沒按過"
assert_eq "$(CLAUDE_CONFIG_DIR="$FX/cfg" python3 -I "$H" /nope)" "untrusted /nope" "沒有項目"
# 只信任父目錄不算：/a/sub 不繼承 /a
assert_eq "$(CLAUDE_CONFIG_DIR="$FX/cfg" python3 -I "$H" /a/sub)" "untrusted /a/sub"

# 沒設（或設成空字串）：讀 $HOME/.claude.json；檔案不存在 = 從沒信任過任何資料夾
assert_eq "$(HOME="$FX/home" CLAUDE_CONFIG_DIR= python3 -I "$H" /a)" "untrusted /a"
cp "$FX/cfg/.claude.json" "$FX/home/.claude.json"
assert_eq "$(HOME="$FX/home" CLAUDE_CONFIG_DIR= python3 -I "$H" /a)" "trusted /a"

# 只讀：檔案沒被改
assert_eq "$(cat "$FX/cfg/.claude.json")" "$before" "信任紀錄被改了"

# 壞 JSON：失敗，訊息含檔名；不當成沒信任
printf '{"projects": ' > "$FX/cfg/.claude.json"
out="$(CLAUDE_CONFIG_DIR="$FX/cfg" python3 -I "$H" /a 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "壞 JSON 要失敗"
case "$out" in *"$FX/cfg/.claude.json"*) ;; *) fail "訊息要含檔名：$out" ;; esac
