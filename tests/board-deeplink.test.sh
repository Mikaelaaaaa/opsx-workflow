#!/usr/bin/env bash
# 看板的單卡 deep link：#card=<repo>/<slug> 開頁後切到卡所在的 tab 並展開抽屜，只處理一次（specs/board-web「單卡 deep link」）。
# 解析與決定寫在網頁的 inline script 裡，這裡用 node 把「card deep link」兩個標記之間切出來，配假的 window 與 UI 動作執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑 deep link 的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "card deep link"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* card deep link start */', END = '/* card deep link end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const {parseHash, deepLinkTarget, readLoadHash, applyDeepLink} =
  new Function(html.slice(s, e) + ';return {parseHash, deepLinkTarget, readLoadHash, applyDeepLink};')();

const fakeWin = (hash, search) => {
  const w = {stored: {}, urls: [],
    location: {hash, search: search || '', pathname: '/'},
    sessionStorage: {setItem(k, v) { w.stored[k] = v; }},
    history: {replaceState(_s, _t, u) { w.urls.push(u); w.location.hash = u.slice(u.indexOf('#')); }}};
  return w;
};

// Scenario token 與 card 一起帶
let w = fakeWin('#token=abc&card=opsx-workflow/tui-keys');
assert.strictEqual(readLoadHash(w), 'opsx-workflow/tui-keys', '解析出 card key');
assert.deepStrictEqual(w.stored, {'opsx-token': 'abc'}, 'token 存進 sessionStorage');
assert.ok(!w.location.hash.includes('token='), '網址列不再含 token：' + w.location.hash);
assert.strictEqual(w.location.hash, '#home', 'inbox 要等 collect 才知道，先放首頁');
// URL 編碼的 repo 名照 open-board 的編法解回來
assert.strictEqual(parseHash('#token=t&card=a%26b%23c/tui-keys').card, 'a&b#c/tui-keys', 'card 要 URL 解碼');
// 只帶 card 也抹成 #home
w = fakeWin('#card=r/x');
assert.strictEqual(readLoadHash(w), 'r/x', '只帶 card');
assert.deepStrictEqual(w.stored, {}, '沒有 token 不寫 sessionStorage');
assert.strictEqual(w.location.hash, '#home', '只帶 card 也換成 #home');

// Scenario 舊 hash 不變
assert.deepStrictEqual(parseHash('#log'), {token: null, card: null, tab: 'log'}, '#log 開紀錄 tab');
assert.deepStrictEqual(parseHash('#inbox'), {token: null, card: null, tab: 'inbox'}, '#inbox 開收件匣');
assert.deepStrictEqual(parseHash('#home'), {token: null, card: null, tab: 'home'}, '#home');
assert.deepStrictEqual(parseHash(''), {token: null, card: null, tab: 'home'}, '沒有 hash 是首頁');
w = fakeWin('#token=abc');
assert.strictEqual(readLoadHash(w), null, '沒有 card');
assert.deepStrictEqual(w.stored, {'opsx-token': 'abc'}, '#token=abc 存 token');
assert.strictEqual(w.location.hash, '#home', '#token=abc 停在 #home');
w = fakeWin('#log');
assert.strictEqual(readLoadHash(w), null, '#log 沒有 card');
assert.deepStrictEqual(w.urls, [], '#log 不改網址');
w = fakeWin('', '?token=q');
readLoadHash(w);
assert.deepStrictEqual(w.stored, {'opsx-token': 'q'}, 'query 的 token 照舊認');
// sessionStorage 不給用時不丟例外
w = fakeWin('#token=abc&card=r/x');
Object.defineProperty(w, 'sessionStorage', {get() { throw new Error('SecurityError'); }});
assert.strictEqual(readLoadHash(w), 'r/x', 'sessionStorage 不給用仍讀出 card');

const cards = [
  {repo: 'opsx-workflow', slug: 'tui-keys', section: '進行中'},
  {repo: 'opsx-workflow', slug: 'idea', section: '收件匣'},
  {repo: 'other', slug: 'tui-keys', section: '收件匣'},
];
assert.deepStrictEqual(deepLinkTarget(cards, 'opsx-workflow/tui-keys'), {tab: 'home', open: 'opsx-workflow/tui-keys'}, '進行中的卡在首頁');
assert.deepStrictEqual(deepLinkTarget(cards, 'opsx-workflow/idea'), {tab: 'inbox', open: 'opsx-workflow/idea'}, '收件匣的卡在 inbox');
assert.deepStrictEqual(deepLinkTarget(cards, 'other/tui-keys'), {tab: 'inbox', open: 'other/tui-keys'}, '同 slug 不同 repo 要分開');
assert.deepStrictEqual(deepLinkTarget(cards, 'nope/x'), {tab: 'home', missing: true}, '找不到');
assert.deepStrictEqual(deepLinkTarget([], 'nope/x'), {tab: 'home', missing: true}, '空 cards 也是找不到');

const fakeUi = (deepLink) => {
  const env = {toasts: [], ui: {tab: 'home', open: null, deepLink}};
  env.showTab = (t) => { env.ui.tab = t; };
  env.openDrawer = (k) => { env.ui.open = k; };
  env.toast = (msg, bad) => { env.toasts.push([msg, bad]); };
  return env;
};

// Scenario 開進行中的卡
let env = fakeUi('opsx-workflow/tui-keys');
applyDeepLink(env, cards);
assert.strictEqual(env.ui.tab, 'home', '進行中：tab home');
assert.strictEqual(env.ui.open, 'opsx-workflow/tui-keys', '進行中：抽屜開那張卡');
assert.deepStrictEqual(env.toasts, [], '找得到不提示');

// Scenario 開收件匣的卡
env = fakeUi('opsx-workflow/idea');
applyDeepLink(env, cards);
assert.strictEqual(env.ui.tab, 'inbox', '收件匣：tab inbox');
assert.strictEqual(env.ui.open, 'opsx-workflow/idea', '收件匣：抽屜開那張卡');

// Scenario 找不到卡
env = fakeUi('nope/x');
env.ui.tab = 'inbox';
applyDeepLink(env, cards);
assert.strictEqual(env.ui.tab, 'home', '找不到：停首頁');
assert.strictEqual(env.ui.open, null, '找不到：抽屜不開');
assert.strictEqual(env.toasts.length, 1, '找不到：提示一次');
assert.strictEqual(env.toasts[0][0], '找不到這張卡', '提示文字');
applyDeepLink(env, cards);
assert.strictEqual(env.toasts.length, 1, '下一輪 collect 不再提示');

// Scenario 只處理一次
env = fakeUi('opsx-workflow/idea');
applyDeepLink(env, cards);
env.ui.open = null; env.ui.tab = 'home';
applyDeepLink(env, cards);
assert.strictEqual(env.ui.open, null, '關掉後下一輪 collect 抽屜維持關閉');
assert.strictEqual(env.ui.tab, 'home', '下一輪 collect 不再切 tab');

// 沒有 card：什麼都不做
env = fakeUi(null);
applyDeepLink(env, cards);
assert.deepStrictEqual([env.ui.tab, env.ui.open, env.toasts.length], ['home', null, 0], '沒有 deep link 不動');
JS

# 接線：開頁用 readLoadHash 把 card 記進 ui.deepLink，成功的 collect 交給 applyDeepLink
node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "deep link 接線"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
assert.ok(/readLoadHash\(window\)/.test(html), '開頁要呼叫 readLoadHash(window)');
const ui = html.slice(html.indexOf('const ui={'), html.indexOf('\n', html.indexOf('const ui={')));
assert.ok(ui.includes('deepLink:'), 'ui 要帶 deepLink：' + ui);
const sc = html.slice(html.indexOf('function showCollect('), html.indexOf('function showCollectError('));
assert.ok(sc.includes('applyDeepLink('), 'showCollect 要呼叫 applyDeepLink：' + sc);
JS
echo ok
