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
# x8：explore 過（有 explore.md）沒派出 → 待指派；x9：上游已關閉、註解已刪，仍在收件匣
D=$(mkcard a x8); printf '## 已知\n\n## 待決\n\n## 不做\n' > "$D/explore.md"
D=$(mkcard a x9 "關掉的"); printf -- '---\ntype: 功能\nsource: gitlab:a#412\nfound: 2026-11-04\nupstream: closed\nstale: true\n---\n\n## 一句話\n\n關掉的\n' > "$D/inbox.md"
# y3：只有 inbox，但已派出 → 進行中
mkcard b y3 >/dev/null
# y2：MR pipeline 紅、已派出
D=$(mkcard b y2); printf '## 1\n\n- [x] 1.1 a\n' > "$D/tasks.md"
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/b/-/merge_requests/8\n' > "$D/report.md"

printf '[repos]\n"a" = "develop"\n' > "$OPSX_STATE_DIR/workspaces.toml"
printf '[repos."a"]\npush = true\nmr = false\n' > "$OPSX_STATE_DIR/grants.toml"
cat > "$OPSX_STATE_DIR/dispatch.json" <<'EOF'
{"a/x4":{"workspace":"develop","tab":"t1","pane":"p4","agent":"x4","model":"claude-opus-5-5","mode":"autopilot","kind":"dev","branch":"feat/x4/mikaela","grants":["push"],"started_at":"2026-11-05T09:00:00+08:00"},
 "b/y1":{"workspace":"b","tab":"t2","pane":"p9","agent":"y1","model":"claude-sonnet-5-5","mode":"drive","kind":"dev","branch":"feat/y1/mikaela","grants":[],"started_at":"2026-11-05T09:30:00+08:00"},
 "b/y3":{"workspace":"b","tab":"t4","pane":"p6","agent":"y3","model":"claude-opus-5-5","mode":"interactive","kind":"dev","branch":"feat/y3/mikaela","grants":[],"started_at":"2026-11-05T08:00:00+08:00"},
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
assert_eq "$(q "$J" repo_paths)" "{\"a\": \"$(cd "$ROOT/a" && pwd -P)\", \"b\": \"$(cd "$ROOT/b" && pwd -P)\"}"
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
C="$(card "$J" a x1)"; assert_eq "$(q "$C" stage)" explore; assert_eq "$(q "$C" section)" 收件匣; assert_eq "$(q "$C" title)" 第一張
assert_eq "$(q "$C" source)" me; assert_eq "$(q "$C" upstream)" null; assert_eq "$(q "$C" stale)" false
assert_eq "$(q "$C" waiting)" null; assert_eq "$(q "$C" dispatch)" null; assert_eq "$(q "$C" agent_status)" null; assert_eq "$(q "$C" kind)" dev
C="$(card "$J" a x8)"; assert_eq "$(q "$C" stage)" propose; assert_eq "$(q "$C" section)" 待指派
C="$(card "$J" a x9)"; assert_eq "$(q "$C" section)" 收件匣; assert_eq "$(q "$C" upstream)" closed; assert_eq "$(q "$C" stale)" true; assert_eq "$(q "$C" source)" "gitlab:a#412"
C="$(card "$J" b y3)"; assert_eq "$(q "$C" stage)" explore; assert_eq "$(q "$C" section)" 進行中
# 排序：待處理 · 進行中 · 待指派 · 收件匣 · 已完成
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys
s=[]
for c in json.load(sys.stdin)["cards"]:
    s.append(c["section"]) if not s or s[-1]!=c["section"] else None
print(" ".join(s))')" "待處理 進行中 待指派 收件匣 已完成"
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
# 最後輸出不在卡上：抽屜向 /api/output 取，collect 的卡沒有 last_output 鍵
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(sorted(c["slug"] for c in json.load(sys.stdin)["cards"] if "last_output" in c))')" "[]"

# 少一個條件 → 進行中
C="$(card "$J" b y2)"; assert_eq "$(q "$C" waiting)" null; assert_eq "$(q "$C" section)" 進行中
assert_eq "$(q "$C" mr.conditions.pipeline)" false; assert_eq "$(q "$C" mr.blocked_on)" pipeline; assert_eq "$(q "$C" agent_status)" unknown

# 終端機等待輸入
C="$(card "$J" b y1)"; assert_eq "$(q "$C" waiting.type)" 終端機等待輸入
assert_eq "$(q "$C" waiting.options)" '["開啟 pane", "停止", "重新指派"]'; assert_eq "$(q "$C" section)" 待處理

# 沒對到卡的 agent
assert_eq "$(q "$J" unmatched_agents)" '[{"agent_status": "idle", "cwd": "/Users/me", "name": "foo", "orphan": false, "pane": "p7", "workspace": "w9"}]'
# 真樣本也讀得懂（兩個 agent 都沒對到卡）
J2="$(OPSX_TEST_HERDR_AGENTS= opsx collect --root "$ROOT")"; assert_eq "$(q "$J2" unmatched_agents.0.pane)" "w1:p2"; assert_eq "$(q "$J2" unmatched_agents.1.name)" "Worktree cleanup"
assert_eq "$(q "$J" unfiled)" '[]' "沒有 unfiled/ 時是空陣列"
assert_eq "$(q "$J" last_sync)" null "沒有 sync.log 時是 null"
assert_eq "$(q "$J" errors)" '[]'
# 不寫檔（cache/ 與 fixture 的 python 除外）
[ "$(find "$OPSX_STATE_DIR" -type f ! -path '*/cache/*' ! -name '*.lock' ! -name python | wc -l | tr -d ' ')" = 3 ] || fail "collect 不該在 state 寫檔：$(find "$OPSX_STATE_DIR" -type f)"
[ -z "$(find "$ROOT" -newer "$OPSX_STATE_DIR/dispatch.json" -type f)" ] || fail "collect 不該動卡的檔"

# ---------- 待分類：unfiled/*.md 列出，dropped/ 不算 ----------
mkdir -p "$OPSX_STATE_DIR/unfiled/dropped"
printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-06\nrelated:\n---\n\n## 一句話\n\n試試看\n' > "$OPSX_STATE_DIR/unfiled/me-20261106-1430.md"
printf -- '---\nsource: me\n---\n\n## 一句話\n\n丟掉的\n' > "$OPSX_STATE_DIR/unfiled/dropped/me-20261105-0900.md"
J6="$(opsx collect --root "$ROOT")"
assert_eq "$(q "$J6" unfiled)" '[{"found": "2026-11-06", "slug": "me-20261106-1430", "source": "me", "title": "試試看"}]'
mv "$OPSX_STATE_DIR/unfiled" "$FX/unfiled-done"
# ---------- 上次同步：sync.log 最後一列 source = sync（debt.sh 自己的 debt 列不算） ----------
printf '2026-11-05T09:00:00+08:00\tsync\t5\t新建 5 · 更新 0 · 沒變 0 · 錯誤 1：glab: 沒登入\n2026-11-06T09:00:00+08:00\tsync\t2\t新建 2 · 更新 1 · 沒變 3 · 錯誤 0\n2026-11-06T09:00:01+08:00\tdebt\t0\t掃到 4 處 shortcut\n' > "$OPSX_STATE_DIR/sync.log"
J7="$(opsx collect --root "$ROOT")"
assert_eq "$(q "$J7" last_sync)" '{"at": "2026-11-06T09:00:00+08:00", "created": 2, "errors": 0, "first_error": "", "unchanged": 3, "updated": 1}'
mv "$OPSX_STATE_DIR/sync.log" "$FX/sync-done.log"

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
assert_eq "$(q "$(card "$J" z z1)" section)" 收件匣
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
mkdir -p "$R2/r/openspec/changes/opsx-noeol"; printf 'schema: opsx' > "$R2/r/openspec/changes/opsx-noeol/.openspec.yaml"
mkdir -p "$R2/r/openspec/changes/opsx-crlf"; printf 'schema: opsx\r\n' > "$R2/r/openspec/changes/opsx-crlf/.openspec.yaml"
rm -f "$OPSX_STATE_DIR/sources.toml"; : > "$FX/stage.log"
J="$(
  # shellcheck source=/dev/null
  source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; source "$OPSX_ROOT/bin/lib/collect.sh"; source "$OPSX_ROOT/bin/lib/python.sh"; opsx_python_load
  stage_name() { printf '%s\n' "$2" >> "$FX/stage.log"; printf 'explore'; }
  LC_ALL=C opsx_collect --root "$R2" --state "$OPSX_STATE_DIR"   # 沒有 LANG 的啟動方式（launchd、nohup）
)"
assert_eq "$(sort "$FX/stage.log" | tr '\n' ' ')" "new-1 opsx-crlf opsx-noeol sd-inbox " "只有 opsx 卡和有 inbox 的卡算 stage，沒有結尾換行或 CRLF 的 opsx 卡也算"
assert_eq "$(q "$J" legacy)" '{"r": 5}'
assert_eq "$(card "$J" r old-ws)" null "只有空白的 inbox 仍是舊卡"
assert_eq "$(card "$J" r old-ideo)" null "只有 U+3000 的 inbox 在 LC_ALL=C 下仍是舊卡"
assert_eq "$(card "$J" r old-nbsp)" null "只有 NBSP 的 inbox 在 LC_ALL=C 下仍是舊卡"
assert_eq "$(q "$(card "$J" r sd-inbox)" stage)" explore
assert_eq "$(q "$(card "$J" r opsx-noeol)" stage)" explore "沒有結尾換行的 opsx 卡要在 cards"
assert_eq "$(q "$(card "$J" r opsx-crlf)" stage)" explore "CRLF 的 opsx 卡要在 cards"
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
# ---------- 壞的 opened_at：改 null 並記 errors；寬限內照收（specs/board-collect「gate 與 MR 的時間」） ----------
R5="$FX/code5"; D="$R5/r5/openspec/changes/bad-ts"; mkdir -p "$R5/r5/.git" "$D"
printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$D/.openspec.yaml"; printf '## 一句話\n\n壞時間\n' > "$D/inbox.md"
FUT="$(date -u -v+8H +%Y-%m-%dT%H:%M:%SZ)"; SOON="$(date -v+30S +%Y-%m-%dT%H:%M:%S%z | sed -E 's/([0-9]{2})([0-9]{2})$/\1:\2/')"
printf '## g1\nstatus: open\nopened_at: %s\n\n## g2\nstatus: open\nopened_at: 2026-11-06 14:05\n\n## g3\nstatus: open\nopened_at: 昨天\n\n## g4\nstatus: open\nopened_at: %s\n\n## g5\nstatus: answered\nopened_at: 昨天\n' "$FUT" "$SOON" > "$D/gates.md"
J="$(opsx collect --root "$R5")"; assert_eq "$?" 0 "壞時間 collect rc"
assert_eq "$(q "$(card "$J" r5 bad-ts)" open_gates)" "[{\"id\": \"g1\", \"opened_at\": null}, {\"id\": \"g2\", \"opened_at\": null}, {\"id\": \"g3\", \"opened_at\": null}, {\"id\": \"g4\", \"opened_at\": \"$SOON\"}]"
E="$(q "$J" errors)"
GE="$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(json.dumps([e for e in json.load(sys.stdin)["errors"] if e["source"].endswith("/r5/openspec/changes/bad-ts/gates.md")],ensure_ascii=False))')"
assert_eq "$(printf '%s' "$GE" | python3 -I -c 'import json,sys;print(len(json.load(sys.stdin)))')" 3 "三個壞值各一筆 error：$E"
for want in "g1.*$FUT" "g2.*2026-11-06 14:05" "g3.*昨天"; do printf '%s' "$GE" | grep -Eq "$want" || fail "errors 要有 gate id 與原值（$want）：$E"; done
case "$E" in *g4*|*g5*) fail "寬限內與 answered 的 gate 不該進 errors：$E" ;; esac

# ---------- generated_at 在讀任何來源之前取：卡片迴圈裡的 glab 慢 4 秒也不會往後（banner-same-second） ----------
# 慢的是迴圈裡的 mr_json：它比 herdr 早讀，取時點放在迴圈之後的實作會被抓到
R4="$FX/code4"; D="$R4/r4/openspec/changes/slow-mr"; mkdir -p "$R4/r4/.git" "$D"
printf 'schema: opsx\ncreated: 2026-11-06\nkind: dev\n' > "$D/.openspec.yaml"; printf '## 一句話\n\n慢\n' > "$D/inbox.md"
printf '# report\n\n## MR\nhttps://gitlab.tsg-navigator.com/agentory/r4/-/merge_requests/9\n' > "$D/report.md"
SLOW="$FX/slow-bin"; mkdir -p "$SLOW"
printf '#!/usr/bin/env bash\n[ "$1 $2" = "mr view" ] && sleep 4\nexec bash "%s/tests/fakes/glab" "$@"\n' "$OPSX_ROOT" > "$SLOW/glab"; chmod +x "$SLOW/glab"
: > "$OPSX_FAKE_LOG"; S="$(date +%s)"
J="$(PATH="$SLOW:$PATH" opsx collect --root "$R4")"; assert_eq "$?" 0
grep -q '^mr view 9 ' "$OPSX_FAKE_LOG" || fail "glab 要真的被叫到，慢才有意義：$(cat "$OPSX_FAKE_LOG")"
G="$(printf '%s' "$J" | python3 -I -c 'import datetime,json,sys;print(int(datetime.datetime.fromisoformat(json.load(sys.stdin)["generated_at"]).timestamp()))')"
[ "$G" -le $((S + 2)) ] || fail "generated_at 要在讀來源前取：呼叫前 ${S}，generated_at ${G}"

# ---------- 卡的等級與目前 milestone（workplan-priority/priority-board，specs/board-collect「卡的等級」「目前 milestone」） ----------
R8="$FX/code8"; mkdir -p "$R8/p/.git" "$R8/q/.git" "$R8/w/.git"
pcard() { # <repo> <slug> [frontmatter 行…]
  local d="$R8/$1/openspec/changes/$2"; shift 2; mkdir -p "$d"
  printf 'schema: opsx\ncreated: 2026-11-10\nkind: dev\n' > "$d/.openspec.yaml"
  { printf -- '---\ntype: 功能\nsource: me\nfound: 2026-11-10\nrelated:\n'; printf '%s\n' "$@"; printf -- '---\n\n## 一句話\n\n%s\n' "$(basename "$d")"; } > "$d/inbox.md"
}
pcard p hot 'kind_of_work: incident' 'impact: security' 'evidence: tests/auth.test.sh 第 3 案'
pcard p held 'priority: P1' 'priority_reason: 等客戶'
pcard p bad 'kind_of_work: incident' 'impact: data'
pcard p plain
D="$R8/p/openspec/changes/archive/2026-11-01-gone"; mkdir -p "$D"; printf 'schema: opsx\n' > "$D/.openspec.yaml"; printf '## 一句話\n\n舊的\n' > "$D/inbox.md"
cat > "$R8/p/openspec/workplan.yaml" <<'EOF'
milestones:
  - name: "1.0"
    goal: "能開單出貨"
  - name: "2.0"
    goal: "能退貨"
current_milestone: "1.0"
features:
  - name: order
    milestone: "1.0"
    prs:
      - name: p-order
        branch: feat/p-order/m
        status: pending
        depends-on: []
        changes:
          - name: c1
            status: done
          - name: c2
            status: pending
          - name: c3
            status: in-progress
  - name: refund
    milestone: "2.0"
    prs:
      - name: p-refund
        branch: feat/p-refund/m
        status: pending
        depends-on: []
        changes:
          - name: c4
            status: pending
EOF
pcard q q1
printf 'milestones:\n  - name: "1.0"\n    goal: "先上線"\nfeatures:\n  - name: f\n    milestone: "1.0"\n' > "$R8/q/openspec/workplan.yaml"
pcard w w1 'kind_of_work: incident' 'impact: security' 'evidence: x'
printf 'milestones:\n  - name: "1.0"\n    goal: "先上線"\ncurrent_milestone: "9.9"\n' > "$R8/w/openspec/workplan.yaml"
J="$(opsx collect --root "$R8")"; assert_eq "$?" 0 "priority collect rc: $J"
# 卡帶等級與理由
C="$(card "$J" p hot)"; assert_eq "$(q "$C" priority.level)" P0; assert_eq "$(q "$C" priority.overridden)" false
case "$(q "$C" priority.reason)" in *security*) ;; *) fail "hot 的理由要含 security：$(q "$C" priority)" ;; esac
# 覆寫的卡
C="$(card "$J" p held)"; assert_eq "$(q "$C" priority.level)" P1; assert_eq "$(q "$C" priority.overridden)" true
# 算不出來：那張 null、errors 指名卡與 evidence；同 repo 其他卡照常
assert_eq "$(q "$(card "$J" p bad)" priority)" null
PE="$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(json.dumps([e for e in json.load(sys.stdin)["errors"] if "bad" in e["message"] and "evidence" in e["message"]],ensure_ascii=False))')"
assert_eq "$(printf '%s' "$PE" | python3 -I -c 'import json,sys;print(len(json.load(sys.stdin)))')" 1 "bad 的 error 要有一筆，含卡名與 evidence：$(q "$J" errors)"
assert_eq "$(q "$(card "$J" p plain)" priority.level)" P2
# 已歸檔的卡沒有等級
assert_eq "$(q "$(card "$J" p gone)" priority)" null
# workplan 壞了：那個 repo 的卡都 null，errors 記 workplan 路徑
assert_eq "$(q "$(card "$J" w w1)" priority)" null
WE="$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(json.dumps([e for e in json.load(sys.stdin)["errors"] if e["source"].endswith("/w/openspec/workplan.yaml")],ensure_ascii=False))')"
case "$WE" in *9.9*) ;; *) fail "壞 workplan 要記進 errors 並指名值：$(q "$J" errors)" ;; esac
assert_eq "$(q "$(card "$J" q q1)" priority.level)" P2
# 還差幾張；沒設目前 milestone 的 repo 沒有 key
assert_eq "$(q "$J" milestones)" '{"p": {"current": "1.0", "goal": "能開單出貨", "remaining": 2}}'

# ---------- 孤兒 pane：cwd 在 opsx worktree 底下，且卡已歸檔 / split / stopped / 目錄不在（specs/opsx-reap「孤兒 pane 的判定」、board-collect「orphans 清單」） ----------
RP6="$FX/code-reap6"; mkdir -p "$RP6/o/.git" "$RP6/o/openspec/changes/archive"
O="$(cd "$RP6/o" && pwd -P)"
mkcard6() { # <slug> [額外 inbox 前言行]
  local d="$RP6/o/openspec/changes/$1"; mkdir -p "$d"
  printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$d/.openspec.yaml"
  printf -- '---\nsource: me\nfound: 2026-11-04\n%s---\n\n## 一句話\n\n%s\n' "${2:-}" "$1" > "$d/inbox.md"
  printf '## 1\n\n- [ ] 1.1 a\n' > "$d/tasks.md"
}
for s in ar ar2; do D="$RP6/o/openspec/changes/archive/2026-11-01-$s"; mkdir -p "$D"; printf 'schema: opsx\nkind: dev\n' > "$D/.openspec.yaml"; printf '## 一句話\n\n%s\n' "$s" > "$D/inbox.md"; done
mkcard6 sp 'split_into: [sp-a, sp-b]
'
mkcard6 st
mkcard6 lv
printf '{"o/ar":{"pane":"w1:p1","mode":"autopilot","worktree":"%s/.claude/worktrees/ar"},"o/ar2":{"pane":"w1:p8","mode":"autopilot"},"o/sp":{"pane":"w1:p2","mode":"autopilot"},"o/st":{"pane":"w1:p3","mode":"stopped"},"o/cm":{"pane":"w1:p4","mode":"autopilot"},"o/re":{"pane":"w1:p5","mode":"stopped"},"o/lv":{"pane":"w1:p6","mode":"autopilot"}}' "$O" > "$OPSX_STATE_DIR/dispatch.json"
agent6() { # <pane> <status> <cwd> [foreground_cwd]
  printf '{"agent":"claude","pane_id":"%s","agent_status":"%s","cwd":"%s","foreground_cwd":"%s","terminal_title_stripped":"t-%s"}' "$1" "$2" "$3" "${4:-$3}" "$1"
}
{ printf '{"id":"cli:agent:list","result":{"agents":['
  agent6 w1:p1 idle "$O/.claude/worktrees/ar"; printf ','
  agent6 w1:p2 idle /Users/me "$O/.claude/worktrees/sp"; printf ','
  agent6 w1:p3 idle "$O/.claude/worktrees/st"; printf ','
  agent6 w1:p4 idle "$O/.claude/worktrees/cm"; printf ','
  agent6 w1:p5 idle /Users/me/notes; printf ','
  agent6 w1:p6 idle "$O/.claude/worktrees/lv"; printf ','
  agent6 w1:p7 idle /Users/me/code/gmtc-rag; printf ','
  agent6 w1:p8 working "$O/.claude/worktrees/ar2"; printf ','
  agent6 w1:p9 idle "$O/.claude/worktrees/my-own-session"
  printf '],"type":"agent_list"}}'; } > "$FX/agents6.json"
export HERDR_ENV=1
J="$(OPSX_TEST_HERDR_AGENTS="$FX/agents6.json" opsx collect --root "$RP6")"; assert_eq "$?" 0 "orphans collect: $J"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(json.dumps({o["pane"]:o["reason"] for o in json.load(sys.stdin)["orphans"]},sort_keys=True))')" \
  '{"w1:p1": "archived", "w1:p2": "split", "w1:p3": "stopped", "w1:p4": "card-missing", "w1:p8": "archived"}' "孤兒：已歸檔、split（只靠 foreground_cwd）、stopped、卡不在、還在做事的也列"
assert_eq "$(q "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(json.dumps([o for o in json.load(sys.stdin)["orphans"] if o["pane"]=="w1:p1"][0]))')" repo)" o
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;o=[o for o in json.load(sys.stdin)["orphans"] if o["pane"]=="w1:p1"][0];print(o["slug"],o["agent_status"],o["cwd"]==sys.argv[1]+"/.claude/worktrees/ar")' "$O")" "ar idle True"
# unmatched_agents：已歸檔 / split 配到卡的不進來；stopped 與卡不在的進來且 orphan 為 true；使用者自己的 orphan 為 false，pane id 被重用的也是
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(json.dumps({a["pane"]:a["orphan"] for a in json.load(sys.stdin)["unmatched_agents"]},sort_keys=True))')" \
  '{"w1:p3": true, "w1:p4": true, "w1:p5": false, "w1:p7": false, "w1:p9": false}' "unmatched_agents 的 orphan 欄；p9 在 .claude/worktrees/ 底下但 dispatch.json 沒記，是使用者自己的 session"
# herdr 不可用：orphans 是 []
export HERDR_ENV=""
J="$(opsx collect --root "$RP6")"; assert_eq "$(q "$J" orphans)" '[]'

# ---------- review 第 1 輪的回歸測試：人或活卡的 pane 不能被當成孤兒（三個重現情境，同一個 orphan_reason） ----------
# (a) slug 先歸檔、後來又建了活卡：活卡的 pane 與同 cwd 的人工 pane 都不是孤兒
# (b) 活卡的 repo 不在這次掃描範圍：不能判成 card-missing
# (c) dispatch.json 留著舊的 stopped 條目（pane w1:p9），人自己在同名 worktree 開的 pane（w1:p3）不是它的
RP7="$FX/code-reap7"; mkdir -p "$RP7/o/.git" "$RP7/o/openspec/changes/foo" "$RP7/o/openspec/changes/archive/2026-11-01-foo"
O7="$(cd "$RP7/o" && pwd -P)"; X7="$FX/elsewhere7/x"
for d in "$RP7/o/openspec/changes/foo" "$RP7/o/openspec/changes/archive/2026-11-01-foo"; do printf 'schema: opsx\nkind: dev\n' > "$d/.openspec.yaml"; printf '## 一句話\n\nfoo\n' > "$d/inbox.md"; done
printf '{"o/foo":{"pane":"w1:p1","mode":"autopilot"},"x/lv":{"pane":"w1:p4","mode":"autopilot","worktree":"%s/.claude/worktrees/lv"},"o/bar":{"pane":"w1:p9","mode":"stopped"}}' "$X7" > "$OPSX_STATE_DIR/dispatch.json"
{ printf '{"id":"cli:agent:list","result":{"agents":['
  agent6 w1:p1 working "$O7/.claude/worktrees/foo"; printf ','
  agent6 w1:p2 idle "$O7/.claude/worktrees/foo"; printf ','
  agent6 w1:p4 idle "$X7/.claude/worktrees/lv"; printf ','
  agent6 w1:p3 idle "$O7/.claude/worktrees/bar"
  printf '],"type":"agent_list"}}'; } > "$FX/agents7.json"
export HERDR_ENV=1
J="$(OPSX_TEST_HERDR_AGENTS="$FX/agents7.json" opsx collect --root "$RP7")"; assert_eq "$?" 0 "回歸 collect: $J"
assert_eq "$(q "$J" orphans)" '[]' "活卡的 pane、未掃描 repo 的活卡、人自己開的 pane 都不能是孤兒"
export HERDR_ENV=""

# ---------- review 第 2 輪的兩個 BUG：回歸測試 ----------
# (1) opsx 已經關掉的 pane（stop 記 pane_closed_at、reap 記 reaped_at），條目還記著 pane id；herdr 之後把同一個 id 發給別人，
#     人在那棵 worktree 開的 pane 三個條件都符合，不能因此被當成孤兒
RP8="$FX/code-reap8"; mkdir -p "$RP8/o/.git" "$RP8/o/openspec/changes/st" "$RP8/o/openspec/changes/archive/2026-11-01-ar"
O8="$(cd "$RP8/o" && pwd -P)"
for d in "$RP8/o/openspec/changes/st" "$RP8/o/openspec/changes/archive/2026-11-01-ar"; do printf 'schema: opsx\nkind: dev\n' > "$d/.openspec.yaml"; printf '## 一句話\n\nx\n' > "$d/inbox.md"; done
printf '{"o/st":{"pane":"w1:p3","mode":"stopped","pane_closed_at":"2026-11-10T10:00:00+08:00"},"o/ar":{"pane":"w1:p5","mode":"autopilot","reaped_at":"2026-11-10T10:00:00+08:00"}}' > "$OPSX_STATE_DIR/dispatch.json"
{ printf '{"id":"cli:agent:list","result":{"agents":['
  agent6 w1:p3 idle "$O8/.claude/worktrees/st"; printf ','
  agent6 w1:p5 idle "$O8/.claude/worktrees/ar"
  printf '],"type":"agent_list"}}'; } > "$FX/agents8.json"
export HERDR_ENV=1
J="$(OPSX_TEST_HERDR_AGENTS="$FX/agents8.json" opsx collect --root "$RP8")"; assert_eq "$?" 0 "回歸 1 collect: $J"
assert_eq "$(q "$J" orphans)" '[]' "已經關掉的 pane（pane_closed_at / reaped_at）的 id 被重用時，新的 pane 不是孤兒"
# (2) 兩個條目共用一棵 worktree 與一個 pane（chain 續接）：條目順序讓最後一筆是已歸檔的，活著的續接 pane 也不能列成孤兒
RP9="$FX/code-reap9"; mkdir -p "$RP9/o/.git" "$RP9/o/openspec/changes/kid" "$RP9/o/openspec/changes/archive/2026-11-01-par"
O9="$(cd "$RP9/o" && pwd -P)"
for d in "$RP9/o/openspec/changes/kid" "$RP9/o/openspec/changes/archive/2026-11-01-par"; do printf 'schema: opsx\nkind: dev\n' > "$d/.openspec.yaml"; printf '## 一句話\n\nx\n' > "$d/inbox.md"; done
printf '{"o/kid":{"pane":"w1:p1","mode":"autopilot","worktree":"%s/.claude/worktrees/par"},"o/par":{"pane":"w1:p1","mode":"autopilot","worktree":"%s/.claude/worktrees/par"}}' "$O9" "$O9" > "$OPSX_STATE_DIR/dispatch.json"
{ printf '{"id":"cli:agent:list","result":{"agents":['
  agent6 w1:p1 idle "$O9/.claude/worktrees/par"
  printf '],"type":"agent_list"}}'; } > "$FX/agents9.json"
J="$(OPSX_TEST_HERDR_AGENTS="$FX/agents9.json" opsx collect --root "$RP9")"; assert_eq "$?" 0 "回歸 2 collect: $J"
assert_eq "$(q "$J" orphans)" '[]' "共用 worktree 與 pane 的活卡（kid）還在，不能列成孤兒"
export HERDR_ENV=""

# ---------- gate type 同義詞、type 不明、needs: run（gate-type-normalize） ----------
R7="$FX/code7"; mkdir -p "$R7/r6/.git"
gcard() { # <slug> <gates.md 內容>
  local d="$R7/r6/openspec/changes/$1"; mkdir -p "$d"
  printf 'schema: opsx\ncreated: 2026-11-10\nkind: dev\n' > "$d/.openspec.yaml"; printf '## 一句話\n\n%s\n' "$1" > "$d/inbox.md"
  printf '## 1\n\n- [ ] 1.1 a\n' > "$d/tasks.md"; printf '%b' "$2" > "$d/gates.md"
}
gcard t-auth    '## g1\ntype: authorization\naction: push\nstatus: open\n問題: push？\n建議: 允許\n'
gcard t-zh-dec  '## g1\ntype: 等待決定\nstatus: open\n問題: 哪個？\n選項: A | B (Recommended)\n'
gcard t-zh-auth '## g1\ntype:  等待授權 \naction: push\nstatus: open\n問題: push？\n'
gcard t-notype  '## g1\nstatus: open\n問題: 沒寫 type\n建議: 照做\n'
gcard t-ish     '## g1\ntype: approval-ish\nstatus: open\n問題: 表外\n'
gcard t-run     '## g1\ntype: decision\nneeds: run\nstatus: open\n問題: 跑一下\n建議: ls -la /tmp\n'
gcard t-plain   '## g1\ntype: decision\nstatus: open\n問題: 選\n選項: A | B\n建議: A\n'
gcard t-badneed '## g1\ntype: decision\nneeds: ssh\nstatus: open\n問題: 選\n'
J="$(opsx collect --root "$R7")"; assert_eq "$?" 0 "gate-type collect rc"
w() { q "$(card "$J" r6 "$1")" "waiting.$2"; }
assert_eq "$(w t-auth type)" 等待授權 "authorization 是授權"
assert_eq "$(w t-auth options)" '["這次", "這張卡", "這個 repo 永遠", "拒絕"]'
assert_eq "$(w t-zh-dec type)" 等待決定; assert_eq "$(w t-zh-dec options)" '["A", "B"]'
assert_eq "$(w t-zh-auth type)" 等待授權 "值前後有空白"
assert_eq "$(w t-notype type)" "type 不明" "沒寫 type 不再當決定"
assert_eq "$(w t-notype options)" '[]'; assert_eq "$(w t-notype gate_id)" g1; assert_eq "$(w t-notype question)" "沒寫 type"
assert_eq "$(w t-ish type)" "type 不明" "表外的值"
assert_eq "$(w t-run needs)" run; assert_eq "$(w t-run type)" 等待決定; assert_eq "$(w t-run recommended)" "ls -la /tmp"
assert_eq "$(w t-plain needs)" null "沒標 needs"
assert_eq "$(w t-badneed needs)" null "needs 只認 run"
assert_eq "$(w t-auth needs)" null; assert_eq "$(w t-notype needs)" null

# ---------- session：workplan 的 feature 收成 sessions[]（specs/board-collect「收成 session 的 feature」等四條） ----------
R6="$FX/code6"; S6="$FX/state6"; mkdir -p "$R6/s/.git" "$R6/t/.git" "$R6/u/.git" "$R6/t/openspec/changes" "$R6/u/openspec/changes" "$S6"
sess() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
s=[s for s in d["sessions"] if s["repo"]==sys.argv[1] and s["feature"]==sys.argv[2]]
print(json.dumps(s[0],ensure_ascii=False) if s else "null")' "$2" "$3"; }
ROOT_SAVED="$ROOT"; ROOT="$R6"
# bt：主 change 在 review（tasks 全勾、tests green），底下三個子殼
D=$(mkcard s bt); printf '## 1\n\n- [x] 1.1 a\n' > "$D/tasks.md"; printf '{"phase":"review","tests":"green"}' > "$D/status.json"
mkdir -p "$D/subs/ct" "$D/subs/as" "$D/subs/ui"
printf '# p\n' > "$D/subs/ct/proposal.md"; printf '## 1\n\n- [ ] 1.1 a\n' > "$D/subs/ct/tasks.md"; printf '[]' > "$D/subs/ct/status.json"   # 合法 JSON 但不是 object
printf '## g1\ntype: decision\nstatus: open\n問題: 哪個？\n選項: A | B (Recommended)\n' > "$D/subs/as/gates.md"
printf '# p\n' > "$D/subs/ui/proposal.md"; printf '{"phase": "apply", "tests": "unknown", "worker": "subagent-2"}' > "$D/subs/ui/status.json"
mkcard s fx1 >/dev/null; mkcard s solo >/dev/null
mkdir -p "$R6/s/openspec/changes/z1/subs/z1b"   # z1 已合併、殼只剩 subs/：不是卡，但讓 fdone 有子殼
cat > "$R6/s/openspec/workplan.yaml" <<'EOF'
features:
  - name: fb
    prs:
      - name: m1
        status: merged
        changes:
          - name: a1
            status: done
          - name: a2
            status: done
          - name: a3
            status: done
          - name: a4
            status: done
      - name: bt
        status: in-progress
        changes:
          - name: ct
            status: in-progress
          - name: as
            status: pending
          - name: ui
            status: done
  - name: fx
    prs:
      - name: fx1
        status: in-progress
        changes:
          - name: fx1
            status: in-progress
          - name: fx1-fix
            status: pending
  - name: solo
    prs:
      - name: solo
        status: in-progress
        changes:
          - name: solo
            status: in-progress
  - name: fdone
    prs:
      - name: z1
        status: merged
        changes:
          - name: z1
            status: done
          - name: z1b
            status: done
      - name: z2
        status: merged
        changes:
          - name: z2
            status: done
  - name: fdup
    prs:
      - name: bt
        status: in-progress
        changes:
          - name: ct
            status: in-progress
EOF
printf 'features:\n  - name: \xff\xfe\n' > "$R6/t/openspec/workplan.yaml"   # 不是 UTF-8
printf 'features: oops\n' > "$R6/u/openspec/workplan.yaml"                 # features 不是 list
printf '{"s/bt":{"workspace":"s","tab":"t1","pane":"p-bt","agent":"bt","model":"claude-opus-5-5","mode":"autopilot","kind":"dev","branch":"feat/bt/mikaela","grants":[],"started_at":"2026-11-05T09:00:00+08:00"}}' > "$S6/dispatch.json"
J="$(opsx collect --root "$R6" --state "$S6")"; assert_eq "$?" 0 "session collect rc: $J"
WS="$(cd "$R6/s" && pwd -P)/openspec/workplan.yaml"; WT="$(cd "$R6/t" && pwd -P)/openspec/workplan.yaml"; WU="$(cd "$R6/u" && pwd -P)/openspec/workplan.yaml"
# 1.1 哪些 feature 收：只有 PR 掛子殼的；一個 PR 掛兩個平放 change（fx）與 1 PR 1 change（solo）都不收；workplan 壞的 repo 沒有 session、各記一筆 errors
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(" ".join("%s/%s" % (s["repo"], s["feature"]) for s in json.load(sys.stdin)["sessions"]))')" "s/fb s/fdone s/fdup"
for k in solo fx1; do
  C="$(card "$J" s $k)"; assert_eq "$(printf '%s' "$C" | python3 -I -c 'import json,sys;print("session" in json.load(sys.stdin))')" False "$k 的卡沒有 session 欄"
done
for w in "$WT" "$WU"; do
  assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(sum(1 for e in json.load(sys.stdin)["errors"] if e["source"]==sys.argv[1]))' "$w")" 1 "壞 workplan 一筆 errors：$w $(q "$J" errors)"
done
# 1.2 樹：mains 依 PR 順序；有卡的主 change 跟卡同值；沒資料夾的 merged PR 是 archive；subs 依 changes 順序
F="$(sess "$J" s fb)"
assert_eq "$(q "$F" mains.0.slug) $(q "$F" mains.0.pr_status) $(q "$F" mains.0.stage) $(q "$F" mains.0.section)" "m1 merged archive 已完成"
assert_eq "$(q "$F" mains.0.subs.0)" '{"open_gates": [], "slug": "a1", "stage": null, "status": "done", "waiting": null, "worker": null}'
assert_eq "$(printf '%s' "$F" | python3 -I -c 'import json,sys;print([s["slug"] for s in json.load(sys.stdin)["mains"][1]["subs"]])')" "['ct', 'as', 'ui']"
assert_eq "$(printf '%s\n%s' "$F" "$(card "$J" s bt)" | python3 -I -c 'import json,sys
m,c=[json.loads(l) for l in sys.stdin.read().split("\n")]; m=m["mains"][1]
ks=["stage","section","dispatch","agent_status","open_gates","waiting"]
print([k for k in ks if m[k]!=c[k]], m["slug"], m["pr_status"], m["stage"], m["section"], m["dispatch"]["pane"])')" "[] bt in-progress review 進行中 p-bt"
assert_eq "$(q "$F" mains.1.subs.1.open_gates)" '[{"id": "g1", "opened_at": null}]'
assert_eq "$(q "$F" mains.1.subs.1.waiting.type) $(q "$F" mains.1.subs.1.waiting.recommended) $(q "$F" mains.1.subs.1.stage)" "等待決定 B inbox"
assert_eq "$(q "$F" mains.1.subs.0.stage) $(q "$F" mains.1.subs.0.worker) $(q "$F" mains.1.subs.0.status)" "apply null in-progress"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(sum(1 for e in json.load(sys.stdin)["errors"] if e["source"].endswith("/subs/ct/status.json")))')" 2 "status.json 不是 object 記 errors（bt/ct 在 fb 與 fdup 各讀一次），站點改由檔推"
assert_eq "$(q "$F" mains.1.subs.2.stage) $(q "$F" mains.1.subs.2.worker)" "apply subagent-2"
# 1.3 一行：計數、目前站、section（子 change 的 gate 讓 session 進待處理，主 change 卡本身是進行中）
assert_eq "$(q "$F" main_done)/$(q "$F" main_total) $(q "$F" sub_done)/$(q "$F" sub_total)" "1/2 5/7"
assert_eq "$(q "$F" current)" '{"slug": "bt", "stage": "review"}'
assert_eq "$(q "$F" section)" 待處理
F="$(sess "$J" s fdone)"; assert_eq "$(q "$F" section) $(q "$F" current) $(q "$F" main_done)/$(q "$F" main_total)" "已完成 null 2/2"
# 1.4 卡標上 session，卡仍在 cards[]；bt 同時在 fb 與 fdup：取第一個，記一筆 errors
assert_eq "$(q "$(card "$J" s bt)" session)" s/fb
E="$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(json.dumps([e for e in json.load(sys.stdin)["errors"] if e["source"]==sys.argv[1]],ensure_ascii=False))' "$WS")"
assert_eq "$(printf '%s' "$E" | python3 -I -c 'import json,sys;print(len(json.load(sys.stdin)))')" 1 "重複 slug 一筆 errors：$E"
printf '%s' "$E" | grep -q 'bt' || fail "重複 slug 的 error 要指名 bt：$E"
ROOT="$ROOT_SAVED"
echo ok
