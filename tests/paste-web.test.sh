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
const line200 = 'x'.repeat(200), line201 = 'x'.repeat(201), line70k = '{"a":1}'.repeat(10000);
assert.deepStrictEqual(newRequest(line200, [], null), {path: 'new', body: {text: line200}}, '單行 200 字仍走 new');
assert.deepStrictEqual(newRequest(`  ${line200} \n`, [], null), {path: 'new', body: {text: line200}}, '200 字的界線不算前後空白');
assert.deepStrictEqual(newRequest(line201, [], null), {path: 'paste', body: {text: line201, files: []}}, '單行 201 字改走 paste');
assert.deepStrictEqual(newRequest(line70k, [], R), {path: 'paste', body: {text: line70k, files: [], repo: R}}, '單行 70 KB 改走 paste 且帶範圍');
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

# 送出與讀檔的實際接線：切出 toast 到 submitNew 整段，DOM、api、FileReader 都換成假的
node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "paste 送出接線"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'let toastT;', END = '/* 先 explore';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0 || e < s) throw new Error(`index.html 找不到 ${START} … ${END}`);

class Box { constructor() { this.hidden = true; this.value = ''; this.textContent = ''; this.innerHTML = ''; this.classList = {toggle() {}, add() {}, remove() {}}; } focus() {} }
const els = {};
const $ = sel => (els[sel] ||= new Box());
const toasts = [], posts = [];
let postResult = () => ({ok: true, stdout: 'me-1'});
const api = {post: async (path, body) => { posts.push({path, body}); return postResult(); }};
const readers = [];
class FileReader { readAsDataURL(f) { readers.push(() => { this.result = 'data:x;base64,' + f.b64; this.onload(); }); } }
const ui = {busy: false, scope: 'all', repo: null};
const env = {$, api, FileReader, ui, data: {}, refresh: async () => {}, esc: x => x, setTimeout: () => 0, clearTimeout: () => {}};
const names = Object.keys(env);
// toast 是切片裡的 function 宣告，只能在切片裡換掉；訊息收進 globalThis.toasts
globalThis.toasts = toasts;
const k = new Function(...names, html.slice(s, e).replace(START, START + 'toast=m=>{globalThis.toasts.push(m);};') +
  ';return {submitNew, addFiles, closeNew, openNew, get newFiles(){return newFiles;}};');
const m = k(...names.map(n => env[n]));
const flush = () => new Promise(r => setImmediate(r));
(async () => {

// 失敗時輸入留著
m.openNew(); $('#new-text').value = '第一行\n第二行';
postResult = () => { throw new Error('paste 413：太大'); };
m.submitNew(); await flush(); await flush();
assert.strictEqual(posts.length, 1, '有送出');
assert.strictEqual($('#new-text').value, '第一行\n第二行', '失敗時文字留著');
assert.strictEqual($('#newbar').hidden, false, '失敗時輸入區不關');
assert.ok(toasts.some(t => t.includes('失敗')), '失敗有提示');

// 成功才清空
postResult = () => ({ok: true, stdout: 'me-1'});
m.submitNew(); await flush(); await flush();
assert.strictEqual($('#new-text').value, '', '成功後清空');
assert.strictEqual($('#newbar').hidden, true, '成功後關掉');

// 送出期間又打字、又加檔：成功後只清掉送出的那份
let release;
postResult = () => new Promise(r => { release = () => r({ok: true, stdout: 'me-2'}); });
m.openNew(); $('#new-text').value = '先送的';
m.submitNew(); await flush();
$('#new-text').value = '送出後才打的';
const extra = m.addFiles([{name: 'later.png', size: 3, b64: 'BBBB'}]);
readers.shift()(); await extra;
release(); await flush(); await flush();
assert.strictEqual($('#new-text').value, '送出後才打的', '送出期間打的字留著');
assert.deepStrictEqual(m.newFiles.map(f => f.name), ['later.png'], '送出期間加的檔留著');
assert.strictEqual($('#newbar').hidden, false, '還有東西就不關');
m.closeNew();
postResult = () => ({ok: true, stdout: 'me-1'});

// 忙碌時不送也不清
ui.busy = true; posts.length = 0; toasts.length = 0;
m.openNew(); $('#new-text').value = '忙的時候貼的';
m.submitNew(); await flush();
assert.strictEqual(posts.length, 0, '忙碌時不送');
assert.strictEqual($('#new-text').value, '忙的時候貼的', '忙碌時輸入留著');
assert.ok(toasts.length > 0, '忙碌時有提示');
ui.busy = false;

// 讀檔中不准送出
toasts.length = 0;
const pending = m.addFiles([{name: 'shot.png', size: 3, b64: 'AAEC'}]);
m.submitNew(); await flush();
assert.strictEqual(posts.length, 0, '讀檔中不送');
assert.ok(toasts.some(t => t.includes('讀')), '讀檔中有提示');
readers.shift()(); await pending;
assert.deepStrictEqual(m.newFiles.map(f => [f.name, f.data]), [['shot.png', 'AAEC']]);

// 讀到一半關掉，讀完的檔不能跑進下一張
const late = m.addFiles([{name: 'late.png', size: 3, b64: 'AAAA'}]);
m.closeNew();
readers.shift()(); await late;
assert.deepStrictEqual(m.newFiles, [], '關掉之後讀完的檔要丟掉');

// 超過 10 MB 不進清單並提示
toasts.length = 0;
await m.addFiles([{name: 'big.bin', size: 10 * 1024 * 1024 + 1, b64: ''}]);
assert.deepStrictEqual(m.newFiles, [], '大檔不進清單');
assert.ok(toasts.some(t => t.includes('10 MB')), '大檔提示 10 MB');
})().catch(err => { console.error(err); process.exit(1); });
JS
