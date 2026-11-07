#!/usr/bin/env bash
# 看板紀錄 tab：只畫最新 200 列、載入更多、換篩選回到 200、內容沒變不重寫 #view（specs/board-log「紀錄 tab」）。
# 從 herdr-board/web/index.html 切出「紀錄 tab」那段 inline script，用 node 執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑紀錄 tab 測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "紀錄 tab 案例失敗"
const fs = require('node:fs');
const assert = require('node:assert');

const src = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* ---------- 紀錄 tab', END = '/* ---------- 離開期間 banner';
const a = src.indexOf(START), b = src.indexOf(END);
if (a < 0 || b < 0) throw new Error('index.html 找不到切片標記：' + [a < 0 ? START : '', b < 0 ? END : ''].filter(Boolean).join('、'));
const slice = src.slice(a, b);
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function load(tl) {
  // 跟 index.html 的 ui 字面值一樣沒有 logLimit：初始值要由切片自己設
  const ui = { scope: 'all', ws: null, repo: null, logFilter: 'all' };
  const f = new Function('ui', 'tl', 'tlErr', 'esc', 'inScope',
    slice + ';return {renderLog, setView, logMore, setLogFilter, setScope, LOG_PAGE};');
  return { ui, ...f(ui, tl, '', esc, () => true) };
}
// 切片外的接線：#view 只經 setView 寫；render() 用 setView；兩個範圍選單都走 setScope
{
  assert.ok(!/\$\('#view'\)\.innerHTML\s*=/.test(src), "index.html 不該直接寫 $('#view').innerHTML");
  const r = src.indexOf('function render(){');
  assert.ok(r >= 0, 'index.html 找不到 function render(){');
  assert.ok(src.slice(r, src.indexOf('\n}', r)).includes("setView($('#view'),"), 'render() 要經 setView 寫 #view');
  assert.strictEqual((src.match(/setScope\(/g) || []).length, 3, '範圍選單兩個 handler 都要呼叫 setScope（加上定義共 3 處）');
  assert.ok(!/ui\.scope\s*=\s*'/.test(src.slice(b)), '範圍只能經 setScope 改');
}
// n 列，由新到舊，每天 10 列；偶數列是「你」回的
function events(n) {
  const t0 = Date.parse('2026-11-06T23:00:00+08:00');
  return Array.from({ length: n }, (_, i) => ({
    ts: new Date(t0 - i * 2.4 * 3600e3).toISOString(), repo: 'a', slug: 'x', archived: false,
    who: i % 2 ? 'agent' : '你', tag: '已決定', text: 'row-' + i + '-end', evidence: '', source: 'decisions',
  }));
}
const rows = h => (h.match(/<div class="ev">/g) || []).length;

// 只畫最新 200 列
{
  const t = load({ events: events(450), errors: [] });
  assert.strictEqual(t.LOG_PAGE, 200);
  assert.strictEqual(t.ui.logLimit, 200, '切片要把 ui.logLimit 設成 200');
  const h = t.renderLog();
  assert.strictEqual(rows(h), 200);
  assert.ok(h.includes('row-0-end') && h.includes('row-199-end') && !h.includes('row-200-end'), '應是最新的 200 列');
  assert.ok(h.includes('data-act="log-more"'), '要有載入更多');
  assert.ok(h.includes('還有 250 列'), '要寫還剩幾列');
}
// 載入更多
{
  const t = load({ events: events(450), errors: [] });
  t.logMore(); assert.strictEqual(rows(t.renderLog()), 400);
  t.logMore(); const h = t.renderLog();
  assert.strictEqual(rows(h), 450);
  assert.ok(!h.includes('data-act="log-more"'), '全畫完不該有載入更多');
}
// 不到 200 列沒有載入更多；剛好 200 列也沒有
for (const n of [150, 200]) {
  const t = load({ events: events(n), errors: [] });
  const h = t.renderLog();
  assert.strictEqual(rows(h), n);
  assert.ok(!h.includes('data-act="log-more"'), n + ' 列不該有載入更多');
}
// 篩選後才算 200：450 列裡「你」回的有 225 列
{
  const t = load({ events: events(450), errors: [] });
  t.setLogFilter('you');
  const h = t.renderLog();
  assert.strictEqual(rows(h), 200);
  assert.ok(h.includes('還有 25 列'));
}
// 換篩選回到 200
{
  const t = load({ events: events(450), errors: [] });
  t.logMore(); assert.strictEqual(rows(t.renderLog()), 400);
  t.setLogFilter('you'); t.setLogFilter('all');
  assert.strictEqual(t.ui.logLimit, 200);
  assert.strictEqual(rows(t.renderLog()), 200);
}
// 換範圍回到 200
{
  const t = load({ events: events(450), errors: [] });
  t.logMore(); t.setScope('ws', 'develop', 'a');
  assert.deepStrictEqual([t.ui.scope, t.ui.ws, t.ui.repo, t.ui.logLimit], ['ws', 'develop', 'a', 200]);
  t.logMore(); t.setScope('all', 'develop', null);
  assert.strictEqual(t.ui.logLimit, 200);
}
// 按日分組（既有 Scenario）：11/06 三筆在前，11/05 兩筆在後
{
  const ev = ['2026-11-06T15:00:00+08:00', '2026-11-06T12:00:00+08:00', '2026-11-06T09:00:00+08:00',
    '2026-11-05T15:00:00+08:00', '2026-11-05T09:00:00+08:00']
    .map(ts => ({ ts, repo: 'a', slug: 'x', who: '你', tag: '已決定', text: 't', evidence: '', source: 'decisions' }));
  const h = load({ events: ev, errors: [] }).renderLog();
  const days = [...h.matchAll(/<div class="day">([^<]*)<\/div>/g)].map(m => m[1]);
  assert.deepStrictEqual(days, ['2026-11-06 · 3', '2026-11-05 · 2']);
}
// collect 變動不重寫；切到首頁再切回紀錄會重寫
{
  const t = load({ events: events(10), errors: [] });
  let writes = 0, html = '';
  const el = { get innerHTML() { return html; }, set innerHTML(v) { writes++; html = v; } };
  const log = t.renderLog();
  t.setView(el, log, true); assert.strictEqual(writes, 1);
  t.setView(el, t.renderLog(), true); assert.strictEqual(writes, 1, 'HTML 沒變不該重寫');
  t.setView(el, '<home>', false); assert.strictEqual(writes, 2);
  t.setView(el, '<home>', false); assert.strictEqual(writes, 3, '首頁照舊每次寫');
  t.setView(el, log, true); assert.strictEqual(writes, 4, '切回紀錄要重寫');
  assert.strictEqual(html, log);
  t.logMore(); t.setView(el, t.renderLog(), true); assert.strictEqual(writes, 4, '10 列時載入更多不改畫面');
  t.setLogFilter('you'); t.setView(el, t.renderLog(), true); assert.strictEqual(writes, 5, '換篩選要重寫');
}
console.log('ok');
JS
