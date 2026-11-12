#!/usr/bin/env bash
# GitLab 來源，給 opsx sync 用。只撈，不寫檔。
#
#   gitlab.sh list <sources.toml>      每個 kind = "gitlab" 的 [[source]]，在它的 path 下跑
#                                      glab issue list --assignee=<assignee> -R <project>（assignee 是該來源在 sources.toml 設的 GitLab 帳號名，
#                                      沒設就印 error 行、不呼叫 glab；不用 @me，它要打 /user，token 沒有 User: Read 會 403），一行印一個 JSON：
#                                        issue：{source, repo, path, slug, title, body, url, state, updated_at, type}
#                                        撈成功：{"listed": <repo>, "project": <project>}（opsx sync 只對撈成功的 repo 查關閉）
#                                        撈失敗：{"error": <stderr 第一段>, "repo": <repo>}，其他來源照跑
#   gitlab.sh state <project> <iid>    glab issue view，印 open 或 closed
#
# 欄位照 glab 的 JSON：iid、title、description、state（opened / closed）、updated_at、web_url、labels（字串陣列）。
# label 含 bug 的 type 是「錯誤修正」，其他是「功能」。slug 是 gl-<repo 小寫>-<iid>（board-inbox D2）。
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  list)
    python3 -I "$here/sources.py" gitlab "${2:?sources.toml}" | while IFS=$'\t' read -r repo project path assignee; do
      if [ -z "$assignee" ]; then
        python3 -I -c 'import json,sys;print(json.dumps({"error":"gitlab 來源 %s 沒設 assignee：在 sources.toml 這個 [[source]] 加 assignee = \"<GitLab 帳號名>\"（不用 @me，它要打 /user，token 要有 User: Read）" % sys.argv[1],"repo":sys.argv[1]},ensure_ascii=False))' "$repo"
        continue
      fi
      err="$(mktemp "${TMPDIR:-/tmp}/opsx-gitlab.XXXXXX")"
      if out="$(cd "$path" && glab issue list --assignee="$assignee" -R "$project" -F json 2>"$err")"; then
        printf '%s' "$out" | python3 -I "$here/sources.py" normalize gitlab "$repo" "$project" "$path"
      else
        python3 -I -c 'import json,sys;print(json.dumps({"error":open(sys.argv[1]).read().strip()[:300] or "glab 失敗","repo":sys.argv[2]},ensure_ascii=False))' "$err" "$repo"
      fi
      rm -f "$err"
    done ;;
  state)
    glab issue view "${3:?iid}" -R "${2:?project}" -F json | python3 -I -c 'import json,sys;print("closed" if json.load(sys.stdin)["state"]=="closed" else "open")' ;;
  *) echo "用法：gitlab.sh list <sources.toml> | gitlab.sh state <project> <iid>" >&2; exit 2 ;;
esac
