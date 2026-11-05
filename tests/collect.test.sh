#!/usr/bin/env bash
# opsx collect：三個來源投影成一份 JSON。驗收：specs/board-collect/spec.md 全部 Scenario（herdr-board 2.2）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_MR_CACHE_TTL=0

q() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d,ensure_ascii=False,sort_keys=True) if isinstance(d,(dict,list,bool)) or d is None else d)' "$2"; }
card() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
c=[c for c in d["cards"] if c["repo"]==sys.argv[1] and c["slug"]==sys.argv[2]]
print(json.dumps(c[0],ensure_ascii=False) if c else "null")' "$2" "$3"; }

ROOT="$FX/code"; mkdir -p "$ROOT/a/openspec/changes/archive" "$ROOT/b/openspec/changes" "$ROOT/c" "$OPSX_STATE_DIR"
mkcard() { # <repo> <slug> [title]
  local d="$ROOT/$1/openspec/changes/$2"; mkdir -p "$d"
  printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$d/.openspec.yaml"
  printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-04\nrelated:\n---\n\n## 一句話\n\n%s\n\n## 證據\n\n- x\n' "${3:-$2 的一句話}" > "$d/inbox.md"
  printf '%s' "$d"
}
# x1：只有 inbox
mkcard a x1 "第一張" >/dev/null
# x2：apply 中、授權 gate 開著
D=$(mkcard a x2); printf '## 1\n\n- [ ] 1.1 a\n  - 驗收：R\n  - 測試：t\n' > "$D/tasks.md"
cat > "$D/gates.md" <<'EOF'
## g1
type: approval
action: push
status: open
問題: 要 push 分支到 gitlab 才能開 MR
建議: 允許
證據: tests 全綠，diff 只有 bin/
風險: 低，分支是自己的
預設: 不 push，先做 1.2
EOF
# x3：決定 gate，三個選項
D=$(mkcard a x3); printf '## 1\n\n- [ ] 1.1 a\n' > "$D/tasks.md"
cat > "$D/gates.md" <<'EOF'
## g2
type: decision
status: open
問題: 快取放哪
選項: 記憶體 | 檔案 (Recommended) | redis
建議: 檔案
證據: 單機
風險: 無
預設: 檔案
EOF
# x4：MR 全綠、已派出
D=$(mkcard a x4); printf '## 1\n\n- [x] 1.1 a\n' > "$D/tasks.md"
printf '{"phase":"pr","step":"5","total":"5","label":"可以合併","tests":"green","at":"2026-11-05T10:00:00+08:00"}' > "$D/status.json"
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/a/-/merge_requests/7\n' > "$D/report.md"
# x5：archive
D="$ROOT/a/openspec/changes/archive/2026-11-01-x5"; mkdir -p "$D"; printf 'schema: opsx\nkind: chore\n' > "$D/.openspec.yaml"; printf '## 一句話\n\n舊的\n' > "$D/inbox.md"
# y1：派出、herdr blocked、沒 gate
D=$(mkcard b y1); printf '## 1\n\n- [ ] 1.1 a\n' > "$D/tasks.md"
# y2：MR pipeline 紅、已派出
D=$(mkcard b y2); printf '## 1\n\n- [x] 1.1 a\n' > "$D/tasks.md"
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/b/-/merge_requests/8\n' > "$D/report.md"

printf '[repos]\n"a" = "develop"\n' > "$OPSX_STATE_DIR/workspaces.toml"
printf '[repos."a"]\npush = true\nmr = false\n' > "$OPSX_STATE_DIR/grants.toml"
cat > "$OPSX_STATE_DIR/dispatch.json" <<'EOF'
{"a/x4":{"workspace":"develop","tab":"t1","pane":"p4","agent":"x4","model":"claude-opus-5-5","mode":"autopilot","kind":"dev","branch":"feat/x4/mikaela","grants":["push"],"started_at":"2026-11-05T09:00:00+08:00"},
 "b/y1":{"workspace":"b","tab":"t2","pane":"p9","agent":"y1","model":"claude-sonnet-5-5","mode":"drive","kind":"dev","branch":"feat/y1/mikaela","grants":[],"started_at":"2026-11-05T09:30:00+08:00"},
 "b/y2":{"workspace":"b","tab":"t3","pane":"p5","agent":"y2","model":"claude-opus-5-5","mode":"interactive","kind":"dev","branch":"feat/y2/mikaela","grants":[],"started_at":"2026-11-05T08:00:00+08:00"}}
EOF
# glab：iid 7 全綠、8 pipeline 紅（fake glab 依 iid 讀不同檔）
export OPSX_TEST_GLAB_JSON="$FX/mr.json" OPSX_TEST_GLAB_JSON_BY_IID="$FX/mr-"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"aaa111","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$FX/mr-7.json"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"bbb222","head_pipeline":{"status":"failed"},"unresolved_discussions_count":0}' > "$FX/mr-8.json"
# herdr：x4 working、y1 blocked、foo 沒對到卡
export OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
printf '[{"name":"x4","pane":"p4","agent_status":"working"},{"name":"y1","pane":"p9","agent_status":"blocked"},{"name":"foo","pane":"p7","agent_status":"idle"}]' > "$OPSX_TEST_HERDR_AGENTS"

# ---------- 在 herdr 內 ----------
export HERDR_ENV=1
J="$(opsx collect --root "$ROOT")"; rc=$?; assert_eq "$rc" 0 "collect rc: $J"

# 範圍：只有 a、b；a 掛 develop，b 沒掛
assert_eq "$(q "$J" scopes)" '[{"repos": ["a"], "workspace": "develop"}, {"repos": ["b"], "workspace": null}]'

# 節點與分段
C="$(card "$J" a x1)"; assert_eq "$(q "$C" stage)" explore; assert_eq "$(q "$C" section)" 待指派; assert_eq "$(q "$C" title)" 第一張
assert_eq "$(q "$C" waiting)" null; assert_eq "$(q "$C" dispatch)" null; assert_eq "$(q "$C" agent_status)" null; assert_eq "$(q "$C" kind)" dev
C="$(card "$J" a x5)"; assert_eq "$(q "$C" stage)" archive; assert_eq "$(q "$C" section)" 已完成

# 等待授權
C="$(card "$J" a x2)"; assert_eq "$(q "$C" section)" 待處理
assert_eq "$(q "$C" waiting.type)" 等待授權; assert_eq "$(q "$C" waiting.gate_id)" g1
assert_eq "$(q "$C" waiting.options)" '["這次", "這張卡", "這個 repo 永遠", "拒絕"]'
assert_eq "$(q "$C" waiting.question)" "要 push 分支到 gitlab 才能開 MR"; assert_eq "$(q "$C" waiting.recommended)" 允許
assert_eq "$(q "$C" waiting.evidence)" "tests 全綠，diff 只有 bin/"; assert_eq "$(q "$C" waiting.risk)" "低，分支是自己的"
assert_eq "$(q "$C" waiting.default_if_unanswered)" "不 push，先做 1.2"; assert_eq "$(q "$C" waiting.action)" push

# 等待決定
C="$(card "$J" a x3)"; assert_eq "$(q "$C" waiting.type)" 等待決定
assert_eq "$(q "$C" waiting.options)" '["記憶體", "檔案", "redis"]'; assert_eq "$(q "$C" waiting.recommended)" 檔案

# 可以合併
C="$(card "$J" a x4)"; assert_eq "$(q "$C" waiting.type)" 可以合併; assert_eq "$(q "$C" section)" 待處理
assert_eq "$(q "$C" mr.conditions)" '{"no_conflicts": true, "not_draft": true, "opened": true, "pipeline": true, "threads": true}'
assert_eq "$(q "$C" mr.head_sha)" aaa111; assert_eq "$(q "$C" dispatch.pane)" p4; assert_eq "$(q "$C" dispatch.mode)" autopilot
assert_eq "$(q "$C" agent_status)" working; assert_eq "$(q "$C" status.phase)" pr; assert_eq "$(q "$C" dispatch.grants)" '["push"]'

# 少一個條件 → 進行中
C="$(card "$J" b y2)"; assert_eq "$(q "$C" waiting)" null; assert_eq "$(q "$C" section)" 進行中
assert_eq "$(q "$C" mr.conditions.pipeline)" false; assert_eq "$(q "$C" mr.blocked_on)" pipeline; assert_eq "$(q "$C" agent_status)" unknown

# 終端機等待輸入
C="$(card "$J" b y1)"; assert_eq "$(q "$C" waiting.type)" 終端機等待輸入
assert_eq "$(q "$C" waiting.options)" '["開啟 pane", "停止", "重新指派"]'; assert_eq "$(q "$C" section)" 待處理

# 沒對到卡的 agent
assert_eq "$(q "$J" unmatched_agents)" '[{"agent_status": "idle", "name": "foo", "pane": "p7"}]'
assert_eq "$(q "$J" errors)" '[]'
# 不寫檔（cache/ 除外）
[ "$(find "$OPSX_STATE_DIR" -type f ! -path '*/cache/*' | wc -l | tr -d ' ')" = 3 ] || fail "collect 不該在 state 寫檔：$(find "$OPSX_STATE_DIR" -type f)"
[ -z "$(find "$ROOT" -newer "$OPSX_STATE_DIR/dispatch.json" -type f)" ] || fail "collect 不該動卡的檔"

# ---------- 不在 herdr 內 ----------
export HERDR_ENV=""
: > "$OPSX_FAKE_LOG"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0
assert_eq "$(q "$(card "$J" a x4)" agent_status)" null
assert_eq "$(q "$J" errors.0.source)" herdr
assert_eq "$(q "$J" unmatched_agents)" '[]'
assert_not_grep '^agent list' "$OPSX_FAKE_LOG"
C="$(card "$J" b y1)"; assert_eq "$(q "$C" waiting)" null "沒 herdr 就判不出 blocked"; assert_eq "$(q "$C" section)" 進行中
echo ok
