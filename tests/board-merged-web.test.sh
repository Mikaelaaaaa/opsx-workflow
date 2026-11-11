#!/usr/bin/env bash
# 看板抽屜的併入項目：列出、escape、拆出來的 POST body、沒有項目不顯示（specs/board-web「抽屜的併入項目段」）。
# 規則寫在網頁的 inline script 裡，這裡用 node 把「併入項目 start」到「併入項目 end」標記之間切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑併入項目的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "併入項目網頁規則"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* 併入項目 start */', END = '/* 併入項目 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0 || e < s) throw new Error(`index.html 找不到標記 ${START} / ${END}`);
const esc = x => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
const repoTop = c => c.path.split('/openspec/changes/')[0];
const posts = [], acts = [];
const api = {post: (action, body) => { posts.push([action, body]); return Promise.resolve({ok: true}); }};
const act = (label, fn) => { acts.push(label); return fn(); };
const {mergedSection, splitOut} = new Function('esc', 'repoTop', 'api', 'act',
  html.slice(s, e) + ';return {mergedSection, splitOut};')(esc, repoTop, api, act);

const card = (merged) => ({repo: 'r', slug: 'x', path: '/code/r/openspec/changes/x', merged});
const items = [
  {id: 'agent-20261111-1040', when: '2026-11-11T10:40:00+08:00', source: 'agent:foo', text: 'hook 漏擋', kind_of_work: 'planned', area: 'hooks'},
  {id: 'me-20261111-1100', when: '2026-11-11T11:00:00+08:00', source: 'me', text: '<b>粗</b>', kind_of_work: 'planned', area: 'hooks'},
];

// 列出併入項目：依序、escape、每項一顆拆出來
const h = mergedSection(card(items));
assert.ok(h.includes('併入項目'), '段標題：' + h);
const i1 = h.indexOf('hook 漏擋'), i2 = h.indexOf('&lt;b&gt;粗&lt;/b&gt;');
assert.ok(i1 >= 0 && i2 > i1, '依 merged 的順序列出：' + h);
assert.ok(!h.includes('<b>粗'), '一句話要 escape：' + h);
assert.ok(h.includes('2026-11-11 10:40') && h.includes('agent:foo') && h.includes('2026-11-11 11:00'), '顯示時間與來源：' + h);
assert.strictEqual((h.match(/data-act="split-out"/g) || []).length, 2, '每項一顆拆出來：' + h);
assert.ok(h.includes('data-id="agent-20261111-1040"') && h.includes('data-id="me-20261111-1100"'), '按鈕帶 id：' + h);
assert.ok(/data-act="split-out"[^>]*>拆出來</.test(h), '按鈕文字是拆出來：' + h);

// 沒有併入項目不顯示
assert.strictEqual(mergedSection(card([])), '', 'merged 是空的不顯示');
assert.strictEqual(mergedSection({repo: 'r', slug: 'x', path: '/code/r/openspec/changes/x'}), '', '沒有 merged 欄位不顯示');

// 按拆出來送出
splitOut(card(items), 'agent-20261111-1040');
assert.deepStrictEqual(posts, [['split-out', {slug: 'x', id: 'agent-20261111-1040', repo: '/code/r'}]], 'POST body');
assert.deepStrictEqual(acts, ['opsx split-out x agent-20261111-1040'], '動作標籤');

// 抽屜：併入項目段接在派工指示段後面；點擊接線把 data-id 交給 splitOut
assert.ok(html.includes('${notesSection(c)}${mergedSection(c)}'), '抽屜放進併入項目段');
assert.ok(html.includes("if(a==='split-out'){splitOut(c,btn.dataset.id);return;}"), '點擊接線');
JS
echo ok
