#!/usr/bin/env bash
# 看板的等級徽章與首頁進度列（workplan-priority/priority-board「卡顯示等級」，progress-dashboard/board-web「首頁進度列」「點進度數字篩卡」）。
# 顯示邏輯寫在網頁的 inline script 裡，這裡用 node 把 priorityBadge 與進度列的函式從 index.html 切出來直接執行。
# 進度行的 HH:MM 是本地時間，固定 TZ 讓預期字串（+08:00）在每台機器上都一樣。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑等級徽章測試"

TZ=Asia/Taipei node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "等級徽章與進度列"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'const PRIO_BADGE=', END = '/* ---------- 範圍';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
// 進度行的時間用紀錄 tab 那段的 hhmm，一起切進來
const h0 = html.indexOf('const hhmm=');
if (h0 < 0) throw new Error('index.html 找不到 const hhmm=');
const hhmmSrc = html.slice(h0, html.indexOf('\n', h0));
const {priorityBadge, progressLine, toggleProgressClass, byProgressClass, progressFilterMark, notDispatchedNames, progressSect, counterTail, PRIO_HINT} = new Function('esc', hhmmSrc + html.slice(s, e) + ';return {priorityBadge, progressLine, toggleProgressClass, byProgressClass, progressFilterMark, notDispatchedNames, progressSect, counterTail, PRIO_HINT};')(esc);

// 改等級的提示：等級只排還沒派出去的卡，在跑的卡不受影響
assert.ok(PRIO_HINT.includes('還沒派出去') && PRIO_HINT.includes('不會') && PRIO_HINT.includes('被停'), `提示文字：${PRIO_HINT}`);
const ctl = html.slice(html.indexOf('function prioCtl'), html.indexOf('function prioCtl') + 1200);
assert.ok((ctl.match(/PRIO_HINT/g) || []).length >= 2, `改等級按鈕與編輯列都要帶提示：${ctl}`);

// 徽章與理由
const p0 = {repo: 'r', slug: 'a', priority: {level: 'P0', reason: 'P0：security（附證據）', overridden: false}};
const row = priorityBadge(p0);
assert.match(row, /class="badge[^"]*"[^>]*>P0</, `卡片要有 P0 徽章：${row}`);
assert.ok(!row.includes('改'), `沒覆寫不標「改」：${row}`);
assert.ok(priorityBadge(p0, true).includes('P0：security（附證據）'), `展開區要有理由：${priorityBadge(p0, true)}`);
assert.ok(!row.includes('prio-why'), `列上理由只在 title，展開才顯示：${row}`);

// 覆寫標記
const over = {repo: 'r', slug: 'b', priority: {level: 'P1', reason: 'P1：使用者：等客戶', overridden: true}};
assert.match(priorityBadge(over), />P1<.*>改</, `覆寫的徽章旁有「改」：${priorityBadge(over)}`);

// 沒有等級
assert.strictEqual(priorityBadge({repo: 'r', slug: 'c', priority: null}), '');
assert.strictEqual(priorityBadge({repo: 'r', slug: 'c', priority: null}, true), '');

// 理由跳脫
assert.ok(!priorityBadge({priority: {level: 'P2', reason: '<b>x</b>', overridden: false}}, true).includes('<b>x'), '理由要跳脫');

// 進度列（progress-dashboard/board-web「首頁進度列」）。預期字串與 TUI 的 progress_text 共用，兩邊逐字相同
const text = h => h.replace(/<[^>]*>/g, '');
const lines = h => h.split('<span class="ms"').slice(1).map(l => text('<span class="ms"' + l));
const p = {milestone: '1.0', goal: '能開單出貨', remaining: 5, mergeable: 1, testing: 1, developing: 1, waiting_on_you: 1, not_dispatched: 1, not_dispatched_planned: ['web-x'], at: '2026-11-11T14:30:00+08:00'};
const one = progressLine({r: p}, ['r']);
assert.deepStrictEqual(lines(one), ['進度 14:30 · 1.0：剩 5 張 · 可合併 1 · 測試中 1 · 開發中 1 · 等你 1 · 還沒派 1'], `有 milestone 的進度行：${one}`);
assert.ok(one.includes('title="能開單出貨"'), `goal 放進 milestone 名的 title：${one}`);
for (const k of ['mergeable', 'testing', 'developing', 'waiting_on_you', 'not_dispatched'])
  assert.match(one, new RegExp(`<button class="link[^"]*" data-act="progress-filter" data-class="${k}"`), `${k} 的數字可點：${one}`);

// 沒有 milestone
const none = lines(progressLine({r: {...p, milestone: null, goal: null, remaining: 4}}, ['r']));
assert.deepStrictEqual(none, ['進度 14:30 · 進行中 4 張 · 可合併 1 · 測試中 1 · 開發中 1 · 等你 1 · 還沒派 1'], `沒有 milestone 的進度行：${none}`);
assert.ok(!none[0].includes('剩'));

// 範圍是全部：有值的 repo 各一行，行首 repo 名
const all = lines(progressLine({r: p, s: {...p, milestone: 'v2'}}, ['r', 's', 't']));
assert.strictEqual(all.length, 2, `兩行：${all}`);
assert.ok(all[0].startsWith('r 進度 14:30 · 1.0：') && all[1].startsWith('s 進度 14:30 · v2：'), `行首 repo 名：${all}`);
// 範圍內只剩一個有值的 repo：不加 repo 名
assert.ok(lines(progressLine({r: p, s: p}, ['r']))[0].startsWith('進度 '), '單一 repo 不加 repo 名');

// collect 沒有 progress、範圍內的 repo 都沒有值
assert.strictEqual(progressLine(undefined, ['r']), '', '舊 collect 沒有 progress 欄位');
assert.strictEqual(progressLine({}, ['r']), '');
assert.strictEqual(progressLine({r: p}, ['t']), '');

// 頂列不再有還差幾張；舊的 milestoneLine 已移除
assert.ok(!text(one).includes('還差'), '進度行不含還差');
assert.ok(!html.includes('milestoneLine') && !html.includes('還差'), 'index.html 不再畫還差幾張');
assert.ok(html.includes("$('#milestones').innerHTML=progressLine(data.progress,"), '頂列改呼叫 progressLine');

// 跳脫
const bad = progressLine({'<r>': {...p, milestone: '<b>m</b>', goal: '"g"'}, s: p}, ['<r>', 's']);
assert.ok(!bad.includes('<b>m') && !bad.includes('<r>') && !bad.includes('"g"'), `字串要跳脫：${bad}`);

// 等你非 0 用警示色，0 不用
const wait = n => progressLine({r: {...p, waiting_on_you: n}}, ['r']).match(/<button[^>]*data-class="waiting_on_you"[^>]*>/)[0];
assert.ok(wait(2).includes('badge warn'), `等你 2 要警示色：${wait(2)}`);
assert.ok(!wait(0).includes('warn'), `等你 0 不要警示色：${wait(0)}`);

// 點數字篩卡（board-web「點進度數字篩卡」）
const cards = [{slug: 'a', progress_class: 'mergeable'}, {slug: 'b', progress_class: 'testing'}, {slug: 'c', progress_class: null}];
let cls = toggleProgressClass(null, 'mergeable');
assert.strictEqual(cls, 'mergeable');
assert.deepStrictEqual(byProgressClass(cards, cls).map(c => c.slug), ['a'], '只剩 mergeable');
const mark = progressFilterMark(cls);
assert.ok(text(mark).includes('篩選：可合併') && mark.includes('data-act="progress-filter" data-class="mergeable"'), `篩選標記可點掉：${mark}`);
// 換一類直接切過去
assert.strictEqual(toggleProgressClass('mergeable', 'testing'), 'testing');
// 再點一次取消
cls = toggleProgressClass(cls, 'mergeable');
assert.strictEqual(cls, null);
assert.deepStrictEqual(byProgressClass(cards, cls).map(c => c.slug), ['a', 'b', 'c'], '取消後三張都回來');
assert.strictEqual(progressFilterMark(cls), '', '取消後沒有篩選標記');

// 篩還沒派：列出範圍內各 repo 還沒建殼的項目名
assert.deepStrictEqual(notDispatchedNames({r: p, s: {...p, not_dispatched_planned: ['s-y']}}, ['r']), ['web-x']);
assert.deepStrictEqual(notDispatchedNames({r: p, s: {...p, not_dispatched_planned: ['s-y']}}, ['r', 's', 't']), ['web-x', 's-y']);
assert.deepStrictEqual(notDispatchedNames(undefined, ['r']), []);
assert.ok(html.includes("pc==='not_dispatched'?notDispatchedNames(data.progress,scopeRepos())"), '篩還沒派時首頁畫還沒建殼的項目');
assert.ok(html.includes("a==='progress-filter'){ui.progressClass=toggleProgressClass(ui.progressClass,btn.dataset.class)"), '點數字切換篩選');

// 篩選中各區的卡：收進 session 的主 change 卡也要出現（不篩時由 session 列代表），收件匣裡符合的卡也要畫
const home = [
  {slug: 'run', section: '進行中', progress_class: 'developing'},
  {slug: 'in-session', section: '進行中', progress_class: 'developing', session: 'r/feat'},
  {slug: 'other', section: '進行中', progress_class: 'testing'},
  {slug: 'ready', section: '待指派', progress_class: 'not_dispatched'},
  {slug: 'fresh', section: '收件匣', progress_class: 'not_dispatched'},
];
assert.deepStrictEqual(progressSect(home, 'developing', '進行中').map(c => c.slug), ['run', 'in-session'], '收進 session 的卡篩選中要出現');
assert.deepStrictEqual(progressSect(home, 'not_dispatched', '待指派').map(c => c.slug), ['ready']);
assert.deepStrictEqual(progressSect(home, 'not_dispatched', '收件匣').map(c => c.slug), ['fresh'], '收件匣裡還沒派的卡要畫');
assert.ok(html.includes("pc?{sessions:[],cards:progressSect(cards,pc,name)}:homeSect(cards,"), '首頁各區篩選中走 progressSect');
assert.ok(html.includes("progressSect(cards,pc,'收件匣')"), '篩選中首頁多畫收件匣裡符合的卡');

// 篩選標記接到 counter
assert.ok(text(counterTail('mergeable')).includes('篩選：可合併 ×'), `有篩選時 counter 帶標記：${counterTail('mergeable')}`);
assert.strictEqual(counterTail(null), '', '取消後 counter 沒有標記');
assert.ok(html.includes("counterHtml(data.cards,data.sessions,inScope)+counterTail(ui.progressClass)"), 'render 把標記接到 counter');
JS
