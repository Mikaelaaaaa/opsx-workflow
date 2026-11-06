#!/usr/bin/env bash
# opsx collect：三個來源投影成一份 JSON。驗收：specs/board-collect/spec.md 全部 Scenario（herdr-board 2.2）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_MR_CACHE_TTL=0

q() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d,ensure_ascii=False,sort_keys=True) if isinstance(d,(dict,list,bool)) or d is None else d)' "$2"; }
card() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
c=[c for c in d["cards"] if c["repo"]==sys.argv[1] and c["slug"]==sys.argv[2]]
print(json.dumps(c[0],ensure_ascii=False) if c else "null")' "$2" "$3"; }

ROOT="$FX/code"; mkdir -p "$ROOT/a/openspec/changes/archive" "$ROOT/b/openspec/changes" "$ROOT/c" "$ROOT/a-wt/openspec/changes/x9" "$OPSX_STATE_DIR"
mkdir -p "$ROOT/a/.git" "$ROOT/b/.git"; printf 'gitdir: %s/a/.git/worktrees/x9\n' "$ROOT" > "$ROOT/a-wt/.git"   # a-wt 是 linked worktree，不是 repo
printf 'schema: opsx\n' > "$ROOT/a-wt/openspec/changes/x9/.openspec.yaml"; printf '## 一句話\n\nworktree 的\n' > "$ROOT/a-wt/openspec/changes/x9/inbox.md"
# 舊 schema 的 change（spec-driven，沒 inbox.md）：只計數不當卡
mkdir -p "$ROOT/a/openspec/changes/old-1" "$ROOT/a/openspec/changes/old-2"
for o in old-1 old-2; do printf 'schema: spec-driven\n' > "$ROOT/a/openspec/changes/$o/.openspec.yaml"; printf '## 1\n\n- [ ] 1.1 a\n' > "$ROOT/a/openspec/changes/$o/tasks.md"; done
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
# x5：archive；另外塞 3 張更舊的，cap 設 2 時只留最新 2 張
D="$ROOT/a/openspec/changes/archive/2026-11-01-x5"; mkdir -p "$D"; printf 'schema: opsx\nkind: chore\n' > "$D/.openspec.yaml"; printf '## 一句話\n\n舊的\n' > "$D/inbox.md"
for i in 1 2 3; do D2="$ROOT/a/openspec/changes/archive/2026-10-0$i-old$i"; mkdir -p "$D2"; printf 'schema: opsx\n' > "$D2/.openspec.yaml"; touch -t "2026100${i}0000" "$D2"; done; touch "$D"
# x6：已經 answered 的 gate 不算待處理；x7：action=merge 的 approval gate 沒有「這個 repo 永遠」
D=$(mkcard a x6); printf '## 1\n\n- [ ] 1.1 a\n' > "$D/tasks.md"; printf '## g1\ntype: approval\naction: push\nstatus: answered\nanswer: 允許\n' > "$D/gates.md"
D=$(mkcard a x7); printf '## 1\n\n- [ ] 1.1 a\n' > "$D/tasks.md"; printf '## g1\ntype: approval\naction: merge\nstatus: open\n問題: 合併？\n' > "$D/gates.md"
# x10：兩個 open gate（一個有 opened_at）、一個 answered
D=$(mkcard a x10); printf '## 1\n\n- [ ] 1.1 a\n' > "$D/tasks.md"
printf '## g1\ntype: approval\naction: push\nstatus: open\nopened_at: 2026-11-06T10:00:00+08:00\n問題: push？\n\n## g2\ntype: decision\nstatus: open\n問題: 哪個？\n\n## g3\ntype: decision\nstatus: answered\nopened_at: 2026-11-06T09:00:00+08:00\nanswer: A\n' > "$D/gates.md"
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
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"aaa111","head_pipeline":{"status":"success"},"unresolved_discussions_count":0,"created_at":"2026-11-05T01:10:00.000Z","merged_at":null}' > "$FX/mr-7.json"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"bbb222","head_pipeline":{"status":"failed"},"unresolved_discussions_count":0}' > "$FX/mr-8.json"
# herdr：x4 working、y1 blocked、foo 沒對到卡
export OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
# 真格式（tests/fakes/herdr-samples/agent-list.json）：result.agents[].pane_id，沒有 agent 名字
printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","pane_id":"p4","tab_id":"t1","workspace_id":"develop","agent_status":"working","cwd":"/x","terminal_title_stripped":"x4"},{"agent":"claude","pane_id":"p9","agent_status":"blocked","cwd":"/y","terminal_title_stripped":"y1"},{"agent":"claude","pane_id":"p7","workspace_id":"w9","agent_status":"idle","cwd":"/Users/me","terminal_title_stripped":"foo"}],"type":"agent_list"}}' > "$OPSX_TEST_HERDR_AGENTS"

# ---------- 在 herdr 內 ----------
export HERDR_ENV=1
J="$(opsx collect --root "$ROOT")"; rc=$?; assert_eq "$rc" 0 "collect rc: $J"

# gate 與 MR 的時間（specs/board-collect「gate 與 MR 的時間」）
assert_eq "$(q "$(card "$J" a x10)" open_gates)" '[{"id": "g1", "opened_at": "2026-11-06T10:00:00+08:00"}, {"id": "g2", "opened_at": null}]'
assert_eq "$(q "$(card "$J" a x1)" open_gates)" '[]'
assert_eq "$(q "$(card "$J" a x4)" mr.created_at)" "2026-11-05T01:10:00.000Z"
assert_eq "$(q "$(card "$J" a x4)" mr.merged_at)" null

# 範圍：只有 a、b；a 掛 develop，b 沒掛；a-wt 是 worktree 不算 repo；舊 schema 只計數
assert_eq "$(q "$J" scopes)" '[{"repos": ["a"], "workspace": "develop"}, {"repos": ["b"], "workspace": null}]'
assert_eq "$(q "$J" worktrees_skipped)" '["a-wt"]'; assert_eq "$(card "$J" a-wt x9)" null
assert_eq "$(q "$J" legacy)" '{"a": 2}'; assert_eq "$(card "$J" a old-1)" null
# archive cap：預設 30 全在；設 2 只留最新的 x5 與 old3
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(sum(1 for c in json.load(sys.stdin)["cards"] if c["section"]=="已完成"))')" 4
J3="$(OPSX_COLLECT_ARCHIVE_CAP=2 opsx collect --root "$ROOT")"
assert_eq "$(printf '%s' "$J3" | python3 -I -c 'import json,sys;print(sorted(c["slug"] for c in json.load(sys.stdin)["cards"] if c["section"]=="已完成"))')" "['old3', 'x5']"
# answered 的 gate 不是待處理；merge gate 的選項沒有「這個 repo 永遠」
C="$(card "$J" a x6)"; assert_eq "$(q "$C" waiting)" null; assert_eq "$(q "$C" section)" 待指派
C="$(card "$J" a x7)"; assert_eq "$(q "$C" waiting.options)" '["這次", "這張卡", "拒絕"]'

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
assert_eq "$(q "$J" unmatched_agents)" '[{"agent_status": "idle", "cwd": "/Users/me", "name": "foo", "pane": "p7", "workspace": "w9"}]'
# 真樣本也讀得懂（兩個 agent 都沒對到卡）
J2="$(OPSX_TEST_HERDR_AGENTS= opsx collect --root "$ROOT")"; assert_eq "$(q "$J2" unmatched_agents.0.pane)" "w1:p2"; assert_eq "$(q "$J2" unmatched_agents.1.name)" "Worktree cleanup"
assert_eq "$(q "$J" errors)" '[]'
# 不寫檔（cache/ 與 fixture 的 python 除外）
[ "$(find "$OPSX_STATE_DIR" -type f ! -path '*/cache/*' ! -name '*.lock' ! -name python | wc -l | tr -d ' ')" = 3 ] || fail "collect 不該在 state 寫檔：$(find "$OPSX_STATE_DIR" -type f)"
[ -z "$(find "$ROOT" -newer "$OPSX_STATE_DIR/dispatch.json" -type f)" ] || fail "collect 不該動卡的檔"

# ---------- glab 讀不到：卡還在、errors 記 glab、exit 0 ----------
printf '' > "$FX/mr-7.json"
J4="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0
assert_eq "$(q "$(card "$J4" a x4)" mr.state)" none; assert_eq "$(q "$(card "$J4" a x4)" section)" 進行中
assert_eq "$(q "$J4" errors.0.source)" glab; q "$J4" errors.0.message | grep -q 'a/x4' || fail "glab error 要指名卡: $(q "$J4" errors)"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"aaa111","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$FX/mr-7.json"
# herdr 有設但沒有 agent：都是 unknown，不報錯
printf '{"id":"cli:agent:list","result":{"agents":[],"type":"agent_list"}}' > "$OPSX_TEST_HERDR_AGENTS"
J5="$(opsx collect --root "$ROOT")"; assert_eq "$(q "$(card "$J5" a x4)" agent_status)" unknown; assert_eq "$(q "$J5" errors)" '[]'
printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","pane_id":"p4","agent_status":"working"},{"agent":"claude","pane_id":"p9","agent_status":"blocked"},{"agent":"claude","pane_id":"p7","agent_status":"idle","cwd":"/Users/me","workspace_id":"w9","terminal_title_stripped":"foo"}],"type":"agent_list"}}' > "$OPSX_TEST_HERDR_AGENTS"

# ---------- 不在 herdr 內 ----------
export HERDR_ENV=""
: > "$OPSX_FAKE_LOG"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0
assert_eq "$(q "$(card "$J" a x4)" agent_status)" null
assert_eq "$(q "$J" errors.0.source)" herdr
assert_eq "$(q "$J" unmatched_agents)" '[]'
assert_not_grep '^agent list' "$OPSX_FAKE_LOG"
C="$(card "$J" b y1)"; assert_eq "$(q "$C" waiting)" null "沒 herdr 就判不出 blocked"; assert_eq "$(q "$C" section)" 進行中

# ---------- sources.toml 登記的 repo 不在 root 底下也要算（D1）；重複的去重；不存在的跳過 ----------
Z="$FX/elsewhere/z"; mkdir -p "$Z/openspec/changes" "$Z/.git"
D="$Z/openspec/changes/z1"; mkdir -p "$D"; printf 'schema: opsx\nkind: dev\n' > "$D/.openspec.yaml"; printf '## 一句話\n\n別處的\n' > "$D/inbox.md"
printf '# 來源\n\n[[source]]\nkind = "github"\nrepo = "z"\nproject = "me/z"\npath = "%s"\n\n[[source]]\nkind = "gitlab"\nrepo = "a"\nproject = "g/a"\npath = "%s/a"\n\n[[source]]\nkind = "gitlab"\nrepo = "gone"\nproject = "g/gone"\npath = "%s/gone"\n' "$Z" "$ROOT" "$FX" > "$OPSX_STATE_DIR/sources.toml"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect with sources.toml: $J"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(sorted(r for s in json.load(sys.stdin)["scopes"] for r in s["repos"]))')" "['a', 'b', 'z']"
assert_eq "$(q "$(card "$J" z z1)" section)" 待指派
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(sum(1 for c in json.load(sys.stdin)["cards"] if c["repo"]=="a" and c["slug"]=="x1"))')" 1 "a 兩邊都有，卡不能重複"
assert_eq "$(q "$J" errors.0.source)" herdr; assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(len(json.load(sys.stdin)["errors"]))')" 1 "不存在的 path 不該進 errors"
# ---------- 舊卡在算 stage 之前就濾掉，只計數（collect-perf） ----------
R2="$FX/code2"; mkdir -p "$R2/r/.git" "$R2/r/openspec/changes"
for o in old-1 old-2 old-ws old-ideo old-nbsp sd-inbox; do mkdir -p "$R2/r/openspec/changes/$o"; printf 'schema: spec-driven\n' > "$R2/r/openspec/changes/$o/.openspec.yaml"; done
printf '\n  \n\t\n' > "$R2/r/openspec/changes/old-ws/inbox.md"
printf '\xe3\x80\x80\n' > "$R2/r/openspec/changes/old-ideo/inbox.md"   # 只有全形空白 U+3000
printf '\xc2\xa0\n' > "$R2/r/openspec/changes/old-nbsp/inbox.md"       # 只有 NBSP
printf '## 一句話\n\n有 inbox 的舊 schema\n' > "$R2/r/openspec/changes/sd-inbox/inbox.md"
mkdir -p "$R2/r/openspec/changes/new-1"; printf 'schema: opsx\n' > "$R2/r/openspec/changes/new-1/.openspec.yaml"
rm -f "$OPSX_STATE_DIR/sources.toml"; : > "$FX/stage.log"
J="$(
  # shellcheck source=/dev/null
  source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; source "$OPSX_ROOT/bin/lib/collect.sh"; source "$OPSX_ROOT/bin/lib/python.sh"; opsx_python_load
  stage_name() { printf '%s\n' "$2" >> "$FX/stage.log"; printf 'explore'; }
  LC_ALL=C opsx_collect --root "$R2" --state "$OPSX_STATE_DIR"   # 沒有 LANG 的啟動方式（launchd、nohup）
)"
assert_eq "$(sort "$FX/stage.log" | tr '\n' ' ')" "new-1 sd-inbox " "只有 opsx 卡和有 inbox 的卡算 stage"
assert_eq "$(q "$J" legacy)" '{"r": 5}'
assert_eq "$(card "$J" r old-ws)" null "只有空白的 inbox 仍是舊卡"
assert_eq "$(card "$J" r old-ideo)" null "只有 U+3000 的 inbox 在 LC_ALL=C 下仍是舊卡"
assert_eq "$(card "$J" r old-nbsp)" null "只有 NBSP 的 inbox 在 LC_ALL=C 下仍是舊卡"
assert_eq "$(q "$(card "$J" r sd-inbox)" stage)" explore
# ---------- 舊卡不查 MR：glab / gh 不被叫，errors 不記它（collect-legacy-mr-errors） ----------
R3="$FX/code3"; D="$R3/r3/openspec/changes/legacy-mr"; mkdir -p "$R3/r3/.git" "$D"
printf 'schema: spec-driven\n' > "$D/.openspec.yaml"
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/r3/-/merge_requests/4242\n' > "$D/report.md"
: > "$FX/glab-empty.json"; : > "$OPSX_FAKE_LOG"
J="$(OPSX_TEST_GLAB_JSON="$FX/glab-empty.json" OPSX_TEST_GLAB_JSON_BY_IID= opsx collect --root "$R3")"; assert_eq "$?" 0
[ ! -s "$OPSX_FAKE_LOG" ] || fail "只有舊卡的 repo 不該叫 glab / gh：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(q "$J" legacy)" '{"r3": 1}'
E="$(q "$J" errors)" || fail "errors 讀不到：$J"
case "$E" in *legacy-mr*|*glab*) fail "errors 不該指名舊卡：$E" ;; esac
echo ok
