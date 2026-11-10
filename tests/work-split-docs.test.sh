#!/usr/bin/env bash
# references/work-split.md 的段落與入口連結。只證明文件寫了、入口指得到；內容對不對由 review 對照 subchange-fanout D1–D8。
# 驗收：openspec/changes/split-plan/specs/work-split-docs/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
DOC="$OPSX_ROOT/references/work-split.md"
assert_file "$DOC"

# --- Scenario：文件段落齊全 ---
for h in '## 四層' '## 殼的位置' '## 三層依賴' '## 什麼時候拆' '## 確認一次' '## 看板' '## 跟 fan-out 的差別'; do
  grep -qxF -- "$h" "$DOC" || fail "work-split.md 少段落：$h"
done
for k in 'features' 'prs' 'changes' 'depends-on' 'subs/' 'split_into' 'opsx check'; do
  grep -qF -- "$k" "$DOC" || fail "work-split.md 沒提到 $k"
done
for layer in 派工 session '主 change' '子 change'; do
  awk '/^## 四層/{f=1;next} /^## /{f=0} f' "$DOC" | grep -qF -- "$layer" || fail "四層段沒有 $layer"
done

# --- Scenario：README 與需求檔有連結 ---
for f in README.md docs/rewrite-requirements-pstack-grill.md; do
  grep -qF 'references/work-split.md' "$OPSX_ROOT/$f" || fail "$f 沒連到 references/work-split.md"
done
echo ok
