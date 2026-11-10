#!/usr/bin/env bash
# 看板的刷新排程：強制刷新碰上進行中的刷新要補跑一輪，輪詢照舊放棄（specs/board-web「動作後的強制刷新不會被丟掉」）。
# 排程寫在網頁的 inline script 裡，這裡用 node 把「刷新排程」兩個標記之間切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑刷新排程的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "刷新排程"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* 刷新排程 start */', END = '/* 刷新排程 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const {refreshStep, REFRESH_IDLE} = new Function(html.slice(s, e) + ';return {refreshStep, REFRESH_IDLE};')();

const idle = REFRESH_IDLE;
assert.deepStrictEqual(idle, {inflight: false, pendingForce: false}, '初始狀態');

// 閒置時：輪詢與強制都馬上打 collect，只有強制要強制重畫
assert.deepStrictEqual(refreshStep(idle, 'poll'), {st: {inflight: true, pendingForce: false}, fetch: true, force: false}, '閒置時輪詢');
assert.deepStrictEqual(refreshStep(idle, 'force'), {st: {inflight: true, pendingForce: false}, fetch: true, force: true}, '閒置時強制');

// Scenario 強制刷新碰上進行中的刷新：記下來，那一輪回來後再打一次並強制重畫
let r = refreshStep(idle, 'poll');
r = refreshStep(r.st, 'force');
assert.strictEqual(r.fetch, false, '進行中不另外打 collect');
assert.deepStrictEqual(r.st, {inflight: true, pendingForce: true}, '記下待補的強制刷新');
r = refreshStep(r.st, 'done');
assert.deepStrictEqual(r, {st: {inflight: true, pendingForce: false}, fetch: true, force: true}, '回來後補跑一輪強制');
r = refreshStep(r.st, 'done');
assert.deepStrictEqual(r, {st: idle, fetch: false, force: false}, '補跑結束後回到閒置（照常排下一次輪詢）');

// Scenario 多次強制刷新只補一輪
r = refreshStep(idle, 'force');
let fetches = 0;
for (let i = 0; i < 3; i++) { r = refreshStep(r.st, 'force'); fetches += r.fetch; }
assert.strictEqual(fetches, 0, '進行中的三次強制都不另外打');
r = refreshStep(r.st, 'done');
assert.strictEqual(r.fetch, true, '回來後補一次');
r = refreshStep(r.st, 'done');
assert.strictEqual(r.fetch, false, '只補一次');

// Scenario 輪詢碰上進行中的刷新：不打、不補跑
r = refreshStep(idle, 'force');
r = refreshStep(r.st, 'poll');
assert.deepStrictEqual(r, {st: {inflight: true, pendingForce: false}, fetch: false, force: false}, '輪詢被放棄');
r = refreshStep(r.st, 'done');
assert.deepStrictEqual(r, {st: idle, fetch: false, force: false}, '輪詢不會留下補跑');

// 輪詢不會取消已記下的強制
r = refreshStep(refreshStep(refreshStep(idle, 'poll').st, 'force').st, 'poll');
assert.strictEqual(r.st.pendingForce, true, '輪詢不清掉待補的強制');
JS

# refresh() 要照排程函式做，不能自己再判斷 inflight
node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "refresh 照排程函式做"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const s = html.indexOf('async function refresh('), e = html.indexOf('\n}', s);
if (s < 0) throw new Error('index.html 找不到 async function refresh(');
const body = html.slice(s, e);
assert.ok(body.includes("refreshStep(rs,'done')"), 'refresh 每輪結束要交給 refreshStep：' + body);
assert.ok(!/if\(inflight\)return/.test(body), 'refresh 不能遇到 inflight 直接 return：' + body);
JS
echo ok
