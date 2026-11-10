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

assert.notStrictEqual(cls(card({agent_status: null})), 'sleep', 'null 不能畫成睡著');
assert.strictEqual(cls(card({agent_status: null, dispatch: null})), 'sleep', '沒派出的卡本來就沒有 agent 狀態，不是狀態不明');
assert.strictEqual(cls(card({agent_status: 'idle'})), 'sleep', 'idle 照舊');
assert.strictEqual(cls(card({agent_status: 'unknown'})), 'sleep', 'herdr 的 unknown 照舊');
assert.strictEqual(cls(card({agent_status: 'working'})), 'work');
assert.strictEqual(cls(card({agent_status: null, waiting: {type: '等待決定'}})), 'ask', '待處理優先於狀態不明');

assert.strictEqual(herdrWhy([{source: 'glab', message: 'g'}, {source: 'herdr', message: 'herdr agent list 失敗：socket gone'}]),
  'herdr agent list 失敗：socket gone');
assert.strictEqual(herdrWhy([{source: 'glab', message: 'g'}]), '讀不到 agent 狀態', '沒有 herdr 那條才用固定字');
assert.strictEqual(herdrWhy([]), '讀不到 agent 狀態');
JS
