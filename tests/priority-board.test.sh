#!/usr/bin/env bash
# 看板的等級徽章與頂列 milestone（workplan-priority/priority-board，specs/board-web「卡顯示等級」「目前 milestone 還差幾張」）。
# 顯示邏輯寫在網頁的 inline script 裡，這裡用 node 把 priorityBadge 與 milestoneLine 從 index.html 切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑等級徽章測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "等級徽章與 milestone"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'const PRIO_BADGE=', END = '/* ---------- 範圍';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
const {priorityBadge, milestoneLine, PRIO_HINT} = new Function('esc', html.slice(s, e) + ';return {priorityBadge, milestoneLine, PRIO_HINT};')(esc);

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

// 單一 repo：讀 collect 的 progress
const ms = {r: {milestone: '1.0', goal: '能開單出貨', remaining: 2, mergeable: 0, testing: 0, developing: 2, waiting_on_you: 0, not_dispatched: 0, not_dispatched_planned: [], at: '2026-11-11T14:30:00+08:00'}};
const one = milestoneLine(ms, ['r']);
assert.ok(one.includes('1.0 · 能開單出貨 · 還差 2 張'), `頂列要有 milestone：${one}`);
// 範圍是全部：每個有值的 repo 各一段，沒值的不出現
const all = milestoneLine({...ms, s: {milestone: 'v2', goal: '能退貨', remaining: 0}}, ['r', 's', 't']);
assert.ok(all.includes('1.0 · 能開單出貨 · 還差 2 張') && all.includes('v2 · 能退貨 · 還差 0 張'), `每個 repo 各一段：${all}`);
// 範圍外的 repo 不列
assert.ok(!milestoneLine({...ms, s: {milestone: 'v2', goal: '能退貨', remaining: 0}}, ['r']).includes('v2'), '範圍外的 repo 不列');

// 沒有 milestone
assert.strictEqual(milestoneLine({}, ['r']), '');
assert.strictEqual(milestoneLine(ms, ['t']), '');
assert.strictEqual(milestoneLine({r: {milestone: null, goal: null, remaining: 4}}, ['r']), '', 'milestone 為 null 的 repo 不列');
assert.strictEqual(milestoneLine(undefined, ['r']), '', '舊 collect 沒有 progress 欄位');
JS
