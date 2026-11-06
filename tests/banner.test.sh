#!/usr/bin/env bash
# 離開期間 banner 的列入／排除規則（specs/board-log「離開期間 banner」）。
# 規則寫在網頁的 inline script 裡，這裡用 node 把 after 與 bannerItems 從 index.html 切出來直接執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑 banner 規則測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "banner 規則"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = 'const after=', END = 'function renderBanner';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0) throw new Error(`index.html 找不到標記 ${START}`);
if (e < s) throw new Error(`index.html 找不到 ${START} 之後的標記 ${END}`);
const bannerItems = new Function(html.slice(s, e) + ';return bannerItems;')();

const LS = '2026-11-06T10:00:00+08:00';
const T = '2026-11-06T11:00:00+08:00';
const BEFORE = '2026-11-06T09:00:00+08:00';
const ev = (who, tag, text) => ({ts: T, source: 'decisions', repo: 'r', slug: 'x', who, tag, text});
const card = (more) => ({repo: 'r', slug: 'x', section: '進行中', open_gates: [], mr: null,
                         dispatch: null, agent_status: null, ...more});
const check = (name, events, cards, want) =>
  assert.deepStrictEqual(bannerItems(events, cards, LS), want, name);

check('替你做的決定進 banner', [ev('claude', '替你決定', '選 B')], [],
  [{key: 'r/x', text: 'x：claude 替你決定「選 B」'}]);
check('你自己的動作不進 banner', [ev('你', '已指派', 'claude'), ev('你', '已允許', 'push')], [], []);
check('你自己的合併與決定不進 banner', [ev('你', '已合併', 'abc'), ev('你', '替你決定', '選 B')], [], []);
check('空同步不進 banner', [{ts: T, source: 'sync', new: 0, evidence: 'debt'}], [], []);
check('有新卡的同步進 banner', [{ts: T, source: 'sync', new: 2, evidence: 'debt'}], [],
  [{text: '同步 debt：2 張新卡'}]);
check('自動派出進 banner', [ev('系統', '已指派', 'claude')], [],
  [{key: 'r/x', text: 'x 自動派出：claude'}]);
check('不是系統的已指派不進 banner', [ev('claude', '已指派', 'codex')], [], []);
check('last-seen 之前的事不進 banner', [{...ev('claude', '替你決定', '選 B'), ts: BEFORE}], [], []);
check('新開的 gate',
  [], [card({open_gates: [{id: 'G0', opened_at: BEFORE}, {id: 'G1', opened_at: T}]})],
  [{key: 'r/x', text: 'x 開了 gate G1'}]);
check('新開的 MR', [], [card({mr: {created_at: T, merged_at: null}})],
  [{key: 'r/x', text: 'x 開了 MR'}]);
check('合併只列一次',
  [ev('系統', '已合併', 'abc')], [card({mr: {created_at: BEFORE, merged_at: T}})],
  [{key: 'r/x', text: 'x 已合併'}]);
check('只有 mr.merged_at 也列合併', [], [card({mr: {created_at: BEFORE, merged_at: T}})],
  [{key: 'r/x', text: 'x 已合併'}]);
check('blocked 不帶時間', [], [card({dispatch: {pane: 'w1:p2'}, agent_status: 'blocked'})],
  [{key: 'r/x', now: true, text: 'x 的 agent 卡在終端機'}]);
check('失聯的 agent', [], [card({dispatch: {pane: 'w1:p2'}, agent_status: 'unknown'})],
  [{key: 'r/x', now: true, text: 'x 的 agent 不在 herdr 裡（停了或掛了）'}]);
check('已完成的卡不列現在',
  [], [card({section: '已完成', dispatch: {pane: 'w1:p2'}, agent_status: 'unknown'})], []);
// collect 對 mode 是 stopped 的卡把 dispatch 設成 null
check('沒有 dispatch 的 unknown 不算失聯', [], [card({agent_status: 'unknown'})], []);
JS
