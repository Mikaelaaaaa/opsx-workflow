#!/usr/bin/env bash
# 看板的派工指示：指派對話框的 body、抽屜的派工指示段、追加的 body（specs/board-web「指派對話框的指示欄」「抽屜的派工指示段」）。
# 規則寫在網頁的 inline script 裡，這裡用 node 把 esc 到「派工指示 end」標記之間切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑派工指示的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "派工指示網頁規則"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'const esc=', END = '/* 派工指示 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const {dispatchBody, noteBody, notesSection} =
  new Function(html.slice(s, e) + ';return {dispatchBody, noteBody, notesSection};')();

const card = (more) => ({repo: 'r', slug: 'x', path: '/code/r/openspec/changes/x', section: '進行中',
                         open_gates: [], notes: [], ...more});
const picked = {agent: 'claude', model: 'claude-opus-5-5', mode: 'autopilot', kind: 'dev'};

// 指派對話框的指示欄
assert.deepStrictEqual(dispatchBody(card(), {...picked, note: ' 先跑 lint '}),
  {slug: 'x', ...picked, repo: '/code/r', note: '先跑 lint'}, '填了指示');
assert.deepStrictEqual(dispatchBody(card(), {...picked, note: '   '}),
  {slug: 'x', ...picked, repo: '/code/r'}, '沒填指示：body 沒有 note');
assert.ok(!('note' in dispatchBody(card(), {...picked, note: ''})), '空字串也不帶 note');

// 追加的 body
assert.deepStrictEqual(noteBody(card(), '補跑 e2e'), {slug: 'x', text: '補跑 e2e', repo: '/code/r'}, '追加 body');

// 抽屜的派工指示段
const notes = [{at: '2026-11-10T14:00:00+08:00', text: '先跑 lint'}, {at: '2026-11-10T15:00:00+08:00', text: '<b>不要動</b>'}];
const h = notesSection(card({notes}));
const i1 = h.indexOf('先跑 lint'), i2 = h.indexOf('&lt;b&gt;不要動&lt;/b&gt;');
assert.ok(i1 >= 0 && i2 > i1, '依序列出、舊的在上：' + h);
assert.ok(!h.includes('<b>不要動'), '指示文字要 escape：' + h);
assert.ok(h.includes('2026-11-10 14:00'), '顯示時間：' + h);
assert.ok(h.includes('id="note-add"'), '沒有 gate 時可以追加：' + h);
assert.ok(notesSection(card()).includes('id="note-add"'), 'notes 空的也給追加輸入');

const gated = notesSection(card({notes, open_gates: [{id: 'g1', opened_at: null}]}));
assert.ok(gated.includes('先跑 lint') && !gated.includes('note-add'), '有 gate 時列出但不給追加：' + gated);
assert.strictEqual(notesSection(card({open_gates: [{id: 'g1', opened_at: null}]})), '', '有 gate 又沒有指示就不顯示這段');

const done = notesSection(card({notes: notes.slice(0, 1), section: '已完成'}));
assert.ok(done.includes('先跑 lint') && !done.includes('note-add'), '已完成的卡不給追加：' + done);
assert.strictEqual(notesSection(card({section: '已完成'})), '', '已完成又沒有指示就不顯示這段');
JS

# opsx note 寫了 inbox.md 但送不進 pane 時退出非零；看板要認得這句並清掉輸入框，否則重送會重複寫同一條
node - "$OPSX_ROOT/herdr-board/web/index.html" "$OPSX_ROOT/bin/lib/note.sh" <<'JS' || fail "已寫入的失敗要清輸入框"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8'), sh = fs.readFileSync(process.argv[3], 'utf8');
const MARK = 'inbox.md 已寫';
assert.ok(sh.includes(`die "note: ${MARK}`), `note.sh 送 pane 失敗的訊息要以「note: ${MARK}」開頭`);
const s = html.indexOf('function submitNote('), e = html.indexOf('\n}', s);
if (s < 0) throw new Error('index.html 找不到 function submitNote(');
assert.ok(html.slice(s, e).includes(MARK), `submitNote 要在錯誤訊息含「${MARK}」時清掉輸入框`);
JS
echo ok
