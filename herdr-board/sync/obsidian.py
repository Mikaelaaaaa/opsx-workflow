"""obsidian 收件夾來源：讀 sources.toml 的 [obsidian]，<vault>/<folder> 底下每篇 .md 印一行 JSON，不寫檔。

    obsidian.py <sources.toml>

每行是 {source, slug, title, body, evidence}，或 {"error": …}（收件夾不是資料夾）。沒有 [obsidian] 就什麼都不印。
source 用相對 vault 根的路徑，使用者改 folder 時同一篇筆記的鍵不變；slug 用它的 sha1，因為中文檔名 sanitize 後會變空。
略過名稱以 . 開頭的檔案與目錄（.trash、.obsidian）。標題降級由 sync.py 做。specs/board-sync「obsidian 收件夾」。
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import sys
import tomllib

FRONTMATTER = re.compile(r"\A---\n.*?^---[ \t]*(?:\n|\Z)", re.S | re.M)
HEADING = re.compile(r"^# (.+)$", re.M)


def notes(folder: pathlib.Path) -> list[pathlib.Path]:
    return sorted(p for p in folder.rglob("*.md")
                  if p.is_file() and not any(part.startswith(".") for part in p.relative_to(folder).parts))


def item(vault: pathlib.Path, note: pathlib.Path) -> dict:
    rel = note.relative_to(vault).as_posix()
    body = FRONTMATTER.sub("", note.read_text(encoding="utf-8"), count=1)
    heading = HEADING.search(body)
    return {
        "source": "obsidian:%s" % rel,
        "slug": "ob-%s" % hashlib.sha1(rel.encode("utf-8")).hexdigest()[:8],
        "title": heading.group(1).strip() if heading else note.stem,
        "body": body,
        "evidence": "- %s" % note,
    }


def main(toml: pathlib.Path) -> None:
    conf = tomllib.loads(toml.read_text(encoding="utf-8")).get("obsidian")
    if conf is None:
        return
    vault = pathlib.Path(conf["vault"])
    folder = vault / conf["folder"]
    if not folder.is_dir():
        print(json.dumps({"error": "%s 不是資料夾" % folder}, ensure_ascii=False))
        return
    for note in notes(folder):
        print(json.dumps(item(vault, note), ensure_ascii=False))


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]))
