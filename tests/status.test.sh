#!/usr/bin/env bash
# opsx status：寫 changes/<slug>/status.json。對應要求檔 §3.6 新增的儲存 6。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo Agentory-AI)"; mk_change "$R" eval-core; cd "$R"
S="$R/openspec/changes/eval-core/status.json"

# --- 正常：從 branch 推 slug ---
opsx status apply 4/8 "實作 + self-check" || fail "status rc"
assert_file "$S"
python3 -I - "$S" <<'PY' || fail "status.json shape"
import json,sys,re
d=json.load(open(sys.argv[1]))
assert d["phase"]=="apply" and d["step"]==4 and d["total"]==8, d
assert d["label"]=="實作 + self-check", d
assert d["tests"]=="unknown", d
assert re.match(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$", d["at"]), d["at"]
PY

# --- tests 旗標：寫了就留，下一次沒給要保留 ---
opsx status apply 8/8 "測試 agent" --tests green || fail "tests flag"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["tests"]=="green",d' "$S"
opsx status review 1/7 "diff" || fail "status 2"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["tests"]=="green" and d["phase"]=="review",d' "$S"

# --- --change 指定 slug（不在卡的 branch 上也能寫）---
mkdir -p "$R/openspec/changes/other"; printf 'schema: opsx\n' > "$R/openspec/changes/other/.openspec.yaml"
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" checkout -q main
opsx status explore 1/8 "讀 inbox" --change other || fail "--change"
assert_file "$R/openspec/changes/other/status.json"

# --- 邊界：branch 對不到卡、也沒 --change → rc 2，不亂寫 ---
assert_rc 2 opsx status apply 1/8 x
assert_no_file "$R/openspec/changes/main"

# --- 邊界：phase 不在清單、step 格式錯、step > total、指定的卡不存在 → rc 2 ---
git -C "$R" checkout -q feat/eval-core/mikaela
assert_rc 2 opsx status deploy 1/8 x
assert_rc 2 opsx status apply 4 x
assert_rc 2 opsx status apply 9/8 x
assert_rc 2 opsx status apply 1/8 x --tests maybe
assert_rc 2 opsx status apply 1/8 x --change nope

# --- --show 印目前的，沒有檔印 none ---
out="$(opsx status --show)"; echo "$out" | grep -q "review 1/7" || fail "show: $out"
rm "$S"; out="$(opsx status --show)"; assert_eq "$out" "none"

# --- worker：一般分支是 session ---
opsx status apply 1/3 x || fail "worker session"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["worker"]=="session",d' "$S"

# --- 子殼分支 <主>--<子>：寫子殼的 status.json，worker 是 subagent-<子>，主殼不動 ---
mkdir -p "$R/openspec/changes/eval-core/subs/s1"
cp "$S" "$S.before"
git -C "$R" checkout -q -b feat/eval-core--s1/mikaela
opsx status apply 1/3 "子" || fail "子殼分支 rc"
SS="$R/openspec/changes/eval-core/subs/s1/status.json"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["worker"]=="subagent-s1" and d["label"]=="子",d' "$SS"
diff -q "$S" "$S.before" >/dev/null || fail "子殼分支不該動主殼 status.json"

# --- 子殼不存在：rc 2，訊息含它要找的路徑 ---
git -C "$R" checkout -q -b feat/eval-core--nope/mikaela
out="$(opsx status apply 1/3 x 2>&1)"; rc=$?
assert_eq "$rc" 2 "子殼不存在 rc"
echo "$out" | grep -q 'openspec/changes/eval-core/subs/nope' || fail "子殼不存在的訊息: $out"

# --- --sub / --worker：session 在主 change 分支上替子殼寫 ---
git -C "$R" checkout -q feat/eval-core/mikaela
rm "$SS"
opsx status apply 2/3 y --sub s1 --worker subagent-s1 || fail "--sub rc"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["worker"]=="subagent-s1" and d["step"]==2,d' "$SS"
opsx status apply 3/3 z --sub s1 || fail "--sub 無 --worker"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["worker"]=="session",d' "$SS"
assert_rc 2 opsx status apply 1/3 x --sub nope
echo ok
