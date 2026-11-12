#!/usr/bin/env bash
# 看板收件匣的「技術債」：shortcut 不當卡列，只顯示各 repo 的數量，展開後列 file:line、上限、升級條件
# （specs/debt-board-count「看板收件匣只顯示 shortcut 數量」）。規則寫在網頁的 inline script，這裡用 node 把標記之間切出來執行。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v node >/dev/null || fail "需要 node 才能跑技術債的網頁測試"

node - "$OPSX_ROOT/herdr-board/web/index.html" <<'JS' || fail "技術債網頁規則"
const fs = require('node:fs');
const assert = require('node:assert');
const html = fs.readFileSync(process.argv[2], 'utf8');
const START = '/* 技術債 start */', END = '/* 技術債 end */';
const s = html.indexOf(START), e = html.indexOf(END);
if (s < 0 || e < s) throw new Error(`index.html 找不到標記 ${START} / ${END}`);
const esc = x => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
const {debtTotal, debtRows} = new Function('esc', html.slice(s, e) + ';return {debtTotal, debtRows};')(esc);

const hit = (file, line, limit, trigger) => ({file, line, limit, trigger});
const debt = {a: [hit('x.py', 3, '單 worker', '量大再拆'), hit('<y>.py', 9, '上限', '')], b: [hit('z.py', 1, 'l', 't')], c: []};

// 數量：每個有 shortcut 的 repo 一列，總數是筆數加總
assert.strictEqual(debtTotal(debt), 3);
assert.strictEqual(debtTotal({}), 0);
assert.strictEqual(debtTotal(undefined), 0, '舊資料沒有 debt 欄');
const collapsed = debtRows(debt, null);
assert.strictEqual((collapsed.match(/data-act="debt-toggle"/g) || []).length, 2, '只列有 shortcut 的 repo');
assert.ok(collapsed.includes('data-repo="a"') && collapsed.includes('data-repo="b"') && !collapsed.includes('data-repo="c"'));
assert.ok(!collapsed.includes('x.py'), '沒展開時不列清單');
assert.ok(/aria-expanded="false"/.test(collapsed));

// 展開：列 file:line、上限、升級條件；檔名要跳脫
const open = debtRows(debt, 'a');
assert.ok(open.includes('x.py:3') && open.includes('單 worker') && open.includes('量大再拆'));
assert.ok(open.includes('&lt;y&gt;.py:9') && !open.includes('<y>.py'), '檔名要跳脫');
assert.ok(!open.includes('z.py'), '只展開選到的 repo');
assert.ok(/aria-expanded="true"/.test(open));

// 沒有 shortcut：沒有任何列
assert.strictEqual(debtRows({}, null), '');
JS
echo "board-debt-web ok"
