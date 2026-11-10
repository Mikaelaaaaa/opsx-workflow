#!/usr/bin/env bash
# opsx note：派工指示寫進 inbox.md 的「## 派工指示」段，已派出的卡再送進 agent。
# 驗收：openspec/changes/dispatch-note-cli/specs/dispatch-note/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"

R="$(mk_repo Agentory-AI)"; C="$R/openspec/changes/x"; mk_change "$R" x; mkdir -p "$OPSX_STATE_DIR"
I="$C/inbox.md"
printf -- '---\ntype: 功能\nsource: me\n---\n\n## 一句話\n\n做 x\n' > "$I"
cd "$R"
ENTRY='^- 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9][+-][0-9][0-9]:[0-9][0-9] '
notes() { awk '/^## 派工指示[[:space:]]*$/{f=1;next} /^## /{f=0} f && /^- /' "$I"; }

# --- 段落不存在時建在檔尾，原內容不變；沒派出只寫檔 ---
cp "$I" "$FX/orig.md"
out="$(opsx note x "先跑 lint" 2>&1)"; assert_eq "$?" 0 "note: $out"
head -c "$(wc -c < "$FX/orig.md")" "$I" | cmp -s - "$FX/orig.md" || fail "原有內容要原樣留在前面：$(cat "$I")"
assert_eq "$(grep -c '^## 派工指示$' "$I")" 1 "標題一個"
assert_eq "$(notes | wc -l | tr -d ' ')" 1 "一條"
notes | grep -qE "${ENTRY}先跑 lint\$" || fail "條目格式：$(notes)"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "沒派出不碰 herdr"

# --- 追加在段尾，後面的段不動 ---
printf '\n## 備註\n\n- 別動我\n' >> "$I"
out="$(opsx note x "第二條" 2>&1)"; assert_eq "$?" 0 "note 2: $out"
assert_eq "$(notes | wc -l | tr -d ' ')" 2 "兩條"
notes | sed -n 1p | grep -q ' 先跑 lint$' || fail "第一條原樣：$(notes)"
notes | sed -n 2p | grep -q ' 第二條$' || fail "第二條在後：$(notes)"
awk '/^## 備註/{f=1;next} /^## /{f=0} f' "$I" | grep -q '^- 別動我$' || fail "備註段要原樣：$(cat "$I")"
assert_eq "$(grep -n '^## ' "$I" | tail -1 | cut -d: -f2-)" "## 備註" "備註段仍在派工指示之後"

# --- 多行壓成一行，不長出像 frontmatter 的行 ---
out="$(opsx note x "$(printf '第一行\nsource: evil')" 2>&1)"; assert_eq "$?" 0 "note 多行: $out"
notes | tail -1 | grep -q ' 第一行 source: evil$' || fail "多行要壓成一行：$(notes)"
assert_not_grep '^source: evil' "$I"
# Python 的 splitlines 也認 \v \f U+0085 U+2028 U+2029：寫進去後下一次追加不能把它們切成新行
out="$(opsx note x "$(printf '換行符\xe2\x80\xa8source: sep\x0bfound: vt')" 2>&1)"; assert_eq "$?" 0 "note 其他換行符: $out"
out="$(opsx note x "再一條" 2>&1)"; assert_eq "$?" 0 "note 之後再一條: $out"
assert_not_grep '^source: sep' "$I"; assert_not_grep '^found: vt' "$I"
notes | grep -q ' 換行符 source: sep found: vt$' || fail "其他換行符要壓成空格：$(notes)"

# --- 空白文字拒絕，不動檔 ---
cp "$I" "$FX/before.md"
out="$(opsx note x "   " 2>&1)"; [ $? -ne 0 ] || fail "空白要拒絕: $out"
cmp -s "$I" "$FX/before.md" || fail "空白不該動 inbox.md"
out="$(opsx note x 2>&1)"; [ $? -ne 0 ] || fail "沒給文字要拒絕: $out"

# --- 沒有這張卡 ---
out="$(opsx note zz "先跑 lint" 2>&1)"; [ $? -ne 0 ] || fail "沒有的卡要拒絕"
echo "$out" | grep -q zz || fail "訊息要含 zz: $out"

# --- stopped 的卡當成沒派出 ---
printf '{"Agentory-AI/x":{"mode":"stopped","pane":"p4"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx note x "停了" 2>&1)"; assert_eq "$?" 0 "note stopped: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "stopped 不碰 herdr"

# --- 已派出：送進 agent ---
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx note x "先跑 lint" 2>&1)"; assert_eq "$?" 0 "note dispatched: $out"
assert_grep '^agent prompt x 有新的派工指示，Read inbox.md 的 ## 派工指示$' "$OPSX_FAKE_LOG"

# --- 代管卡送到協調它的 pane，帶 [slug] ---
: > "$OPSX_FAKE_LOG"
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","herdr_name":"p","via":"p"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx note x "先跑 lint" 2>&1)"; assert_eq "$?" 0 "note hosted: $out"
assert_grep '^agent prompt p \[x\] 有新的派工指示，Read inbox.md 的 ## 派工指示$' "$OPSX_FAKE_LOG"

# --- 已交接的卡：拒絕，不寫不送 ---
: > "$OPSX_FAKE_LOG"; cp "$I" "$FX/before.md"
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4","handed_to":["y"],"handed_at":"2026-11-10T12:00:00+08:00"}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx note x "先跑 lint" 2>&1)"; [ $? -ne 0 ] || fail "已交接要拒絕: $out"
echo "$out" | grep -q 'y' || fail "訊息要含交接對象: $out"
cmp -s "$I" "$FX/before.md" || fail "已交接不該寫 inbox.md"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "已交接不碰 herdr"

# --- herdr 送不出去：檔已寫，退出非零並說明 ---
printf '{"Agentory-AI/x":{"mode":"autopilot","pane":"p4"}}' > "$OPSX_STATE_DIR/dispatch.json"
printf 'agent_not_found\n' > "$FX/prompt-err"
n="$(notes | wc -l | tr -d ' ')"
out="$(OPSX_TEST_PROMPT_ERR="$FX/prompt-err" opsx note x "送不出去" 2>&1)"; [ $? -ne 0 ] || fail "herdr 失敗要退出非零: $out"
echo "$out" | grep -q 'inbox.md' || fail "要說 inbox.md 已寫: $out"
assert_eq "$(notes | wc -l | tr -d ' ')" "$((n + 1))" "herdr 失敗時檔仍要寫"
notes | tail -1 | grep -q ' 送不出去$' || fail "最後一條：$(notes)"

# --- --repo 與 -- ---
cd "$FX"
out="$(opsx note x --repo "$R" -- "--開頭的指示" 2>&1)"; assert_eq "$?" 0 "note --repo: $out"
notes | tail -1 | grep -q ' --開頭的指示$' || fail "-- 之後全是文字：$(notes)"

# --- 用法說明有 note ---
opsx --help 2>&1 | grep -q '^  note ' || fail "opsx --help 要列 note"
echo ok
