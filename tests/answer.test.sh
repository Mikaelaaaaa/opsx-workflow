#!/usr/bin/env bash
# opsx answer：回 gate → gates.md answered、decisions.tsv、grants 落到對的檔、herdr agent prompt。
# 驗收：specs/board-actions/spec.md「回 gate」「三種授權答案落到對的檔」（herdr-board 3.1）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
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
assert_eq "$(tail -1 "$C/decisions.tsv" | cut -f2-5)" $'你\t已決定\t選 檔案\tg2'
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
assert_grep '^# grants' "$OPSX_STATE_DIR/grants.toml"   # 原有的註解留著
awk '/^## g1/{f=1} /^## g2/{f=0} f' "$C/gates.md" | grep -q '^status: answered' || fail "g1 要 answered"
assert_grep '^agent prompt x 允許$' "$OPSX_FAKE_LOG"
assert_eq "$(tail -1 "$C/decisions.tsv" | cut -f2-5)" $'你\t已允許\t允許\tg1 · repo'

# --- 授權：這張卡 ---
gates; printf '# grants\n' > "$OPSX_STATE_DIR/grants.toml"
out="$(opsx answer x --gate g1 --grant card "允許" 2>&1)"; assert_eq "$?" 0 "answer g1 card: $out"
PD="${OPSX_STATE_DIR}-protected"   # 這張卡 / 這次的授權只落受保護位置，dispatch.json 不寫（protected-authorization）
assert_eq "$(jq -c '."Agentory-AI/x".grants' "$PD/authz.json")" '["push"]'
assert_eq "$(jq -c '."Agentory-AI/x".grants' "$OPSX_STATE_DIR/dispatch.json")" '[]' "card 授權不該寫進 dispatch.json"
assert_not_grep 'push' "$OPSX_STATE_DIR/grants.toml"

# --- 授權：這次 → 記進 once（閘門用掉就刪），grants 與 grants.toml 都不動 ---
gates; printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"; rm -rf "$PD"
out="$(opsx answer x --gate g1 --grant this "允許" 2>&1)"; assert_eq "$?" 0 "answer g1 this: $out"
assert_eq "$(jq -c '."Agentory-AI/x".grants' "$OPSX_STATE_DIR/dispatch.json")" '[]'; assert_not_grep 'push' "$OPSX_STATE_DIR/grants.toml"
assert_eq "$(jq -c '."Agentory-AI/x".once' "$PD/authz.json")" '["push"]'
assert_eq "$(jq -r '."Agentory-AI/x" | has("once")' "$OPSX_STATE_DIR/dispatch.json")" false "once 不該寫進 dispatch.json"

# --- 受保護位置寫不進去（沙盒內）：非零退出、訊息含路徑，gates.md / decisions / dispatch.json 都不動，不送 prompt ---
gates; rm -rf "$PD"; mkdir -p "$PD"; chmod 500 "$PD"; : > "$OPSX_FAKE_LOG"
cp "$C/gates.md" "$FX/before.md"; cp "$C/decisions.tsv" "$FX/before.tsv"; cp "$OPSX_STATE_DIR/dispatch.json" "$FX/dispatch.before"
for g in card this; do
  out="$(opsx answer x --gate g1 --grant "$g" "允許" 2>&1)"; [ $? -ne 0 ] || fail "$g：受保護位置唯讀要非零退出"
  echo "$out" | grep -qF "$PD" || fail "$g：訊息要含受保護路徑: $out"
  cmp -s "$C/gates.md" "$FX/before.md" || fail "$g：gates.md 不該變"; cmp -s "$C/decisions.tsv" "$FX/before.tsv" || fail "$g：decisions 不該變"
  cmp -s "$OPSX_STATE_DIR/dispatch.json" "$FX/dispatch.before" || fail "$g：dispatch.json 不該變"
done
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "寫不進去不該送 prompt"
chmod 700 "$PD"

# --- 答案含換行：壓成一行，不能變成新欄位把 gate 重開 ---
gates
out="$(opsx answer x --gate g2 $'選 檔案\nstatus: open\n## g9' 2>&1)"; assert_eq "$?" 0 "answer 多行: $out"
awk '/^## g2/{f=1} /^## g3/{f=0} f' "$C/gates.md" > "$FX/g2.txt"
assert_grep '^answer: 選 檔案 status: open ## g9$' "$FX/g2.txt"; assert_eq "$(grep -c '^status: open' "$FX/g2.txt" || true)" 0 "不該被重開"
assert_eq "$(grep -c '^## g9' "$C/gates.md" || true)" 0 "不該多出假 gate"

# --- action 不合格：不寫壞 TOML ---
gates; sed -i.bak 's/^action: push$/action: git push/' "$C/gates.md"; rm -f "$C/gates.md.bak"
out="$(opsx answer x --gate g1 --grant repo "允許" 2>&1)"; [ $? -ne 0 ] || fail "壞 action 要拒絕"; echo "$out" | grep -q 'git push' || fail "要印出 action: $out"
python3 -I -c 'import tomllib,sys;tomllib.load(open(sys.argv[1],"rb"))' "$OPSX_STATE_DIR/grants.toml" || fail "grants.toml 被寫壞了"

# --- 答案以 -- 開頭：用 -- 隔開 ---
gates
out="$(opsx answer x --gate g2 -- "--no-verify 可以嗎" 2>&1)"; assert_eq "$?" 0 "-- 文字: $out"
assert_grep '^answer: --no-verify 可以嗎$' "$C/gates.md"

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
# --- 代管卡（auto-dispatch）：送給 herdr_name，prompt 帶 [<slug>]；沒有 herdr_name 的舊條目照舊送 slug（上面幾段已驗）---
gates; : > "$OPSX_FAKE_LOG"
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"claude","grants":[],"via":"p","herdr_name":"p"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx answer x --gate g2 "選 B" 2>&1)"; assert_eq "$?" 0 "代管卡 answer: $out"
assert_grep '^agent prompt p \[x\] 選 B$' "$OPSX_FAKE_LOG"
# 單一續接後的卡：herdr_name 就是自己，沒有 via，不加前綴
gates; : > "$OPSX_FAKE_LOG"
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"claude","grants":[],"herdr_name":"x"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx answer x --gate g2 "選 B" 2>&1)"; assert_eq "$?" 0 "續接卡 answer: $out"
assert_grep '^agent prompt x 選 B$' "$OPSX_FAKE_LOG"
# feature session 代管的主 change（opsx dispatch --feature 寫的形狀）：送到 feature 名的 session，前綴 [<主>]
gates; : > "$OPSX_FAKE_LOG"
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"claude","grants":[],"herdr_name":"fs","via":"fs","feature":"fs"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx answer x --gate g2 "選 B" 2>&1)"; assert_eq "$?" 0 "session 代管卡 answer: $out"
assert_grep '^agent prompt fs \[x\] 選 B$' "$OPSX_FAKE_LOG"

# --- 舊寫法的授權 gate 可以 --grant；type 不明不行（gate-type-normalize） ---
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '# grants\n' > "$OPSX_STATE_DIR/grants.toml"; rm -rf "$PD"
printf '## g1\ntype: authorization\naction: push\nstatus: open\n問題: push？\n\n## g2\ntype: approval-ish\naction: push\nstatus: open\n問題: ？\n\n## g3\naction: push\nstatus: open\n問題: 沒寫 type\n\n## g4\ntype: 等待授權\naction: push\nstatus: open\n問題: push？\n' > "$C/gates.md"
cp "$C/gates.md" "$FX/before.md"
out="$(opsx answer x --gate g2 --grant card "允許" 2>&1)"; [ $? -ne 0 ] || fail "表外的 type 不能 --grant"
echo "$out" | grep -q 'approval-ish' || fail "訊息要印原始值：$out"
out="$(opsx answer x --gate g3 --grant card "允許" 2>&1)"; [ $? -ne 0 ] || fail "沒寫 type 不能 --grant"
echo "$out" | grep -q '沒寫 type' || fail "訊息要說沒寫 type：$out"
cmp -s "$C/gates.md" "$FX/before.md" || fail "拒絕時 gates.md 不該變"
assert_no_file "$PD/authz.json"   # 拒絕時不該有授權寫入（受保護位置連檔都不該出現）
out="$(opsx answer x --gate g1 --grant card "允許" 2>&1)"; assert_eq "$?" 0 "authorization 要能授權：$out"
assert_eq "$(jq -c '."Agentory-AI/x".grants' "$PD/authz.json")" '["push"]' "authorization 的授權要落在受保護位置"
rm -rf "$PD"   # g1 的授權已留下 push，不清掉的話下面的斷言就算 g4 什麼都沒寫也會過
out="$(opsx answer x --gate g4 --grant card "允許" 2>&1)"; assert_eq "$?" 0 "等待授權 要能授權：$out"
assert_eq "$(jq -c '."Agentory-AI/x".grants' "$PD/authz.json")" '["push"]' "等待授權 的授權要自己落在受保護位置"
awk '/^## g4/{f=1} f' "$C/gates.md" | grep -q '^status: answered' || fail "g4 要 answered"

# --- 子 change：--sub 回 subs/<子>/gates.md，decisions 記子殼，主 change 的檔不動（board-tree answer-sub）---
mk_change "$R" bt; B="$R/openspec/changes/bt"; S="$B/subs/as"; mkdir -p "$S"
printf '## g1\ntype: decision\nstatus: open\n問題: 主的\n' > "$B/gates.md"; cp "$B/gates.md" "$FX/main-before.md"
subgates() { printf '## g1\ntype: decision\nstatus: open\n問題: 選哪個\n\n## g2\ntype: approval\naction: push\nstatus: open\n問題: 要 push\n' > "$S/gates.md"; }
subgates; printf '{}' > "$OPSX_STATE_DIR/dispatch.json"; : > "$OPSX_FAKE_LOG"
out="$(opsx answer bt --sub as --gate g1 第一項 2>&1)"; assert_eq "$?" 0 "answer --sub: $out"
awk '/^## g1/{f=1} /^## g2/{f=0} f' "$S/gates.md" > "$FX/sg1.txt"
assert_grep '^status: answered' "$FX/sg1.txt"; assert_grep '^answer: 第一項$' "$FX/sg1.txt"
assert_eq "$(tail -1 "$S/decisions.tsv" | cut -f2-5)" $'你\t已決定\t第一項\tg1'
cmp -s "$B/gates.md" "$FX/main-before.md" || fail "主 change 的 gates.md 不該變"; assert_no_file "$B/decisions.tsv"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "主 change 沒派出就不 prompt"

# 子殼不存在：退出非 0，訊息含 subs/nope，什麼都不動
cp "$S/gates.md" "$FX/sub-before.md"; cp "$S/decisions.tsv" "$FX/sub-before.tsv"; cp "$OPSX_STATE_DIR/dispatch.json" "$FX/disp-before.json"
out="$(opsx answer bt --sub nope --gate g1 ok 2>&1)"; [ $? -ne 0 ] || fail "子殼不存在要退出非零"
echo "$out" | grep -q 'subs/nope' || fail "訊息要含 subs/nope: $out"
assert_no_file "$B/subs/nope"; assert_no_file "$B/decisions.tsv"
cmp -s "$B/gates.md" "$FX/main-before.md" || fail "主 gates.md 不該變"
cmp -s "$S/gates.md" "$FX/sub-before.md" || fail "子 gates.md 不該變"; cmp -s "$S/decisions.tsv" "$FX/sub-before.tsv" || fail "子 decisions 不該變"
cmp -s "$OPSX_STATE_DIR/dispatch.json" "$FX/disp-before.json" || fail "dispatch.json 不該變"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "不該碰 herdr"

# 主 change 有派出：送給主的 herdr_name，前綴一律 [主/子]，有沒有 via 都一樣
subgates; : > "$OPSX_FAKE_LOG"
printf '{"Agentory-AI/bt":{"mode":"autopilot","pane":"p5","agent":"claude","grants":[],"herdr_name":"fb"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx answer bt --sub as --gate g1 選 A 2>&1)"; assert_eq "$?" 0 "sub 派出: $out"
assert_grep '^agent prompt fb \[bt/as\] 選 A$' "$OPSX_FAKE_LOG"
subgates; : > "$OPSX_FAKE_LOG"
printf '{"Agentory-AI/bt":{"mode":"autopilot","pane":"p5","agent":"claude","grants":[],"via":"p","herdr_name":"p"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx answer bt --sub as --gate g1 選 A 2>&1)"; assert_eq "$?" 0 "sub 代管: $out"
assert_grep '^agent prompt p \[bt/as\] 選 A$' "$OPSX_FAKE_LOG"

# 卡級 / 這次的授權記在主 change 的條目（受保護位置）；子 change 沒有自己的條目，dispatch.json 不寫授權
chmod -R u+w "$PD" 2>/dev/null; rm -rf "$PD"
subgates; printf '{"Agentory-AI/bt":{"mode":"autopilot","pane":"p5","agent":"claude","grants":[],"herdr_name":"fb"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx answer bt --sub as --gate g2 --grant card 允許 2>&1)"; assert_eq "$?" 0 "sub card: $out"
assert_eq "$(jq -c '."Agentory-AI/bt".grants' "$PD/authz.json")" '["push"]'
assert_eq "$(jq -c '."Agentory-AI/bt".once // []' "$PD/authz.json")" '[]' "card 不該寫進 once"
assert_eq "$(jq -c '."Agentory-AI/bt".grants' "$OPSX_STATE_DIR/dispatch.json")" '[]' "card 授權不該寫進 dispatch.json"
assert_eq "$(tail -1 "$S/decisions.tsv" | cut -f2-5)" $'你\t已允許\t允許\tg2 · card'
subgates; rm -rf "$PD"
out="$(opsx answer bt --sub as --gate g2 --grant this 允許 2>&1)"; assert_eq "$?" 0 "sub this: $out"
assert_eq "$(jq -c '."Agentory-AI/bt".once' "$PD/authz.json")" '["push"]'
assert_eq "$(jq -c '."Agentory-AI/bt".grants // []' "$PD/authz.json")" '[]' "這次不該變成卡級授權"
assert_eq "$(jq -c 'keys' "$PD/authz.json")" '["Agentory-AI/bt"]' "子 change 沒有自己的授權條目"
assert_eq "$(jq -c 'keys' "$OPSX_STATE_DIR/dispatch.json")" '["Agentory-AI/bt"]' "子 change 不進 dispatch.json"
assert_no_file "$B/decisions.tsv"
echo ok
