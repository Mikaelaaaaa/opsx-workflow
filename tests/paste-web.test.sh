#!/usr/bin/env bash
# ＋新增送出時打哪個端點、帶什麼 body，以及 10 MB 上限（specs/board-web「收件匣 tab」）。
# 規則寫在網頁的 inline script 裡，這裡照 banner.test.sh 用 node 把那一段從 index.html 切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑 paste 規則測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "paste 規則"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'const MAX_ATTACH=', END = 'function openNew(';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const {newRequest, splitBySize, MAX_ATTACH} = new Function(html.slice(s, e) + ';return {newRequest, splitBySize, MAX_ATTACH};')();

const R = '/Users/me/code/a';
const shot = {name: 'shot.png', size: 3, data: 'AAEC'};

assert.deepStrictEqual(newRequest('試試看', [], R), {path: 'new', body: {text: '試試看', repo: R}}, '新增帶範圍');
assert.deepStrictEqual(newRequest('試試看', [], null), {path: 'new', body: {text: '試試看'}}, '範圍是全部時不帶 repo');
assert.deepStrictEqual(newRequest('  試試看 \n\n', [], null), {path: 'new', body: {text: '試試看'}}, '單行不帶檔照舊（前後空行不算第二行）');
assert.deepStrictEqual(newRequest('第一行\nhttps://example.com/x', [], null),
  {path: 'paste', body: {text: '第一行\nhttps://example.com/x', files: []}}, '多行貼上');
assert.deepStrictEqual(newRequest('第一行\nhttps://example.com/x', [], R),
  {path: 'paste', body: {text: '第一行\nhttps://example.com/x', files: [], repo: R}}, '多行貼上帶範圍');
assert.deepStrictEqual(newRequest('鍵盤蓋住', [shot], null),
  {path: 'paste', body: {text: '鍵盤蓋住', files: [{name: 'shot.png', data: 'AAEC'}]}}, '拖進檔案：只帶 name 與 data');
assert.deepStrictEqual(newRequest('', [shot], null),
  {path: 'paste', body: {text: '', files: [{name: 'shot.png', data: 'AAEC'}]}}, '只有檔');
assert.strictEqual(newRequest('  \n ', [], R), null, '什麼都沒有就不送');

assert.strictEqual(MAX_ATTACH, 10 * 1024 * 1024);
const exact = {name: 'ok.bin', size: MAX_ATTACH}, big = {name: 'big.bin', size: MAX_ATTACH + 1};
assert.deepStrictEqual(splitBySize([exact, big]), [[exact], [big]], '檔案太大：大於 10 MB 不進清單');
assert.deepStrictEqual(splitBySize([]), [[], []]);

// 輸入區的元件與鍵盤規則：textarea、附檔按鈕（隱藏的多選 file input）、拖放綁在 newbar
assert.match(html, /<textarea id="new-text"/, 'newbar 是多行文字框');
assert.match(html, /<input type="file" id="new-file" multiple hidden>/, '隱藏的多選 file input');
assert.match(html, /data-act="new-attach"/, '附檔按鈕');
assert.match(html, /\$\('#newbar'\)\.addEventListener\('drop'/, '拖放綁在 newbar');
assert.match(html, /readAsDataURL/, '檔案用 FileReader 取 base64');
assert.match(html, /\(e\.ctrlKey\|\|e\.metaKey\)&&e\.key==='Enter'/, 'Ctrl/⌘+Enter 送出');
JS
