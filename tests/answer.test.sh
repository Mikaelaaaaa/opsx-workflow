#!/usr/bin/env bash
# opsx answer：回 gate → gates.md answered、decisions.tsv、grants 落到對的檔、herdr agent prompt。
# 驗收：specs/board-actions/spec.md「回 gate」「三種授權答案落到對的檔」（herdr-board 3.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"

R="$(mk_repo Agentory-AI)"; C="$R/openspec/changes/x"; mk_change "$R" x; mkdir -p "$OPSX_STATE_DIR"
gates() { cat > "$C/gates.md" <<'EOF'
## g1
type: approval
action: push
status: open
問題: 要 push 分支
建議: 允許
證據: 綠
風險: 低
預設: 不 push

## g2
type: decision
status: open
問題: 快取放哪
選項: 記憶體 | 檔案 (Recommended) | redis
建議: 檔案

## g3
type: approval
action: merge
status: open
問題: 合併
EOF
}
gates
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '# grants\n' > "$OPSX_STATE_DIR/grants.toml"
cd "$R"

# --- 決定類 ---
out="$(opsx answer x --gate g2 "選 檔案" 2>&1)"; assert_eq "$?" 0 "answer g2: $out"
awk '/^## g2/{f=1} /^## g3/{f=0} f' "$C/gates.md" > "$FX/g2.txt"
assert_grep '^status: answered' "$FX/g2.txt"; assert_grep '^answer: 選 檔案' "$FX/g2.txt"; assert_grep '^answered_at: 20' "$FX/g2.txt"
awk '/^## g1/{f=1} /^## g2/{f=0} f' "$C/gates.md" | grep -q '^status: open' || fail "g1 不該被動到"
assert_grep $'\tyou\tanswer\tg2\t選 檔案' "$C/decisions.tsv"
assert_grep '^agent prompt x 選 檔案$' "$OPSX_FAKE_LOG"

# --- 不存在的 gate：退出非零，什麼都不動 ---
cp "$C/gates.md" "$FX/before.md"; cp "$C/decisions.tsv" "$FX/before.tsv"; : > "$OPSX_FAKE_LOG"
out="$(opsx answer x --gate g9 "x" 2>&1)"; rc=$?; [ $rc -ne 0 ] || fail "g9 要退出非零"
echo "$out" | grep -q g9 || fail "訊息要含 g9: $out"
cmp -s "$C/gates.md" "$FX/before.md" || fail "gates.md 不該變"; cmp -s "$C/decisions.tsv" "$FX/before.tsv" || fail "decisions 不該變"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "不該碰 herdr"

# --- 已回過的 gate 也拒絕 ---
out="$(opsx answer x --gate g2 "再答一次" 2>&1)"; [ $? -ne 0 ] || fail "answered 的 gate 要拒絕"

# --- 授權：這個 repo 永遠 ---
: > "$OPSX_FAKE_LOG"
out="$(opsx answer x --gate g1 --grant repo "允許" 2>&1)"; assert_eq "$?" 0 "answer g1 repo: $out"
python3 -I -c 'import tomllib,sys;g=tomllib.load(open(sys.argv[1],"rb"));assert g["repos"]["Agentory-AI"]["push"] is True, g' "$OPSX_STATE_DIR/grants.toml" || fail "grants.toml 要有 push = true：$(cat "$OPSX_STATE_DIR/grants.toml")"
assert_eq "$(jq -c '."Agentory-AI/x".grants' "$OPSX_STATE_DIR/dispatch.json")" '[]' "repo 永遠不該寫進 dispatch.json"
awk '/^## g1/{f=1} /^## g2/{f=0} f' "$C/gates.md" | grep -q '^status: answered' || fail "g1 要 answered"
assert_grep '^agent prompt x 允許$' "$OPSX_FAKE_LOG"
assert_grep $'\tyou\tanswer\tg1\t允許（grant: repo）' "$C/decisions.tsv"

# --- 授權：這張卡 ---
gates; printf '# grants\n' > "$OPSX_STATE_DIR/grants.toml"
out="$(opsx answer x --gate g1 --grant card "允許" 2>&1)"; assert_eq "$?" 0 "answer g1 card: $out"
assert_eq "$(jq -c '."Agentory-AI/x".grants' "$OPSX_STATE_DIR/dispatch.json")" '["push"]'
assert_not_grep 'push' "$OPSX_STATE_DIR/grants.toml"

# --- 授權：這次 → 兩邊都不記 ---
gates; printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx answer x --gate g1 --grant this "允許" 2>&1)"; assert_eq "$?" 0 "answer g1 this: $out"
assert_eq "$(jq -c '."Agentory-AI/x".grants' "$OPSX_STATE_DIR/dispatch.json")" '[]'; assert_not_grep 'push' "$OPSX_STATE_DIR/grants.toml"

# --- merge 不可永久授權 ---
cp "$C/gates.md" "$FX/before.md"
out="$(opsx answer x --gate g3 --grant repo "允許" 2>&1)"; [ $? -ne 0 ] || fail "merge + repo 要拒絕"
cmp -s "$C/gates.md" "$FX/before.md" || fail "拒絕時 gates.md 不該變"; assert_not_grep 'merge' "$OPSX_STATE_DIR/grants.toml"

# --- --grant 用在決定類 gate 上：拒絕 ---
gates
out="$(opsx answer x --gate g2 --grant repo "檔案" 2>&1)"; [ $? -ne 0 ] || fail "decision gate 不吃 --grant"

# --- 沒派出的卡：gates / decisions 照寫，不打 herdr ---
gates; printf '{}' > "$OPSX_STATE_DIR/dispatch.json"; : > "$OPSX_FAKE_LOG"
out="$(opsx answer x --gate g2 "檔案" 2>&1)"; assert_eq "$?" 0 "沒派出: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "沒 agent 就不 prompt"; echo "$out" | grep -q '沒派出' || fail "要說沒派出: $out"
echo ok
