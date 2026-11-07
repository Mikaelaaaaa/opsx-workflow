#!/usr/bin/env bash
# GitHub 來源，給 opsx sync 用。只撈，不寫檔。介面與輸出同 gitlab.sh：
#
#   github.sh list <sources.toml>      每個 kind = "github" 的 [[source]]，在它的 path 下跑 gh issue list --assignee @me -R <project>
#   github.sh state <project> <n>      gh issue view，印 open 或 closed
#
# 欄位照 gh 的 JSON：number、title、body、state（OPEN / CLOSED）、updatedAt、url、labels（[{name}]）。slug 是 gh-<repo 小寫>-<n>。
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  list)
    python3 -I "$here/sources.py" github "${2:?sources.toml}" | while IFS=$'\t' read -r repo project path; do
      err="$(mktemp "${TMPDIR:-/tmp}/opsx-github.XXXXXX")"
      if out="$(cd "$path" && gh issue list --assignee @me -R "$project" --json number,title,body,state,updatedAt,url,labels 2>"$err")"; then
        printf '%s' "$out" | python3 -I "$here/sources.py" normalize github "$repo" "$project" "$path"
      else
        python3 -I -c 'import json,sys;print(json.dumps({"error":open(sys.argv[1]).read().strip()[:300] or "gh 失敗","repo":sys.argv[2]},ensure_ascii=False))' "$err" "$repo"
      fi
      rm -f "$err"
    done ;;
  state)
    gh issue view "${3:?number}" -R "${2:?project}" --json state | python3 -I -c 'import json,sys;print("closed" if json.load(sys.stdin)["state"].upper()=="CLOSED" else "open")' ;;
  *) echo "用法：github.sh list <sources.toml> | github.sh state <project> <n>" >&2; exit 2 ;;
esac
