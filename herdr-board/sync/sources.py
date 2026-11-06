"""gitlab.sh / github.sh 共用的兩件事：讀 sources.toml、把 glab / gh 的 issue JSON 轉成 opsx sync 的統一欄位。

    sources.py <gitlab|github> <sources.toml>                          印 repo<TAB>project<TAB>path，一個來源一行
    sources.py normalize <gitlab|github> <repo> <project> <path>  < list 的 JSON 陣列，印 issue 行加一行 {"listed": …}
"""
from __future__ import annotations

import json
import re
import sys
import tomllib

SLUG_MAX = 32
# 兩家的欄位名不同，其餘規則一樣
FIELDS = {
    "gitlab": {"n": "iid", "body": "description", "url": "web_url", "updated": "updated_at", "prefix": "gl"},
    "github": {"n": "number", "body": "body", "url": "url", "updated": "updatedAt", "prefix": "gh"},
}


def slug_for(prefix: str, repo: str, n: int) -> str:
    """<prefix>-<repo 小寫>-<n>；repo 裡 slug 不收的字元換成 -，太長就截 repo 那段，讓整個 slug 不超過 32 字。"""
    tail = "-%d" % n
    name = re.sub(r"[^a-z0-9_-]", "-", repo.lower())
    return ("%s-%s" % (prefix, name))[: SLUG_MAX - len(tail)] + tail


def label_names(labels: list) -> list[str]:
    return [x["name"] if isinstance(x, dict) else x for x in labels]


def normalize(kind: str, repo: str, project: str, path: str, issues: list[dict]) -> list[dict]:
    f = FIELDS[kind]
    out = []
    for i in issues:
        n = i[f["n"]]
        bug = any(name.lower() == "bug" for name in label_names(i.get("labels") or []))
        out.append({
            "source": "%s:%s#%d" % (kind, repo, n), "repo": repo, "path": path, "slug": slug_for(f["prefix"], repo, n),
            "title": " ".join(i["title"].split()), "body": i[f["body"]] or "", "url": i[f["url"]],
            "state": "closed" if i["state"].lower() == "closed" else "open", "updated_at": i[f["updated"]],
            "type": "錯誤修正" if bug else "功能",
        })
    return out


def main() -> None:
    if sys.argv[1] == "normalize":
        kind, repo, project, path = sys.argv[2:6]
        for item in normalize(kind, repo, project, path, json.load(sys.stdin)):
            print(json.dumps(item, ensure_ascii=False))
        print(json.dumps({"listed": repo, "project": project}, ensure_ascii=False))
        return
    kind, toml_path = sys.argv[1], sys.argv[2]
    with open(toml_path, "rb") as fh:
        sources = tomllib.load(fh).get("source", [])
    for s in sources:
        if s.get("kind") == kind:
            print("%s\t%s\t%s" % (s["repo"], s["project"], s["path"]))


if __name__ == "__main__":
    main()
