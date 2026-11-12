# 安裝與設定

這份從 [README](../README.md) 搬來，內容原樣保留：安裝、使用者層 settings、授權檔、herdr socket、onboarding、看板與收件匣子命令。

## 安裝（Claude Code 2.1.275+）

```
/plugin install opsx-workflow --marketplace Mikaelaaaaa/opsx-workflow
```

或本機路徑：`claude plugin marketplace add ~/code/sandbox/opsx-workflow && claude plugin install opsx-workflow@opsx-workflow`。
需要 Python 3.11 以上（macOS 內建的 3.9 不夠，pyenv 或 brew 裝一個）。裝完跑一次 `bash <plugin root>/bin/opsx init --global`（裝 `~/.local/bin/opsx`、建 `~/.local/state/opsx/`、掛 herdr 看板 plugin），
再到每個要用的 repo 根目錄跑 `opsx init`。

`init --global` 會把 PATH 上 `python3` 背後真正的執行檔記在 `~/.local/state/opsx/python`，opsx 和 hooks 只用它（繞過 pyenv shim，每次省 250 ms 左右）。
升級到有這個檔的版本後、或 pyenv 換了 python 版本後，要再跑一次 `opsx init --global`；沒跑的話 opsx 會報錯，卡的 branch 上的授權閘門會擋下 Bash 呼叫。

`init --global` 與 `init` 也會改使用者層 Claude Code settings（`$CLAUDE_CONFIG_DIR/settings.json`，沒設才是 `~/.claude/settings.json`）。要寫什麼只有一份標準設定：`templates/settings.opsx.json`（opsx / openspec 的 allow 規則、opsx state 目錄可寫、`gh pr *` 在沙盒外執行、授權檔唯讀）；`init` 在 repo 裡再把該 repo 的根目錄加進可寫目錄。state 目錄下的 `grants.toml`（「這個 repo 永遠」那級的授權）、`python`（hook 跑的 interpreter 路徑）與 `coordinator-settings.json`（主控 session 的設定）在沙盒內唯讀，所以要改它們得在沙盒外（你的終端機）跑 `opsx init --global` 或 `opsx answer --grant`。這只擋沙盒內對這三個檔的直接寫入：合併核准與卡片層、這次的授權由下面的 `opsx-protected` 擋；rename 能否蓋過被 deny 的檔、hardlink 能否繞過，沒實測。`opsx init` 在 opsx 程式碼位於被登記的 repo 內時（例如 opsx 自己的 repo）只警告：登記後所有 session 都能改那些程式碼。只追加不存在的項目，改檔前把原檔備份成 `settings.json.opsx-bak`，重跑不動；檔案不是合法 JSON 時直接報錯、不改它。

herdr socket 不在使用者層標準設定裡：能連它的 session 可以用 `herdr pane run` 在沒有沙盒的 pane 裡跑指令。一般 agent 的 herdr 動作照原設計走 `hooks/opsx-herdr-queue.sh`；只有主控 session（opsx coordinator）要開 socket，`opsx init --global` 會把設定寫到 `~/.local/state/opsx/coordinator-settings.json`，主控 session 在 herdr pane 裡跑 `opsx lead [<repo 路徑>]` 啟動：它在目前 workspace 開一個新 tab，用 herdr 名 `opsx-coordinator` 起 `claude --settings ~/.local/state/opsx/coordinator-settings.json --add-dir ~/.local/state/opsx`，第一句載入 `/opsx-workflow:lead`（協調者的職責與回報格式）；已經在跑就只告訴你它在哪個 pane。**opsx 只追加、不刪除**：如果你以前手動在使用者層 settings 的 `sandbox.network.allowUnixSockets` 加過 herdr socket，要自己刪掉，否則每個 session 都還能連 herdr，上面的隔離不成立。

新電腦 onboarding：裝好 plugin → `opsx init --global` → 每個 repo 根目錄 `opsx init` → `opsx init --check` 確認和標準設定一致（只讀；缺什麼逐項印出，exit 1）。要改全部機器的設定，改 `templates/settings.opsx.json`、再各跑一次 `opsx init --global`，不要手改各台的 settings。

`opsx init --global` 與 `opsx init --check` 也會掃使用者層（`$CLAUDE_CONFIG_DIR/skills/`，沒設用 `~/.claude/skills/`）與 repo 內 `.claude/skills/`，跟插件 `skills/` 同名的逐項警告；只警告，不影響 exit code，不動你的檔案。

資料夾要在 Claude Code 的信任對話框按過信任，專案層 settings 的 allow 與 additionalDirectories 才生效；`opsx init`、`opsx init --check`、`opsx dispatch` 發現 repo 沒信任會警告。opsx 自己的設定在使用者層，不受信任狀態影響；opsx 不會替你改信任紀錄。

合併核准、「這張卡」與「這次」的授權存在 `~/.local/state/opsx-protected/authz.json`（`init --global` 建，0700）。它刻意放在 `~/.local/state/opsx/` 之外，不要把它或它的父目錄加進任何 `additionalDirectories`：沙盒內的 session 寫得到 `dispatch.json`，所以閘門只信這裡。`opsx merge`、`opsx answer --grant card|this` 要在沙盒外跑（終端機或看板），在 agent 的沙盒裡會報「受保護位置寫不進去」。`opsx init` 的上層目錄檢查也涵蓋它：repo 根目錄是 state 目錄的上層時直接拒絕，`opsx-protected` 與 state 目錄同層，所以一併不會被開成可寫。

## 看板

資料全是投影（`opsx collect`：`openspec/changes/*/`、`~/.local/state/opsx/`、`herdr agent list`、`glab mr view`），看板自己不存狀態。

- 網頁：herdr 裡叫 action `open-board`（`opsx init --global` 已 `herdr plugin link`），或 `bash herdr-board/scripts/open-board.sh`。
  首頁四段 待處理 / 進行中 / 待指派 / 已完成，另有收件匣 tab（見下）；按鈕背後是 `opsx answer`（回 gate、三種授權答案）、`opsx dispatch`、`opsx merge`（寫一次性核准，叫 agent `/babysit merge`，閘門只放行那一次）、`opsx stop`。
- 右側 pane：herdr 裡叫 action `open-pane`，在按鍵的 pane 右邊以 split 開 pane `board`（`python3 herdr-board/tui.py`）；這個 tab 已經開著就跳過去，不疊第二個。同一份清單，↑↓ 選、Enter 跳 pane、i / d 展開收件匣 / 已完成、q 關；不回 gate、不派工。
- 快捷鍵：herdr 的鍵綁 action，在 `~/.config/herdr/config.toml` 加兩段（prefix 是你 herdr 的前綴鍵）：
  ```toml
  [[keys.command]]
  key = "prefix+o"
  type = "plugin_action"
  command = "opsx-board.open-board"

  [[keys.command]]
  key = "prefix+shift+o"
  type = "plugin_action"
  command = "opsx-board.open-pane"
  ```
- 對原型看畫面：`python3 herdr-board/server.py --collect herdr-board/tests/fixtures/collect-sample.json`，開 `http://127.0.0.1:8791/#token=$(cat ~/.local/state/opsx/board-token)`。
- 收件匣 tab：沒派出、還沒 explore 的卡（explore 過才到首頁待指派），依 inbox.md 的 `source` 分組，加上沒有 repo 的「待分類」。每個按鈕都有對應的子命令，終端機做得到同一件事：
  - `opsx new [--repo <path>] -- <一句話>`：＋新增。範圍選到單一 repo 時建在那裡（slug `me-<YYYYMMDD-HHMM>`），否則寫進 `~/.local/state/opsx/unfiled/` 待分類。
  - `opsx file <slug> --repo <path>`：待分類選 repo 建卡。
  - `opsx drop <slug> [--repo <path>] -- <理由>`：捨棄，理由必填；收件卡歸檔並標 `outcome: declined`，待分類移到 `unfiled/dropped/`。
  - `opsx sync [--source gitlab|github|debt|obsidian]`：撈 `sources.toml` 登記的 repo 裡指派給你的 issue，和 code 裡的 `shortcut:` 註解，以 inbox.md 的 `source` 去重（含 archive），建殼或更新。`[obsidian]` 收件夾（`vault` / `folder`，含子資料夾）的每篇筆記進待分類，建好之後不再依筆記內容更新。上游關閉、註解刪掉只標記（列灰色），卡由你捨棄。每次跑完經 `opsx log --sync` 在 `~/.local/state/opsx/sync.log` 記一列 source `sync`（文字是新建、更新、沒變、錯誤數與第一個錯誤），紀錄 tab 讀得到；同一時間只跑一支，另一支退出碼 3。
  - 每日同步：`opsx init --global` 裝 launchd job `com.opsx.sync`（`~/Library/LaunchAgents/com.opsx.sync.plist`），每天 09:00 跑 `opsx sync`，輸出在 `~/.local/state/opsx/sync.out`。
- 紀錄 tab 在 `board-log` 那張卡（`openspec/workplan.yaml`）。
