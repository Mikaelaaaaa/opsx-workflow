#!/usr/bin/env bash
# 把同目錄的 repo/ 建成乾淨的 git repo，停在這張卡的分支上。用法：setup.sh <dest>
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")/repo" && pwd)"
dest="${1:?usage: setup.sh <dest>}"
mkdir -p "$dest"
cp -R "$src/." "$dest/"
cd "$dest"
git init -q -b main
git add -A
git -c user.name=dev -c user.email=dev@example.com commit -q -m "initial"
git checkout -q -b feat/kb-export/dev
