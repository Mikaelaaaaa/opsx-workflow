#!/usr/bin/env bash
# 看板的併進：目標候選清單、POST body、收件卡與待分類列的按鈕（specs/board-web「併進的目標選單」「送出併進」「待分類沒有併進」）。
# 規則寫在網頁的 inline script 裡，這裡用 node 把「併進 start」到「併進 end」標記之間切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑併進的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "併進網頁規則"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* 併進 start */', END = '/* 併進 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0 || e < s) throw new Error(`index.html 找不到標記 ${START} / ${END}`);
const esc = x => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
const key = c => c.repo + '/' + c.slug;
const repoTop = c => c.path.split('/openspec/changes/')[0];
const ui = {merge: null, mergeInto: ''};
const {mergeCandidates, mergeBody, mergeCtl} = new Function('esc', 'key', 'repoTop', 'ui',
  html.slice(s, e) + ';return {mergeCandidates, mergeBody, mergeCtl};')(esc, key, repoTop, ui);

const card = (repo, slug, section, title) => ({repo, slug, section, title: title || slug, path: `/code/${repo}/openspec/changes/${slug}`});
const x = card('a', 'x', '收件匣'), y = card('a', 'y', '進行中', '<b>同一件事</b>'), z = card('a', 'z', '已完成'), w = card('b', 'w', '收件匣');
const cards = [x, y, z, w];

// 併進的目標選單
assert.deepStrictEqual(mergeCandidates(cards, x).map(c => c.slug), ['y'], '只有同 repo、不在已完成、不是自己的卡');
assert.deepStrictEqual(mergeCandidates([x, z, w], x), [], '沒有候選');

// 送出併進
assert.deepStrictEqual(mergeBody(x, 'y'), {slug: 'x', into: 'y', repo: '/code/a'}, 'POST body');

// 選單關著：一顆併進按鈕
assert.ok(mergeCtl(x, cards).includes('data-act="merge-open"') && mergeCtl(x, cards).includes('併進'), '關著時是併進按鈕');

// 選單開著、還沒選：列出 slug 與一句話（escape），送出不可按
ui.merge = 'a/x'; ui.mergeInto = '';
let h = mergeCtl(x, cards);
assert.ok(h.includes('value="y"') && h.includes('&lt;b&gt;同一件事&lt;/b&gt;') && !h.includes('<b>同一件事'), '候選顯示 slug 與一句話：' + h);
assert.ok(!h.includes('value="z"') && !h.includes('value="w"') && !h.includes('value="x"'), '不列 x z w：' + h);
assert.ok(/data-act="merge-go"[^>]*disabled/.test(h), '沒選目標時送出不可按：' + h);

// 選了目標：重畫保留已選，送出可按
ui.mergeInto = 'y';
h = mergeCtl(x, cards);
assert.ok(/value="y" selected/.test(h), '重畫保留已選的目標：' + h);
assert.ok(!/data-act="merge-go"[^>]*disabled/.test(h), '選了目標可送出：' + h);

// 已選的目標不在候選裡了（collect 重拉後它被完成）：不可送出
ui.mergeInto = 'z';
assert.ok(/data-act="merge-go"[^>]*disabled/.test(mergeCtl(x, cards)), '已選的目標不在候選裡時不可送出');

// 沒有候選：只顯示「沒有可併進的卡」，不可送出
ui.mergeInto = '';
h = mergeCtl(x, [x, z, w]);
assert.ok(h.includes('沒有可併進的卡') && /data-act="merge-go"[^>]*disabled/.test(h), '沒有候選：' + h);

// 別張卡的選單開著時，這張還是按鈕
ui.merge = 'b/w';
assert.ok(mergeCtl(x, cards).includes('data-act="merge-open"'), '只有開著的那張換成選單');

// 待分類沒有併進：收件卡列放 mergeCtl，待分類列沒有
const fn = name => { const a = html.indexOf(`function ${name}(`), b = html.indexOf('\n}', a);
  if (a < 0) throw new Error(`index.html 找不到 function ${name}(`); return html.slice(a, b); };
assert.ok(fn('rowInbox').includes('mergeCtl(c,data.cards)'), '收件卡列有併進');
assert.ok(!fn('rowUnfiled').includes('mergeCtl') && !fn('rowUnfiled').includes('併進'), '待分類列沒有併進');
JS
echo ok
