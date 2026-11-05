# 交接：從這裡接下去（2026-11-05）

這份寫給下一個 session（人或 Claude）。沙盒裡做不到的事列在最前面，照順序做完再開看板那張卡。

## 0. 給接手的 Claude session

這份是在 Agentory-AI 的 session 寫的，那邊的沙盒寫不進這個目錄。接手的 session 要在**這個目錄**開、沙盒關掉或把 `~/code`、`~/.local`、`~/.claude-work/plugins`、`~/.config/herdr` 加進寫入白名單，然後 §1 全部、§2 開卡與整條流程都由 Claude 自己跑，不要再把指令丟回給使用者。設計脈絡在 `docs/rewrite-requirements-pstack-grill.md`（正本）、`UPSTREAM.md`（搬了什麼）、Obsidian `01-Projects/opsx 架構總覽.md`（ASCII 架構）。

## 1. 先在終端機做（沙盒做不到）

```bash
cd ~/code/sandbox/opsx-workflow
chmod +x bin/opsx tests/run.sh tests/fakes/herdr tests/fakes/glab hooks/*.sh
bash tests/run.sh                     # 五套要全綠：init / status / hooks / dispatch / drive

git init . && git add -A && git commit -m "feat: opsx-workflow rewrite (pstack + ponytail + grill)"
# 之後開卡、commit 都走新流程；這一顆是「舊世界的最後一顆」，commit 閘門還沒啟用（沒 workplan.yaml）

# 重裝 plugin：cache 裡的是舊 0.1.0 複本。用本機路徑重掛（看 claude plugin --help 的 marketplace/local 用法）
claude plugin uninstall opsx-workflow
claude plugin install ~/code/sandbox/opsx-workflow        # 或 marketplace add 本機路徑再 install

# 裝 CLI、建全域設定（會問 obsidian 資料夾、customer 平台；不填就 Enter）
bash ~/code/sandbox/opsx-workflow/bin/opsx init --global
# 每個要用的 repo 根目錄各跑一次（Agentory-AI、Agentory-CS、Agentory-Infrastructure、agentory-evals、gmtc-rag、scam-guard）
cd ~/code/Agentory-AI && opsx init
```

sandbox 要放行 `~/.config/herdr/herdr.sock`，不然 `opsx dispatch` 打不到 herdr；coordinator session 要在 herdr pane 裡開（`HERDR_ENV=1`）。

## 2. 用新流程做看板（herdr plugin）

在 `~/code/sandbox/opsx-workflow` 根目錄：

```bash
opsx init                                   # 這個 repo 自己也要接上
openspec new change herdr-board --schema opsx
```

`openspec/changes/herdr-board/inbox.md` 貼這個：

```markdown
---
type: 功能
source: me
found: 2026-11-05
related:
---

## 一句話

opsx 的看板：herdr plugin（薄）+ 本機網頁，三個 tab（首頁 / 收件匣 / 紀錄），資料全從磁碟和 herdr / glab 投影。

## 證據

- 要求檔 docs/rewrite-requirements-pstack-grill.md §3.6（全部已定）、§3.1 coordinator、§8.4.3 / §8.4.4 audit 與 debt
- 設計稿（canvas，按功能切塊可操作）：https://claude.ai/artifact/XxXLitJXExJRmpjrcAKh1q
- 整頁原型（假資料跑完整狀態機，欄位對到資料來源）：https://claude.ai/artifact/84HppzEmh6Tiu5ijNgiUxv
- 已有的後端：bin/opsx（dispatch / drive / stop / status）、bin/lib/stage.sh（Router 表）、hooks/
- 要補的：herdr-board/collect.sh（掃 ~/code/*/openspec/ + dispatch.json + status.json + herdr agent list + glab）、
  herdr-board/sync/{gitlab,github,obsidian,customer,shortcut}.sh（launchd 每日）、`opsx answer <slug> …`（回 gate：herdr agent prompt + decisions.tsv + gates.md status）、
  herdr plugin manifest（action open-board）+ 本機 server + 網頁（mission-control 設計系統，照原型）
```

然後 `/explore herdr-board` → 待決非空就 `/grill` → `/propose`（tasks 每條帶 驗收 / 測試）→ `/apply`（每 task 先寫測試）→ `/review` → `/pr`。第一張卡就用互動模式，看每個閘門是不是照要求擋。

## 3. 這一輪沒做、要注意的

- `herdr tab create` 回的 JSON 結構我照 herdr skill 文件猜是 `.result.root_pane`；第一次真跑 `opsx dispatch` 看一眼，不對就改 `bin/lib/dispatch.sh` 一處。
- `glab mr view -F json` 的欄位名（`head_pipeline.status`、`unresolved_discussions_count`）同樣要用真 MR 驗一次，在 `bin/lib/drive.sh` 的 `mr_state`。
- 搬進來的 pstack / ponytail 檔見 `UPSTREAM.md`；相對路徑改過，但各 skill 還沒逐支跑過 eval。grill 跑過一輪（skills/grill/evals/）。
- `~/.claude/skills/grill-me`、`grill-with-docs`、`tdd`、`prototype`、`diagnose`、`to-issues`、`to-prd`、`triage`、`zoom-out`、`improve-codebase-architecture` 照要求檔要刪，等 plugin 重裝好確認新的接得上再刪。
- `~/.claude/hooks/mr-note-reminder.sh` 被 plugin 的 `mr-format-gate.sh` 取代，plugin 重裝好後從 `~/.claude/settings.json` 拿掉。
