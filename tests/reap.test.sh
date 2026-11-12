#!/usr/bin/env bash
# opsx reap 與 stop 對已歸檔卡：驗收 specs/opsx-reap/spec.md 全部 Scenario（pane-reaper）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"

R="$(mk_repo a)"

# --- stop 對卡目錄已不在（已歸檔）的卡：照樣關 pane、標 stopped、rc 0、不印「卡的目錄不存在」 ---
printf '{"a/gone":{"pane":"w1:p3","mode":"autopilot","drive_pid":null,"worktree":"%s/.claude/worktrees/gone"}}' "$R" > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx stop gone --repo "$R" 2>&1)"; rc=$?
assert_eq "$rc" 0 "stop 已歸檔的卡: $out"
case "$out" in *"卡的目錄不存在"*) fail "不該印卡的目錄不存在: $out" ;; esac
assert_grep "pane close w1:p3" "$OPSX_FAKE_LOG"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["a/gone"];assert d["mode"]=="stopped" and d["stopped_at"],d' "$OPSX_STATE_DIR/dispatch.json" || fail "dispatch.json 要標 stopped"
assert_grep "gone" "$OPSX_STATE_DIR/reap.log"
python3 -I -c 'import json,sys;assert json.load(open(sys.argv[1]))["a/gone"]["pane_closed_at"]' "$OPSX_STATE_DIR/dispatch.json" || fail "pane 關成功要記 pane_closed_at（之後 pane id 被重用時，collect 靠它不認領新的 pane）"
# pane 沒關成：不記 pane_closed_at，這個 pane 之後仍可能是孤兒
printf '{"a/stuck":{"pane":"w1:p4","mode":"autopilot","drive_pid":null}}' > "$OPSX_STATE_DIR/dispatch.json"
OPSX_TEST_PANE_CLOSE_FAIL=pane_busy opsx stop stuck --repo "$R" >/dev/null 2>&1 || fail "stop pane 關不掉也要 rc 0"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["a/stuck"];assert d["mode"]=="stopped" and "pane_closed_at" not in d,d' "$OPSX_STATE_DIR/dispatch.json" || fail "pane 關不掉不能記 pane_closed_at"

# ---------- opsx reap：用真的 collect（假 herdr 回 agent list），斷言 herdr 被叫了什麼 ----------
ROOT="$FX/code"; mkdir -p "$ROOT/o/.git" "$ROOT/o/openspec/changes/archive"
O="$(cd "$ROOT/o" && pwd -P)"
mkcard() { # <slug> [額外 inbox 前言行]：活著的卡
  local d="$ROOT/o/openspec/changes/$1"; mkdir -p "$d"
  printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$d/.openspec.yaml"
  printf -- '---\nsource: me\nfound: 2026-11-04\n---\n\n## 一句話\n\n%s\n' "$1" > "$d/inbox.md"
  printf '## 1\n\n- [ ] 1.1 a\n' > "$d/tasks.md"
}
archive() { # <slug>
  local d="$ROOT/o/openspec/changes/archive/2026-11-01-$1"; mkdir -p "$d"
  printf 'schema: opsx\nkind: dev\n' > "$d/.openspec.yaml"; printf '## 一句話\n\n%s\n' "$1" > "$d/inbox.md"
}
agent() { # <pane> <status> <cwd>
  printf '{"agent":"claude","pane_id":"%s","agent_status":"%s","cwd":"%s","foreground_cwd":"%s","terminal_title_stripped":"t-%s"}' "$1" "$2" "$3" "$3" "$1"
}
archive ar; archive ar2; archive p; mkcard st; mkcard q
printf '{"o/ar":{"pane":"w1:p1","mode":"autopilot"},"o/ar2":{"pane":"w1:p8","mode":"autopilot"},"o/st":{"pane":"w1:p3","mode":"stopped"},"o/re":{"pane":"w1:p5","mode":"stopped"},"o/p":{"pane":"w1:pA","mode":"autopilot"},"o/q":{"pane":"w1:pA","mode":"autopilot","via":"p"}}' > "$OPSX_STATE_DIR/dispatch.json"
{ printf '{"id":"cli:agent:list","result":{"agents":['
  agent w1:p1 idle "$O/.claude/worktrees/ar"; printf ','
  agent w1:p8 working "$O/.claude/worktrees/ar2"; printf ','
  agent w1:p3 idle "$O/.claude/worktrees/st"; printf ','
  agent w1:p5 idle /Users/me/notes; printf ','
  agent w1:p7 idle /Users/me/code/rag-demo; printf ','
  agent w1:pA idle "$O/.claude/worktrees/p"
  printf '],"type":"agent_list"}}'; } > "$FX/agents.json"
export HERDR_ENV=1 OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
closed() { grep -c "^pane close $1\$" "$OPSX_FAKE_LOG" || true; }

# 乾跑：只記 DRY，不關、不寫 dispatch.json
: > "$OPSX_FAKE_LOG"; cp "$OPSX_STATE_DIR/dispatch.json" "$FX/dispatch.before"
out="$(opsx reap --root "$ROOT" --dry 2>&1)"; assert_eq "$?" 0 "reap --dry: $out"
case "$out" in *DRY*"w1:p1"*) ;; *) fail "dry 要印 DRY 與 pane：$out" ;; esac
assert_eq "$(grep -c '^pane close' "$OPSX_FAKE_LOG" || true)" 0 "dry 不能關任何 pane"
cmp -s "$OPSX_STATE_DIR/dispatch.json" "$FX/dispatch.before" || fail "dry 不能動 dispatch.json"

# 指定的 pane 不是孤兒：rc 2、訊息含 pane id、不關
: > "$OPSX_FAKE_LOG"
out="$(opsx reap --root "$ROOT" --pane w1:p7 2>&1)"; rc=$?
assert_eq "$rc" 2 "非孤兒要 rc 2: $out"
case "$out" in *w1:p7*) ;; *) fail "訊息要含 pane id：$out" ;; esac
assert_eq "$(grep -c '^pane close' "$OPSX_FAKE_LOG" || true)" 0

# 真的跑：idle 的孤兒關；working 的不關；使用者自己的 pane、pane id 被重用的不關；共用 pane 上還有活卡（q）不關
: > "$OPSX_FAKE_LOG"
out="$(opsx reap --root "$ROOT" 2>&1)"; assert_eq "$?" 0 "reap: $out"
assert_eq "$(closed w1:p1)" 1 "已歸檔 idle 要關"
assert_eq "$(closed w1:p3)" 1 "stopped idle 要關"
assert_eq "$(closed w1:p8)" 0 "working 不關"
assert_eq "$(closed w1:p7)" 0 "不在 opsx worktree 的不關"
assert_eq "$(closed w1:p5)" 0 "pane id 被重用、cwd 不在 opsx worktree 的不關"
assert_eq "$(closed w1:pA)" 0 "共用 pane 上還有活卡 q，不關"
# 留紀錄：dispatch.json 補 reaped_at 條目保留；卡目錄在（st）寫 decisions.tsv；卡目錄不在（已歸檔）寫 reap.log，working 的也記為什麼沒關
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["o/ar"]["reaped_at"] and d["o/st"]["reaped_at"] and "reaped_at" not in d["o/ar2"] and "reaped_at" not in d["o/p"],d' "$OPSX_STATE_DIR/dispatch.json" || fail "reaped_at 只補在關掉的"
assert_grep "w1:p3" "$ROOT/o/openspec/changes/st/decisions.tsv"
assert_grep "w1:p1" "$OPSX_STATE_DIR/reap.log"
assert_grep "w1:p8.*working" "$OPSX_STATE_DIR/reap.log"

# reap.log 是 symlink（symlink-safe-writes）：拒絕、非 0、目標不變
rm -f "$OPSX_STATE_DIR/reap.log"; printf 'keep me\n' > "$FX/victim"; ln -s "$FX/victim" "$OPSX_STATE_DIR/reap.log"
out="$(opsx reap --root "$ROOT" 2>&1)"; rc=$?
[ $rc -ne 0 ] || fail "reap.log 是 symlink 要非 0：$out"
case "$out" in *reap.log*) ;; *) fail "訊息要含 reap.log：$out" ;; esac
assert_eq "$(cat "$FX/victim")" "keep me" "reap.log 不能附加到 symlink 的目標"
rm -f "$OPSX_STATE_DIR/reap.log"

# 共用 pane：q 也歸檔、p 的 pane 還 idle → 關
rm -rf "$ROOT/o/openspec/changes/q"; archive q
: > "$OPSX_FAKE_LOG"
out="$(opsx reap --root "$ROOT" 2>&1)"; assert_eq "$?" 0 "reap 共用 pane: $out"
assert_eq "$(closed w1:pA)" 1 "兩張都結束了，共用 pane 要關"

# pane 已經不在：herdr pane close 失敗視為已完成，rc 0
archive ar3; printf '{"o/ar3":{"pane":"w1:p9","mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
{ printf '{"id":"cli:agent:list","result":{"agents":['; agent w1:p9 idle "$O/.claude/worktrees/ar3"; printf '],"type":"agent_list"}}'; } > "$FX/agents.json"
out="$(OPSX_TEST_PANE_CLOSE_FAIL=pane_not_found opsx reap --root "$ROOT" 2>&1)"; assert_eq "$?" 0 "pane 已不在: $out"
python3 -I -c 'import json,sys;assert json.load(open(sys.argv[1]))["o/ar3"]["reaped_at"]' "$OPSX_STATE_DIR/dispatch.json" || fail "pane 已不在也算 reaped"

# session 條目 o/@g：成員 m5 的 pane 是舊值，靠 via 查到 session 的 pane w1:pG 保護；m5 歸檔後關 pane，記在 session 條目上
mkcard m5
printf '{"o/@g":{"pane":"w1:pG","mode":"autopilot","worktree":"%s/.claude/worktrees/g"},"o/m5":{"pane":"w1:pOld","mode":"autopilot","worktree":"%s/.claude/worktrees/g","feature":"g","via":"@g","herdr_name":"g"}}' "$O" "$O" > "$OPSX_STATE_DIR/dispatch.json"
{ printf '{"id":"cli:agent:list","result":{"agents":['; agent w1:pG idle "$O/.claude/worktrees/g"; printf '],"type":"agent_list"}}'; } > "$FX/agents.json"
: > "$OPSX_FAKE_LOG"
out="$(opsx reap --root "$ROOT" 2>&1)"; assert_eq "$?" 0 "reap session 有活成員: $out"
assert_eq "$(closed w1:pG)" 0 "session pane 上還有活成員 m5，不關"
rm -rf "$ROOT/o/openspec/changes/m5"; archive m5
: > "$OPSX_FAKE_LOG"
out="$(opsx reap --root "$ROOT" 2>&1)"; assert_eq "$?" 0 "reap session 收完: $out"
assert_eq "$(closed w1:pG)" 1 "成員都收完，session pane 要關"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["o/@g"]["reaped_at"] and "reaped_at" not in d["o/m5"],d' "$OPSX_STATE_DIR/dispatch.json" || fail "reaped_at 記在 session 條目"
assert_grep "o/@g w1:pG.*session-done" "$OPSX_STATE_DIR/reap.log"

echo "ok reap"
