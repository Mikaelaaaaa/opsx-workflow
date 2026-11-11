#!/usr/bin/env bash
# logic-map fixture 共用：把 opsx 的一個 commit 建成只有 base、head 兩個 commit、沒有 remote 的新 repo。
# 不用 clone：clone 會留下指向本 repo 的 origin 和原本的 commit 訊息，兩樣都是 skill 禁讀的意圖。
# setup.sh 用法：source 這支，再 build <commit> <dest> <branch>
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
# 跟 tests/scenarios.test.sh 同一條規則。opsx 自己的快照帶著 evals/ 與別的 skill 的題目和答案，
# 候選者看到就知道自己在被評，所以 base 與 head 都刪掉；題目自己的測試檔留著。
banned='eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena'
own_tests='(\.test\.|_test\.|(^|/)tests?/)'

snapshot() { # snapshot <commit> <dest> <message>：工作樹換成 commit 的內容，刪掉洩題路徑後 commit
  git -C "$root" archive "$1" | tar -x -C "$2"
  git -C "$2" add -A
  local pruned; pruned="$(mktemp "${TMPDIR:-/tmp}/pruned.XXXXXX")"
  git -C "$2" ls-files | grep -Ev "$own_tests" | grep -Ei "$banned" > "$pruned" || true
  if [ -s "$pruned" ]; then
    xargs git -C "$2" rm -qf -- < "$pruned"
  fi
  rm -f "$pruned"
  git -C "$2" -c user.name=dev -c user.email=dev@example.com commit -q -m "$3"
}

build() { # build <commit> <dest> <branch>
  local commit="${1:?commit}" dest="${2:?dest}" branch="${3:?branch}"
  mkdir -p "$dest"
  git -C "$dest" init -q -b "$branch"
  snapshot "$commit^" "$dest" base
  git -C "$dest" rm -rq .
  snapshot "$commit" "$dest" head
}
