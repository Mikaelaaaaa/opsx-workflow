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
const {pendKey, pendApply, pendSession, pendDone, pendDrop, pendClear, pendBadge, pendNoteBase} =
  new Function(html.slice(s, e) + ';return {pendKey, pendApply, pendSession, pendDone, pendDrop, pendClear, pendBadge, pendNoteBase};')();

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
// collect 已經帶回這條指示（opsx note 寫檔後才開始的 collect）：不再追加暫存列，送出中與已成功都一樣
const N1 = {...N0, notes: [...N0.notes, {at: '2026-11-10T15:00:01+08:00', text: '先跑 lint'}]};
const lint = st => [{id: 13, key: KX, kind: 'note', text: '先跑 lint', at: 'a', base: 0, state: st, doneAt: st === 'done' ? 1 : undefined}];
assert.deepStrictEqual(view(N1, lint('sending')).notes.map(n => n.text), ['舊的', '先跑 lint'], '送出中、collect 已帶回：只有一列');
assert.deepStrictEqual(view(N1, lint('done')).notes.map(n => n.text), ['舊的', '先跑 lint'], '已成功、collect 已帶回：只有一列');
// 同一句話以前就送過一次：按下時已有 1 條（base 1），collect 只帶回舊的那條，暫存列照樣要出現
const old = {...N0, notes: [{at: '2026-11-09T10:00:00+08:00', text: '先跑 lint'}]};
assert.deepStrictEqual(view(old, [{...lint('sending')[0], base: 1}]).notes.map(n => n.sending), [undefined, true], '重複的舊指示不會吃掉新的暫存列');
assert.deepStrictEqual(view({...old, notes: [...old.notes, {at: 'b', text: '先跑 lint'}]}, [{...lint('done')[0], base: 1}]).notes.length, 2, '新的那條回來後不再追加');
// 同一句話連送兩次：第一條已成功、collect 還沒帶回時送第二條，base 要算進第一條的暫存列
const E0 = card({waiting: null, open_gates: [], notes: []});
const e1 = {id: 20, key: KX, kind: 'note', text: '繼續', at: 'a', base: 0, state: 'done', doneAt: 2};
const base2 = pendNoteBase(E0, KX, '繼續', [e1]);
assert.strictEqual(base2, 1, 'base 從疊加後的畫面算，含還沒清掉的第一條');
assert.strictEqual(pendNoteBase(E0, KX, '繼續', []), 0, '沒有暫存項目時就是 collect 的條數');
// 強制 collect 帶回第一條、清掉 e1；第二條還在送出中，畫面要有兩列，第二列是送出中
const E1 = {...E0, notes: [{at: 'x', text: '繼續'}]};
const e2 = {id: 21, key: KX, kind: 'note', text: '繼續', at: 'b', base: base2, state: 'sending'};
assert.deepStrictEqual(view(E1, pendClear([e1, e2], 3)).notes.map(n => n.sending), [undefined, true], '第二條在 POST 進行中仍顯示送出中');

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

# act / refresh 的接線：把送出中、刷新排程、動作接線三段切出來，用假的 POST、collect、render 實際跑交錯順序
node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "act 與 refresh 的接線"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const cut = name => { const s = html.indexOf(`/* ${name} start */`), e = html.indexOf(`/* ${name} end */`);
  if (s < 0 || e < s) throw new Error(`index.html 找不到標記 ${name} start / end`); return html.slice(s, e); };
const {runAct, runRefresh, REFRESH_IDLE} = new Function(cut('送出中') + cut('刷新排程') + cut('動作接線') + ';return {runAct, runRefresh, REFRESH_IDLE};')();

const deferred = () => { let res, rej; const p = new Promise((a, b) => { res = a; rej = b; }); return {p, res, rej}; };
const tick = () => new Promise(r => setImmediate(r));
function mk() {
  const live = {pending: [], seq: 0, rs: REFRESH_IDLE}, ui = {busy: false}, log = [], gets = [];
  const renv = {live, collect: () => { const d = deferred(); gets.push(d); return d.p; },
    show: (j, force) => log.push(['show', force]), fail: e => log.push(['fail', e.message]), schedule: () => log.push(['schedule'])};
  const aenv = {live, ui, render: () => log.push(['render']), toast: (m, bad) => log.push(['toast', !!bad, m]), refresh: f => runRefresh(renv, f)};
  return {live, ui, log, gets, renv, aenv};
}
const P = {key: 'r/x', kind: 'answer', gate: 'g1'};
const states = R => R.live.pending.map(e => e.state);

(async () => {
  // 點擊 → 輪詢 GET 已送出 → POST 成功 → 那個 GET 回來：已成功的項目保留（那份 collect 可能是動作前開始的）
  let R = mk();
  const poll = runRefresh(R.renv, false);
  let post = deferred();
  const a1 = runAct(R.aenv, 'x', () => post.p, P);
  await tick();
  assert.deepStrictEqual(states(R), ['sending'], '送出 POST 前就是送出中');
  assert.ok(R.log.some(l => l[0] === 'render'), '送出中有重畫');
  post.res({ok: true, stdout: ''}); await tick();
  assert.deepStrictEqual(states(R), ['done'], 'POST 成功改 done');
  R.gets[0].res({}); await tick();
  assert.deepStrictEqual(states(R), ['done'], 'POST 成功前送出的 GET 回來：保留');
  assert.strictEqual(R.gets.length, 2, '排隊的強制刷新補跑一輪');
  R.gets[1].res({}); await poll; await a1;
  assert.deepStrictEqual(states(R), [], 'POST 成功後送出的 GET 回來：清掉');
  assert.deepStrictEqual(R.live.rs, REFRESH_IDLE, '刷新回到閒置');
  assert.strictEqual(R.log.filter(l => l[0] === 'schedule').length, 1, '只排一次下一輪輪詢');
  assert.strictEqual(R.ui.busy, false, 'busy 放開');

  // 點擊 → POST 成功 → GET 送出 → 回來：清掉
  R = mk(); post = deferred();
  const a2 = runAct(R.aenv, 'x', () => post.p, P);
  post.res({ok: true}); await tick();
  assert.strictEqual(R.gets.length, 1, 'POST 成功後強制刷新');
  assert.deepStrictEqual(states(R), ['done']);
  R.gets[0].res({}); await a2;
  assert.deepStrictEqual(states(R), [], '之後送出的 GET 回來就清掉');

  // POST 失敗：還原、toast 失敗、不刷新
  R = mk(); post = deferred();
  const a3 = runAct(R.aenv, 'x', () => post.p, P);
  post.rej(new Error('boom')); await a3;
  assert.deepStrictEqual(states(R), [], '失敗移除項目');
  assert.ok(R.log.some(l => l[0] === 'toast' && l[1] === true), '失敗 toast');
  assert.strictEqual(R.gets.length, 0, '失敗不打 collect');
  assert.strictEqual(R.ui.busy, false);

  // busy 時第二個動作不送出、不加送出中，toast 提示（specs/board-web「忙碌時的第二個動作有提示」）
  R = mk(); post = deferred();
  const a4 = runAct(R.aenv, 'x', () => post.p, P);
  let yPosts = 0;
  const yPost = () => { yPosts++; return Promise.resolve({ok: true}); };
  R.log.length = 0;
  await runAct(R.aenv, 'y', yPost, {...P, key: 'r/y'});
  assert.strictEqual(yPosts, 0, 'busy 時不送第二個 POST');
  assert.deepStrictEqual(R.live.pending.map(e => e.key), ['r/x'], 'busy 時不加第二筆');
  assert.deepStrictEqual(R.log, [['toast', true, '上一個動作還在跑，等一下再按']], 'busy 時只 toast 提示：' + JSON.stringify(R.log));
  post.res({ok: true}); await tick(); R.gets[0].res({}); await a4;
  // 上一個結束後照常送出
  const a4b = runAct(R.aenv, 'y', yPost, {...P, key: 'r/y'});
  await tick();
  assert.strictEqual(yPosts, 1, '上一個結束後 POST 送出');
  R.gets[1].res({}); await a4b;

  // POST 成功之後重畫出錯：不回滾、不報失敗、busy 放開
  R = mk(); post = deferred();
  let renders = 0; R.aenv.render = () => { if (++renders === 2) throw new Error('render'); };
  const a5 = runAct(R.aenv, 'x', () => post.p, P);
  post.res({ok: true});
  await a5.catch(() => {});
  assert.deepStrictEqual(states(R), ['done'], 'POST 已成功：項目維持 done');
  assert.ok(!R.log.some(l => l[0] === 'toast' && l[1] === true), '不 toast 失敗');
  assert.strictEqual(R.ui.busy, false);

  // 送出 POST 前畫送出中就出錯：移除項目、toast 失敗、不送 POST
  R = mk();
  R.aenv.render = () => { throw new Error('render'); };
  let posted = false;
  await runAct(R.aenv, 'x', () => { posted = true; return Promise.resolve({ok: true}); }, P).catch(() => {});
  assert.deepStrictEqual(states(R), [], '不留永久的送出中');
  assert.strictEqual(posted, false, '沒有送 POST');
  assert.ok(R.log.some(l => l[0] === 'toast' && l[1] === true), 'toast 失敗');
  assert.strictEqual(R.ui.busy, false);

  // 有排隊的強制刷新時重畫連續出錯：刷新回到閒置並排下一輪，不會卡死
  R = mk();
  R.renv.show = () => { throw new Error('render'); };
  R.renv.fail = () => { throw new Error('render again'); };
  const r1 = runRefresh(R.renv, false);
  await runRefresh(R.renv, true);
  assert.deepStrictEqual(R.live.rs, {inflight: true, pendingForce: true}, '強制刷新排隊');
  R.gets[0].res({});
  await r1.catch(() => {});
  assert.deepStrictEqual(R.live.rs, REFRESH_IDLE, '例外後回到閒置');
  assert.ok(R.log.some(l => l[0] === 'schedule'), '例外後仍排下一輪輪詢');
  // 排隊而沒有自己跑的那次呼叫不排程、不動狀態
  R = mk();
  const r2 = runRefresh(R.renv, false);
  await runRefresh(R.renv, true);
  assert.strictEqual(R.log.filter(l => l[0] === 'schedule').length, 0, '排隊的呼叫不排程');
  R.gets[0].res({}); await tick(); R.gets[1].res({}); await r2;
  assert.strictEqual(R.log.filter(l => l[0] === 'schedule').length, 1);
})().catch(e => { console.error(e); process.exit(1); });
JS

# 五個呼叫點都把送出中的項目交給 act（接線本身由上面的執行型測試驗）
node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "呼叫點帶送出中項目"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const body = name => { const s = html.indexOf(name), e = html.indexOf('\n}', s); if (s < 0) throw new Error('index.html 找不到 ' + name); return html.slice(s, e); };
for (const f of ['function answer(', 'function answerTree(', 'function submitNote(', 'function exploreFirst(', 'function doDispatch(']) {
  assert.ok(/kind:'(answer|note|dispatch)'/.test(body(f)), f + ' 要交給 act 一筆送出中的項目');
}
assert.ok(/base:/.test(body('function submitNote(')), 'submitNote 要記按下時同文字的指示數');
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

# 忙碌時送出併進、捨棄、改等級、指派：不送、輸入全留著（跟貼上送出一樣先查 busy 再動輸入）
node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "忙碌時輸入留著"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const fn = name => { const a = html.indexOf(`function ${name}(`), b = html.indexOf('\n}', a);
  if (a < 0) throw new Error(`index.html 找不到 function ${name}(`); return html.slice(a, b + 2); };
const c = {repo: 'a', slug: 'x', kind: 'dev', path: '/code/a/openspec/changes/x'};
const ui = {busy: true, merge: 'a/x', mergeInto: 'y', drop: 'a/x', dropText: '重複', prio: 'a/x', prioText: '比較急', prioLevel: 'P1'};
const toasts = [], acts = [], closed = [];
const env = {
  ui, data: {cards: [c, {...c, slug: 'y'}]},
  toast: (m, bad) => toasts.push([m, !!bad]),
  act: label => acts.push(label),
  api: {post: () => { throw new Error('忙碌時不該 POST'); }},
  key: k => k.repo + '/' + k.slug, repoTop: () => '/code/a', byKey: () => c,
  mergeCandidates: cards => cards.filter(t => t.slug !== 'x'), mergeBody: () => ({}), dispatchBody: () => ({}),
  closeDispatch: () => closed.push('dispatch'), render: () => {},
  MODEL_BY_KIND: {dev: 'claude-opus-5-5'},
  $: sel => sel === '.prio-level' ? {value: 'P1'} : sel === '#dlg-note' ? {value: '先跑 lint'} : sel.includes('input') ? {value: 'claude'} : null,
};
const names = Object.keys(env);
const src = ['submitMerge', 'submitDrop', 'submitPriority', 'doDispatch'].map(fn).join('\n') + ';let dlgFor="a/x";return {submitMerge, submitDrop, submitPriority, doDispatch};';
const f = new Function(...names, src)(...names.map(k => env[k]));
f.submitMerge(c); f.submitDrop('a/x', '重複'); f.submitPriority(c); f.doDispatch();
assert.deepStrictEqual(acts, [], '忙碌時四個動作都不送：' + acts);
assert.ok(ui.merge === 'a/x' && ui.mergeInto === 'y', '併進目標留著');
assert.ok(ui.drop === 'a/x' && ui.dropText === '重複', '捨棄理由留著');
assert.ok(ui.prio === 'a/x' && ui.prioText === '比較急' && ui.prioLevel === 'P1', '等級與理由留著');
assert.deepStrictEqual(closed, [], '指派對話框沒關');
assert.strictEqual(toasts.length, 4, '每個都有提示：' + JSON.stringify(toasts));
assert.ok(toasts.every(([m, bad]) => bad && m === '上一個動作還在跑，輸入先留著，等一下再送'), JSON.stringify(toasts));
JS
echo ok
