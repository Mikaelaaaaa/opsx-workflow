#!/usr/bin/env bash
# 看板精靈的「狀態不明」（specs/board-web「agent 狀態不明的呈現」）。
# 規則寫在網頁的 inline script 裡，這裡用 node 把 herdrWhy 與 bot 從 index.html 切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑精靈測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "精靈狀態不明"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'function herdrWhy', END = '/* ---------- 列 ---------- */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const esc = (x) => String(x);
const {herdrWhy, bot} = new Function('esc', html.slice(s, e) + ';return {herdrWhy, bot};')(esc);

const card = (more) => ({dispatch: {agent: 'claude'}, waiting: null, agent_status: null, ...more});
const cls = (c) => /<svg class="bot ([a-z-]+)"/.exec(bot(c, 30))[1];

assert.strictEqual(cls(card({agent_status: null})), 'bot-unsure', 'null 不能畫成睡著');
assert.strictEqual(cls(card({agent_status: null, dispatch: null})), 'bot-sleep', '沒派出的卡本來就沒有 agent 狀態，不是狀態不明');
assert.strictEqual(cls(card({agent_status: 'idle'})), 'bot-sleep', 'idle 照舊');
assert.strictEqual(cls(card({agent_status: 'unknown'})), 'bot-sleep', 'herdr 的 unknown 照舊');
assert.strictEqual(cls(card({agent_status: 'working'})), 'bot-work');
assert.strictEqual(cls(card({agent_status: null, waiting: {type: '等待決定'}})), 'bot-ask', '待處理優先於狀態不明');

assert.strictEqual(herdrWhy([{source: 'glab', message: 'g'}, {source: 'herdr', message: 'herdr agent list 失敗：socket gone'}]),
  'herdr agent list 失敗：socket gone');
assert.strictEqual(herdrWhy([{source: 'glab', message: 'g'}]), '讀不到 agent 狀態', '沒有 herdr 那條才用固定字');
assert.strictEqual(herdrWhy([]), '讀不到 agent 狀態');

// 列上的 herdr 標記 title 要真的取自 data.errors（不是只有 herdrWhy 會算）
const RS = 'function rowRunning', RE = 'function rowReady';
const rs = html.indexOf(RS), re = html.indexOf(RE);
if (rs < 0 || re < rs) throw new Error(`index.html 找不到 ${RS} 到 ${RE} 的範圍`);
const row = (data, c) => new Function('esc', 'bot', 'herdrWhy', 'priorityBadge', 'data', 'ui', 'key', 'since', 'PHASE_LABEL', 'COND',
  html.slice(rs, re) + ';return rowRunning;')(esc, bot, herdrWhy, () => '', data, {sel: null}, () => 'k', () => '1m', {}, [])(c);
const running = card({title: 't', repo: 'r', stage: 'apply', status: null, mr: null, agent_status: null});
const why = 'herdr agent list 失敗：socket gone';
assert.ok(row({errors: [{source: 'herdr', message: why}]}, running).includes(`title="${why}"`), 'title 要帶 errors 的 herdr 原文');
assert.ok(row({errors: []}, running).includes('title="讀不到 agent 狀態"'), '沒有 herdr 那條才用固定字');
JS
