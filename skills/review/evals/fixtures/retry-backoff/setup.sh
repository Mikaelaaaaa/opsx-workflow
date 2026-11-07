#!/usr/bin/env bash
# 把同目錄的 repo/ 建成乾淨的 git repo，切到這張卡的分支，再把 change/ 疊上去提交成分支上唯一的 commit。用法：setup.sh <dest>
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${1:?usage: setup.sh <dest>}"
mkdir -p "$dest"
cp -R "$here/repo/." "$dest/"
cd "$dest"
git init -q -b main
git add -A
git -c user.name=dev -c user.email=dev@example.com commit -q -m "initial"
git checkout -q -b fix/retry-backoff/dev
cp -R "$here/change/." "$dest/"
git add -A
git -c user.name=dev -c user.email=dev@example.com commit -q -m "fix(client): retry upstream failures with capped exponential backoff (retry-backoff)"
