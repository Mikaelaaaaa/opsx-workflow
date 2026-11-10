#!/usr/bin/env bash
# 看板的送出中畫面：answer、note、dispatch 按下去先畫送出中，成功換正式狀態，失敗還原（specs/board-web「動作送出中的畫面」）。
# 清單、疊加與清除規則寫在網頁的 inline script 裡，這裡用 node 把「送出中」兩個標記之間切出來直接執行；DOM 接線手動驗。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑送出中的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "送出中"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* 送出中 start */', END = '/* 送出中 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const {pendKey, pendApply, pendSession, pendDone, pendDrop, pendClear, pendBadge} =
  new Function(html.slice(s, e) + ';return {pendKey, pendApply, pendSession, pendDone, pendDrop, pendClear, pendBadge};')();

const G1 = {type: '等待決定', gate_id: 'g1', question: '要不要 X', options: ['好', '不要']};
const card = (more) => ({repo: 'r', slug: 'x', section: '待處理', waiting: G1, open_gates: [{id: 'g1', opened_at: null}], notes: [], ...more});
const X = card(), KX = pendKey('r', 'x');
const frozen = JSON.stringify(X);
const view = (c, list) => pendApply(c, pendKey(c.repo, c.slug), list);
const sending = (id, more) => ({id, state: 'sending', ...more});

// 空清單：原樣
assert.strictEqual(view(X, []), X, '空清單不複製也不改');

// 回答送出中：g1 仍顯示、標送出中
let list = [sending(1, {key: KX, kind: 'answer', gate: 'g1'})];
let v = view(X, list);
assert.strictEqual(v.waiting.gate_id, 'g1', '送出中 g1 仍然顯示');
assert.strictEqual(v.waiting.sending, true, '送出中 g1 標 sending（畫成灰、按鈕 disabled）');
assert.deepStrictEqual(v.open_gates, X.open_gates, '送出中 open_gates 不動');
assert.strictEqual(JSON.stringify(X), frozen, '疊加不改 collect 的原始資料');

// 回答成功：下一份 collect 回來前 g1 不顯示
list = pendDone(list, 1, 5);
assert.deepStrictEqual(list, [{id: 1, key: KX, kind: 'answer', gate: 'g1', state: 'done', doneAt: 5}], '成功：改成 done 並記時間');
v = view(X, list);
assert.strictEqual(v.waiting, null, '成功後 g1 不顯示');
assert.deepStrictEqual(v.open_gates, [], '成功後 open_gates 不含 g1');

// 動作前開始的 collect 不清掉正式狀態：GET 在 POST 成功之前送出
assert.strictEqual(pendClear(list, 4), list, 'GET 送出時間早於成功時間：保留');
assert.strictEqual(view(X, pendClear(list, 4)).waiting, null, '舊 collect 回來 g1 仍不顯示');
// 新的 collect 清掉送出中：GET 在 POST 成功之後送出
assert.deepStrictEqual(pendClear(list, 6), [], 'GET 送出時間晚於成功時間：清掉');
assert.strictEqual(view(X, pendClear(list, 6)), X, '清掉後畫面只看 collect');
// 還在送出中的項目，任何 collect 都不清
assert.strictEqual(pendClear([sending(2, {key: KX, kind: 'answer', gate: 'g1'})], 99).length, 1, '送出中的項目不因 collect 清掉');

// 回答失敗還原
list = [sending(3, {key: KX, kind: 'answer', gate: 'g1'})];
list = pendDrop(list, 3);
assert.deepStrictEqual(list, [], '失敗：移除項目');
assert.strictEqual(view(X, list), X, '失敗後回到可以回答的樣子');

// collect 已換到別的 gate 時，成功的 g1 只從 open_gates 拿掉，不碰現在的 waiting
const G2 = {...G1, gate_id: 'g2'};
v = view(card({waiting: G2, open_gates: [{id: 'g1'}, {id: 'g2'}]}), [{id: 4, key: KX, kind: 'answer', gate: 'g1', state: 'done', doneAt: 1}]);
assert.strictEqual(v.waiting.gate_id, 'g2', '別的 gate 照常顯示');
assert.deepStrictEqual(v.open_gates, [{id: 'g2'}], '只拿掉被回答的 gate');
assert.ok(!view(card({waiting: G2}), [sending(5, {key: KX, kind: 'answer', gate: 'g1'})]).waiting.sending, '送出中只標被回答的 gate');

// 回答 session 樹裡子 change 的 gate：key 用主 change 加子 change
const sub = (slug, more) => ({slug, stage: 'apply', worker: null, open_gates: [], waiting: null, ...more});
const S = {repo: 'r', feature: 'fb', mains: [{slug: 'bt', open_gates: [], waiting: null,
  subs: [sub('ct'), sub('as', {open_gates: [{id: 'g2', opened_at: null}], waiting: {...G1, gate_id: 'g2'}})]}]};
const sfrozen = JSON.stringify(S);
const KS = pendKey('r', 'bt', 'as');
assert.notStrictEqual(KS, pendKey('r', 'bt'), '子 change 的 key 跟主 change 不同');
assert.strictEqual(pendSession(S, []), S, '空清單 session 原樣');
let t = pendSession(S, [sending(6, {key: KS, kind: 'answer', gate: 'g2'})]);
assert.strictEqual(t.mains[0].subs[1].waiting.sending, true, '樹裡 as 的 g2 標送出中');
assert.ok(!t.mains[0].subs[0].waiting && !t.mains[0].waiting, '其他行不受影響');
t = pendSession(S, [{id: 6, key: KS, kind: 'answer', gate: 'g2', state: 'done', doneAt: 1}]);
assert.strictEqual(t.mains[0].subs[1].waiting, null, '成功後 g2 不顯示');
assert.deepStrictEqual(t.mains[0].subs[1].open_gates, [], '成功後 open_gates 不含 g2');
assert.strictEqual(pendSession(S, pendDrop([sending(6, {key: KS, kind: 'answer', gate: 'g2'})], 6)), S, '失敗還原');
assert.strictEqual(JSON.stringify(S), sfrozen, '疊加不改 session 原始資料');
// 主 change 那一行用卡的 key：樹上回主 change 的 gate 跟抽屜同一份
const SM = {...S, mains: [{...S.mains[0], open_gates: [{id: 'g3'}], waiting: {...G1, gate_id: 'g3'}}]};
assert.strictEqual(pendSession(SM, [sending(7, {key: pendKey('r', 'bt'), kind: 'answer', gate: 'g3'})]).mains[0].waiting.sending, true, '主 change 的 gate 標送出中');
assert.ok(!pendSession(SM, [sending(7, {key: pendKey('r', 'bt'), kind: 'answer', gate: 'g3'})]).mains[0].subs[1].waiting.sending, '主 change 的項目不套到子 change');

// 指示送出中：清單最後多一列暫存
const N0 = card({waiting: null, open_gates: [], notes: [{at: '2026-11-10T14:00:00+08:00', text: '舊的'}]});
list = [sending(8, {key: KX, kind: 'note', text: '先跑 lint', at: '2026-11-10 15:00:00'})];
v = view(N0, list);
assert.deepStrictEqual(v.notes, [N0.notes[0], {at: '2026-11-10 15:00:00', text: '先跑 lint', sending: true}], '暫存指示加在最後、標送出中');
v = view(N0, pendDone(list, 8, 3));
assert.deepStrictEqual(v.notes[1], {at: '2026-11-10 15:00:00', text: '先跑 lint', sending: false}, '成功後改一般樣式');
assert.strictEqual(view(N0, pendDrop(list, 8)), N0, '失敗後移除');
assert.deepStrictEqual(view(card({notes: undefined}), list).notes.map(n => n.text), ['先跑 lint'], 'collect 沒有 notes 也能加');

// 指派送出中：派工中 → 已派出 → 失敗移除
const R = card({section: '待指派', waiting: null, open_gates: []});
list = [sending(9, {key: KX, kind: 'dispatch'})];
assert.strictEqual(view(R, list).dispatching, 'sending', '標派工中');
assert.ok(pendBadge(view(R, list)).includes('派工中'), '派工中的徽章');
list = pendDone(list, 9, 4);
assert.strictEqual(view(R, list).dispatching, 'done', '成功標已派出');
assert.ok(pendBadge(view(R, list)).includes('已派出'), '已派出的徽章');
assert.strictEqual(pendBadge(R), '', '沒有進行中的指派就沒有徽章');
assert.strictEqual(view(R, pendDrop([sending(9, {key: KX, kind: 'dispatch'})], 9)), R, '失敗移除標記');

// 兩張卡同時送出中；一張失敗不影響另一張；清除只動已成功、時間較早的
const Y = card({slug: 'y'}), KY = pendKey('r', 'y');
list = [sending(10, {key: KX, kind: 'answer', gate: 'g1'}), sending(11, {key: KY, kind: 'answer', gate: 'g1'})];
assert.ok(view(X, list).waiting.sending && view(Y, list).waiting.sending, '兩張都送出中');
list = pendDrop(list, 10);
assert.ok(!view(X, list).waiting.sending, 'x 失敗還原');
assert.strictEqual(view(Y, list).waiting.sending, true, 'y 仍送出中');
list = pendDone(list, 11, 7);
assert.strictEqual(view(Y, list).waiting, null, 'y 成功');
list = [...list, {id: 12, key: KX, kind: 'note', text: 'n', at: 'a', state: 'done', doneAt: 9}];
assert.deepStrictEqual(pendClear(list, 8).map(e => e.id), [12], '只清掉成功時間早於 GET 送出的那筆');
assert.deepStrictEqual(pendDone(list, 99, 1), list, '找不到 id 不改任何項目');
JS

# act() 要在送出 POST 之前畫送出中，成功與失敗各自改清單；refresh() 要在打 collect 前記下送出時間，回來後清掉
node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "act 與 refresh 接上清單"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const body = name => { const s = html.indexOf(name), e = html.indexOf('\n}', s); if (s < 0) throw new Error('index.html 找不到 ' + name); return html.slice(s, e); };
const a = body('async function act(');
assert.ok(a.indexOf('render()') >= 0 && a.indexOf('render()') < a.indexOf('await fn()'), 'act 要在 await fn() 之前重畫：' + a);
assert.ok(a.includes('pendDone(') && a.includes('pendDrop('), 'act 成功改 done、失敗移除：' + a);
const r = body('async function refresh(');
assert.ok(r.includes('pendClear(') && r.indexOf('sentAt') < r.indexOf('api.collect()'), 'refresh 先記 GET 送出時間再打 collect：' + r);
for (const f of ['function answer(', 'function answerTree(', 'function submitNote(', 'function exploreFirst(', 'function doDispatch(']) {
  assert.ok(/kind:'(answer|note|dispatch)'/.test(body(f)), f + ' 要交給 act 一筆送出中的項目');
}
JS

# 暫存指示的樣式（notesSection 在派工指示段）
node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "暫存指示的樣式"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const s = html.indexOf('const esc='), e = html.indexOf('/* 派工指示 end */');
const {notesSection} = new Function(html.slice(s, e) + ';return {notesSection};')();
const c = {repo: 'r', slug: 'x', section: '進行中', open_gates: [], notes: [{at: '2026-11-10T14:00:00+08:00', text: '舊的'}, {at: '2026-11-10 15:00:00', text: '先跑 lint', sending: true}]};
const h = notesSection(c);
assert.ok(/class="note-row sending"[^]*先跑 lint[^]*送出中/.test(h), '暫存指示用 sending 樣式並標送出中：' + h);
assert.ok(!/class="note-row sending"[^]*舊的/.test(h), '一般指示不是暫存樣式：' + h);
assert.ok(!notesSection({...c, notes: [{...c.notes[1], sending: false}]}).includes('送出中'), '成功後不標送出中');
JS
echo ok
