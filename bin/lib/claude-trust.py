"""讀 Claude Code 的資料夾信任紀錄，只讀不寫。用法：claude-trust.py <path>，印 trusted|untrusted 與該路徑。

紀錄在 projects[<path>].hasTrustDialogAccepted：CLAUDE_CONFIG_DIR 有設就在它底下的 .claude.json，
沒設在 ~/.claude.json。只認該路徑本身（git 專案要傳主 checkout 的根；父目錄的信任不算數）。
檔案不存在表示從沒信任過任何資料夾；檔案壞掉直接失敗。
"""
import json
import os
import sys


def config_file():
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    if config_dir:
        return os.path.join(config_dir, ".claude.json")
    return os.path.expanduser("~/.claude.json")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("用法：claude-trust.py <path>")
    path = sys.argv[1]
    cfg = config_file()
    if not os.path.exists(cfg):
        print(f"untrusted {path}")
        return
    with open(cfg, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise SystemExit(f"claude-trust: {cfg} 不是合法 JSON：{e}") from e
    projects = data["projects"] if "projects" in data else {}
    entry = projects[path] if path in projects else {}
    trusted = "hasTrustDialogAccepted" in entry and entry["hasTrustDialogAccepted"] is True
    print(f"{'trusted' if trusted else 'untrusted'} {path}")


if __name__ == "__main__":
    main()
