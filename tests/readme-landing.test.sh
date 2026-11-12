#!/usr/bin/env bash
# README 是公開首頁：首行 tagline、必備段落、GIF、不外洩、不宣稱授權；安裝細節搬到 docs/setup.md 不遺失。
# 驗收：openspec/changes/me-20261112-1025/specs/readme-landing/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
README="$OPSX_ROOT/README.md"
SETUP="$OPSX_ROOT/docs/setup.md"
GIF="docs/assets/opsx-board-demo.gif"
assert_file "$README"

# --- Requirement：README 首行是英文 tagline ---
[ "$(sed -n '1p' "$README")" = '# opsx-workflow' ] || fail "README 第一行不是 # opsx-workflow"
tagline="$(sed -n '2,$p' "$README" | grep -m1 -v '^[[:space:]]*$')"
[ -n "$tagline" ] || fail "標題後沒有 tagline"
printf '%s' "$tagline" | LC_ALL=C grep -q '[^ -~]' && fail "tagline 含非 ASCII 字元：$tagline"

# --- Requirement：README 含首頁必備段落，依序 ---
want=(示範 為什麼做 功能重點 快速開始 流程 看板 常用指令 安全模型 路線圖)
got="$(grep '^## ' "$README" | sed 's/^## //')"
last=0
for h in "${want[@]}"; do
  n="$(printf '%s\n' "$got" | grep -nxF -- "$h" | head -1 | cut -d: -f1)"
  [ -n "$n" ] || fail "README 少二級標題：$h"
  [ "$n" -gt "$last" ] || fail "README 二級標題順序不對：$h"
  last=$n
done
quick="$(awk '/^## 快速開始/{f=1;next} /^## /{f=0} f' "$README")"
printf '%s\n' "$quick" | grep -qE '^(bash <plugin root>/bin/)?opsx init --global$' || fail "快速開始沒有 opsx init --global 這一行"
printf '%s\n' "$quick" | grep -qxF 'opsx init' || fail "快速開始沒有單獨一行 opsx init"
printf '%s\n' "$quick" | grep -qF 'docs/setup.md' || fail "快速開始沒連到 docs/setup.md"
printf '%s\n' "$quick" | grep -qF 'openspec' || fail "快速開始前置條件沒提 openspec CLI"
! grep -qF 'ogulcancelik' "$README" || fail "README 含查無佐證的 herdr 外部連結"
grep -qF 'references/work-split.md' "$README" || fail "README 沒連到 references/work-split.md"

# --- Requirement：README 引用示範 GIF ---
assert_file "$OPSX_ROOT/$GIF"
grep -qF "$GIF" "$README" || fail "README 沒引用 $GIF"

# --- Requirement：不外洩也不宣稱授權 ---
# 禁用字樣拼接寫：這個檔自己不能被下面的追蹤檔掃描命中
leak='ts''g-navigator|agen''tory|10\.65\.|172\.21\.|59\.120\.|mikaela''_lin|/Users/mikae''la|spar''k[12]|gmt''c|agn''etory|192\.168\.|10\.66\.|newre''tail|srv19[0-9]|a60''00|台''鋼'
! grep -qiE -- "$leak|/Users/|~/code" "$README" || fail "README 含禁用字樣：$(grep -oiE -- "$leak|/Users/|~/code" "$README" | head -1)"
for s in 'MIT License' 'Apache License' 'licensed under' 'GPL' 'SPDX-License-Identifier'; do
  ! grep -qiF -- "$s" "$README" || fail "README 宣稱授權：$s"
done
! awk '/^## 路線圖/{f=1;next} /^## /{f=0} f' "$README" | grep -qF '補 LICENSE' || fail "LICENSE 已存在，路線圖不該再列補 LICENSE"

# --- Requirement：LICENSE 檔與 plugin.json 一致 ---
assert_file "$OPSX_ROOT/LICENSE"
[ "$(sed -n '1p' "$OPSX_ROOT/LICENSE")" = 'MIT License' ] || fail "LICENSE 第一行不是 MIT License"
meta="$(python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); print(m["license"]); print(m["author"]["name"])' "$OPSX_ROOT/.claude-plugin/plugin.json")"
[ "$(printf '%s\n' "$meta" | sed -n '1p')" = MIT ] || fail "plugin.json 的 license 不是 MIT"
grep -qF "Copyright (c)" "$OPSX_ROOT/LICENSE" || fail "LICENSE 沒有 Copyright (c)"
grep -qF -- "$(printf '%s\n' "$meta" | sed -n '2p')" "$OPSX_ROOT/LICENSE" || fail "LICENSE 的著作權人不是 plugin.json 的 author.name"

# --- Requirement：repo 追蹤檔不含公司名、內網主機與個人路徑 ---
hits="$(git -C "$OPSX_ROOT" grep -niE -- "$leak" -- . ':!docs/assets' | head -20)"
[ -z "$hits" ] || fail "追蹤檔含禁用字樣：
$hits"
# /Users/ 底下只准中性名字（dev、me、you）
hits="$(git -C "$OPSX_ROOT" grep -noE '/Users/[A-Za-z0-9_.-]+' -- . ':!docs/assets' ':!tests/readme-landing.test.sh' | grep -vE ':/Users/(dev|me|you)$' | head -20)"
[ -z "$hits" ] || fail "追蹤檔含非中性的 /Users/ 路徑：
$hits"

# --- Requirement：安裝細節搬到 docs/setup.md 不遺失 ---
assert_file "$SETUP"
for k in 'templates/settings.opsx.json' 'grants.toml' 'opsx-protected' 'coordinator-settings.json' 'opsx init --check' 'com.opsx.sync' 'opsx drop' 'security-guard.sh' 'claude plugin update' 'openspec'; do
  grep -qF -- "$k" "$SETUP" || fail "docs/setup.md 少了 $k"
done
echo ok
