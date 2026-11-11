#!/usr/bin/env bash
# logic-map fixture 共用：把 opsx 的一個 commit 建成只有 base、head 兩個 commit、沒有 remote 的新 repo。
# 不用 clone：clone 會留下指向本 repo 的 origin 和原本的 commit 訊息，兩樣都是 skill 禁讀的意圖。
# setup.sh 用法：source 這支，再 build <commit> <dest> <branch>
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
# 字眼跟 tests/scenarios.test.sh 同一份。opsx 自己的快照帶著 evals/、別的 skill 的題目和答案、
# 描述評測工具的 tests/*.test.sh，候選者看到就知道自己在被評，所以 base 與 head 都刪掉。
# 只留這個 commit 改到的檔：那些是 PR 的內容，刪了 diff 就不對。
banned='eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena'

snapshot() { # snapshot <commit> <dest> <message> <keep-file>：工作樹換成 commit 的內容，刪掉洩題路徑後 commit
  git -C "$root" archive "$1" | tar -x -C "$2"
  git -C "$2" add -A
  local pruned; pruned="$(mktemp "${TMPDIR:-/tmp}/pruned.XXXXXX")"
  git -C "$2" ls-files | grep -Ei "$banned" | grep -vxF -f "$4" > "$pruned" || true
  if [ -s "$pruned" ]; then
    xargs git -C "$2" rm -qf -- < "$pruned"
  fi
  rm -f "$pruned"
  git -C "$2" -c user.name=dev -c user.email=dev@example.com commit -q -m "$3"
}

build() { # build <commit> <dest> <branch>
  local commit="${1:?commit}" dest="${2:?dest}" branch="${3:?branch}" keep
  keep="$(mktemp "${TMPDIR:-/tmp}/keep.XXXXXX")"
  git -C "$root" diff --name-only "$commit^" "$commit" > "$keep"
  mkdir -p "$dest"
  git -C "$dest" init -q -b "$branch"
  snapshot "$commit^" "$dest" base "$keep"
  git -C "$dest" rm -rq .
  snapshot "$commit" "$dest" head "$keep"
  rm -f "$keep"
}
