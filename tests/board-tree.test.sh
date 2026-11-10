#!/usr/bin/env bash
# session 卡與樹（specs/board-web「session 卡一行」「session 樹」）的純函式部分。
# 函式寫在網頁的 inline script 裡，這裡用 node 把它們從 index.html 切出來直接執行，DOM 接線手動驗。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑 session 樹測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "session 樹"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'function sessionLine', END = 'function rowSession';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const {sessionLine, treeRows, answerBody, homeSect} =
  new Function(html.slice(s, e) + ';return {sessionLine, treeRows, answerBody, homeSect};')();

// 整段 inline script 要能編譯：DOM 接線不在這裡跑，至少不能有語法錯
new Function(html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>')));

const sub = (slug, more) => ({slug, status: 'pending', stage: 'apply', worker: null, open_gates: [], waiting: null, ...more});
const SESSION = {
  repo: 'r', feature: 'fb', section: '進行中', main_done: 1, main_total: 2, sub_done: 5, sub_total: 7,
  current: {slug: 'bt', stage: 'review'},
  mains: [{
    slug: 'bt', pr_status: 'in-progress', stage: 'apply', section: '進行中',
    dispatch: {pane: 'w1:p2', herdr_name: 'fb'}, agent_status: 'working', open_gates: [], waiting: null,
    subs: [
      sub('ct', {worker: 'subagent-1'}),
      sub('as', {stage: 'propose', open_gates: [{id: 'g1', opened_at: null}],
                 waiting: {type: '等待決定', gate_id: 'g1', question: '要不要 X', options: ['第一項', '第二項']}}),
    ],
  }],
};

// session 卡一行
assert.strictEqual(sessionLine(SESSION), 'fb · 主 change 1/2 · 子 change 5/7 · bt review', 'session 一行的文字');
assert.ok(sessionLine({...SESSION, current: null}).endsWith('已合併'), '全部合併：結尾是已合併');
assert.strictEqual(sessionLine({...SESSION, current: {slug: 'bt', stage: null}}),
  'fb · 主 change 1/2 · 子 change 5/7 · bt', '目前站沒有 stage 就只寫 slug');

// 收進 session 的主 change 不單獨出現；session 依自己的 section 放
const cards = [{repo: 'r', slug: 'bt', section: '進行中', session: 'r/fb'}, {repo: 'r', slug: 'solo', section: '進行中'}];
const run = homeSect(cards, [SESSION], '進行中');
assert.deepStrictEqual(run.cards.map(c => c.slug), ['solo'], '帶 session 的卡不單獨畫');
assert.deepStrictEqual(run.sessions.map(x => x.feature), ['fb'], 'session 卡在進行中');
assert.deepStrictEqual(homeSect(cards, [{...SESSION, section: '已完成', current: null}], '已完成').sessions.map(x => x.feature),
  ['fb'], '全部合併的 session 卡在已完成');

// 樹的行
const rows = treeRows(SESSION);
assert.deepStrictEqual(rows.map(r => [r.main, r.sub, r.text]), [
  ['bt', null, 'fb working · apply'],
  ['bt', 'ct', 'subagent-1 · apply'],
  ['bt', 'as', '— · propose · g1 要不要 X'],
], '樹依序三行');
assert.strictEqual(rows[2].waiting.gate_id, 'g1', '有 waiting 的行帶著 waiting，畫回答選項');
const noDispatch = {...SESSION, mains: [{...SESSION.mains[0], dispatch: null, agent_status: null, subs: []}]};
assert.strictEqual(treeRows(noDispatch)[0].text, '— · apply', '主 change 沒派出寫 —');
const unnamed = {...SESSION, mains: [{...SESSION.mains[0], dispatch: {pane: 'w1:p2'}, subs: []}]};
assert.strictEqual(treeRows(unnamed)[0].text, 'bt working · apply', 'dispatch 沒有 herdr_name 用主 change slug');

// 從樹上回子 change 的 gate；主 change 不帶 sub
assert.deepStrictEqual(answerBody('bt', 'as', 'g1', '第一項'), {slug: 'bt', sub: 'as', gate: 'g1', text: '第一項'});
assert.deepStrictEqual(answerBody('bt', null, 'G2', '好'), {slug: 'bt', gate: 'G2', text: '好'});
JS
