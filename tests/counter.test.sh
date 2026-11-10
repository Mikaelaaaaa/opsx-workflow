#!/usr/bin/env bash
# 首頁頂列的待處理數（specs/board-web「頂列待處理數涵蓋全部範圍」）。
# 組字寫在網頁的 inline script 裡，這裡用 node 把 counterHtml 從 index.html 切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑頂列計數測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "頂列計數"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'function counterHtml', END = '/* ---------- 精靈';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const counterHtml = new Function(html.slice(s, e) + ';return counterHtml;')();

const card = (repo, section) => ({repo, slug: repo + '-x', section});
const inW1 = c => c.repo === 'a';
const all = () => true;
const cards = [card('a', '待處理'), card('b', '待處理'), card('b', '待處理'), card('a', '進行中')];

const scoped = counterHtml(cards, inW1);
assert.strictEqual(scoped,
  '待處理 <b>1</b> · <button class="link" data-act="scope-all">全部 <b>3</b></button>',
  '範圍視圖顯示全部的待處理數');
assert.ok(!scoped.includes('範圍外'), `文字不含「範圍外」：${scoped}`);

assert.strictEqual(counterHtml([card('b', '待處理')], inW1),
  '<span class="faint">無待處理</span> · <button class="link" data-act="scope-all">全部 <b>1</b></button>',
  '範圍內是零時也顯示全部的待處理數');

assert.strictEqual(counterHtml([card('a', '待處理'), card('b', '進行中')], inW1),
  '待處理 <b>1</b>', '範圍內外一樣多時計數不變');

assert.strictEqual(counterHtml(cards, all), '待處理 <b>3</b>', '全部範圍的計數不變');
assert.strictEqual(counterHtml([], all), '<span class="faint">無待處理</span>', '沒有卡');

// 切片外的接線：render() 經 counterHtml 寫頂列；「全部 N」的 data-act 在 click handler 裡轉按頂列「全部」鈕
const r = html.indexOf('function render(){');
assert.ok(r >= 0, 'index.html 找不到 function render(){');
assert.ok(html.slice(r, html.indexOf('\n}', r)).includes("$('#counter').innerHTML=counterHtml(data.cards,inScope)"),
  'render() 要經 counterHtml 寫頂列計數');
const act = /data-act="([^"]+)"/.exec(scoped)[1];
assert.ok(html.includes(`if(a==='${act}'){$('#scope-all').click();`),
  `click handler 要處理 data-act="${act}"，並轉按頂列「全部」鈕`);
JS
