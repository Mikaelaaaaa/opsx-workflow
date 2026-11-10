#!/usr/bin/env bash
# 精靈的狀態外觀不受其他元件樣式影響（specs/board-web）。
# 瀏覽器的 cascade 在 node 裡跑不了，這裡守的是它的前提：精靈的狀態 class 不能被 .bot 以外的規則選到。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑精靈測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "精靈"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const escLine = html.match(/^const esc=.*$/m);
if (!escLine) throw new Error('index.html 找不到 const esc=');
const s = html.indexOf('function bot('), e = html.indexOf('\n}\n', s);
if (s < 0 || e < 0) throw new Error('index.html 找不到 function bot(');
const bot = new Function(escLine[0] + '\n' + html.slice(s, e + 2) + ';return bot;')();

const css = html.slice(html.indexOf('<style>') + 7, html.indexOf('</style>'));
const selectors = [...css.matchAll(/([^{}]+)\{/g)]
  .flatMap(m => m[1].split(','))
  .map(x => x.trim())
  .filter(x => x && !x.startsWith('@'));

const cards = {
  ask: {waiting: {type: '等待決定'}},
  wait: {waiting: {type: '可以合併'}},
  work: {waiting: null, agent_status: 'working'},
  sleep: {waiting: null, agent_status: 'idle'},
};
for (const [st, c] of Object.entries(cards)) {
  const svg = bot(c, 30);
  const cls = svg.match(/^<svg class="([^"]+)"/)[1].split(/\s+/);
  assert.strictEqual(cls[0], 'bot', `${st}：第一個 class 是 bot`);
  for (const tok of cls.slice(1)) {
    const re = new RegExp(`\\.${tok}(?![\\w-])`);
    const stray = selectors.filter(sel => re.test(sel) && !sel.startsWith('.bot'));
    assert.deepStrictEqual(stray, [], `${st}：class ${tok} 被 .bot 以外的規則選到`);
  }
}

const ask = bot(cards.ask, 30);
assert.strictEqual((ask.match(/<rect x="\d+" y="(4|54)" width="4" height="6"/g) || []).length, 6, 'ask 有 6 根接腳');
assert.strictEqual((ask.match(/<rect x="(17|35)" y="21" width="12" height="20"/g) || []).length, 2, 'ask 有兩個 ask 眼睛');
assert.ok(ask.includes('class="ring"'), 'ask 有外圈');
JS
