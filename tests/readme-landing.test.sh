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
grep -qF 'opsx init --global' "$README" || fail "快速開始沒有 opsx init --global"
grep -qE 'opsx init([^ -]|$)|opsx init$|opsx init `' "$README" || fail "快速開始沒有 opsx init"
grep -qF 'docs/setup.md' "$README" || fail "README 沒連到 docs/setup.md"
grep -qF 'references/work-split.md' "$README" || fail "README 沒連到 references/work-split.md"

# --- Requirement：README 引用示範 GIF ---
assert_file "$OPSX_ROOT/$GIF"
grep -qF "$GIF" "$README" || fail "README 沒引用 $GIF"

# --- Requirement：不外洩也不宣稱授權 ---
for s in '/Users/' '~/code' 'tsg' 'agentory' '10.65.' '172.21.'; do
  ! grep -qiF -- "$s" "$README" || fail "README 含禁用字樣：$s"
done
for s in 'MIT License' 'Apache License' 'licensed under' 'GPL' 'SPDX-License-Identifier'; do
  ! grep -qiF -- "$s" "$README" || fail "README 宣稱授權：$s"
done
awk '/^## 路線圖/{f=1;next} /^## /{f=0} f' "$README" | grep -qF '補 LICENSE' || fail "路線圖沒有「補 LICENSE」"

# --- Requirement：安裝細節搬到 docs/setup.md 不遺失 ---
assert_file "$SETUP"
for k in 'templates/settings.opsx.json' 'grants.toml' 'opsx-protected' 'coordinator-settings.json' 'opsx init --check' 'com.opsx.sync' 'opsx drop'; do
  grep -qF -- "$k" "$SETUP" || fail "docs/setup.md 少了 $k"
done
echo ok
