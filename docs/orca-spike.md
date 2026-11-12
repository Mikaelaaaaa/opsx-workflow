# Orca spike：能不能用 Orca worker 取代 herdr 派工

卡：`me-20261112-1015-2`。2026-11-12 在使用者的 Mac 上實測，Orca app pid 69717，runtime `11d4594f`。

## 前提

- 這個 session 的 sandbox 擋 unix socket。使用者在 `~/.claude-work/settings.json` 加了 `sandbox.excludedCommands: "orca *"`，又暫時在 `permissions.allow` 加了 `Bash(orca:*)`。後者在 spike 結束後由協調者拿掉。
- `"orca *"` 只比對得到單獨下的 orca 指令。前面接 `cd … &&`、後面接 pipe，或參數裡有 `$'…'`，整串指令都留在 sandbox 裡跑，回 `Permission denied connecting to Orca (EPERM)`。
- worker 用拋棄式目錄 `/tmp/claude-502/orca-spike/repo`，不碰 inbox 的卡。授權閘門那項必須在有 autopilot 卡的 repo 裡跑，所以用這張卡的 worktree。

## 驗證紀錄

| 項目 | 指令 | 輸出 | 判定 | 原因 |
|---|---|---|---|---|
| socket 連線 | `orca status`（單獨一個 Bash 呼叫） | `runtimeReachable: true`、`runtimeConnectionState: connected`、`runtimeState: ready` | 過 | |
| socket 重開後 | `orca status --json`；`ls ~/Library/Application\ Support/orca/` | `reachable: true`、`connectionState: connected`，但 `app.pid` 仍是 69717，socket 仍是 10:34 建的 `o-69717-11d4.sock`，`orcad.lock` 的 pid 也是 69717 | 未驗 | 使用者 13:3x 按 Cmd+Q 再打開，但 app 主 process 沒有退出（pid 與 socket 檔名都沒變），所以沒驗到 socket 換檔名的情況。照 D1，excludedCommands 比對的是指令，不是 socket 路徑，換檔名理論上不影響，這點是推論 |
| 自訂啟動參數 | `orca terminal create --command "cd …/repo && claude --settings …/settings.json --permission-mode dontAsk --add-dir …/extra"`，再 `orca orchestration worker-start --terminal <handle> --spec-file spec-a.md` | worker 回報：`printenv ORCA_SPIKE_MARK` 印出 settings 裡設的 `settings-loaded-91ab`；Read `extra/marker.txt` 讀到 `add-dir-marker-7c3f`；Write 被拒，訊息 `Permission to use Write has been denied because Claude Code is running in don't ask mode.`；狀態列 `don't ask on` | 過 | |
| 啟動參數重開後 | `orca terminal list --json` 比對重開前後；`orca terminal send` 問 orca-spike-a 的 claude 剛才 `printenv ORCA_SPIKE_MARK` 印了什麼，再跑一次 | 五個 terminal 的 handle、ptyId、incarnationId 都和重開前相同，`connected: true`；orca-spike-a 憑記憶答 `settings-loaded-91ab`，重跑也印 `settings-loaded-91ab`，狀態列 `don't ask on`，scrollback 從 TASK 到 13:16 的 worker_done 都在 | 過 | |
| worker_done 叫醒 | Orca terminal 裡的 claude 協調者跑 `orca orchestration worker-start --spec 'Immediately report worker_done with the body hello-wake…' --terminal <worker A>`，然後結束回合 | Orca 在協調者輸入 `You have 1 orchestration message. Run orca orchestration check --run run_3b59d68a045a.`，協調者回 `WOKE hello-wake`；信箱 `msg_b8ebe93e8773` 的 `delivered_at` 有值 | 過 | |
| escalation 叫醒 | 同一個協調者派 worker：`orca orchestration ask` 問 `escalation test, reply PONG`，拿到答案再送 worker_done | 問題 `msg_4b4a230c4112` 叫醒協調者，協調者 `orca orchestration reply` PONG；回覆叫醒 worker，worker 送 worker_done `got-PONG`，再叫醒協調者，協調者回 `WOKE2 got-PONG` | 過 | |
| 授權閘門 | | | 未驗 | 不需要（不換引擎）：Orca worker 不接 opsx 卡（gate `orca-grant-check` 選 B）。驗到一半時，本 session 自己的授權閘門擋下了交給 worker 的觸發指令：`opsx 授權閘門：「deploy」是永遠要人的動作（第三級），任何授權蓋不掉。`。hook 比對整段指令原文，送給 worker 的文字也算 |
| orca serve 常駐 | `orca serve --json`（Orca app 開著時） | exit 3，`runtime_serve_already_running`：`Orca is already running for this userData profile as pid 69717; not starting a second process.` | 未驗 | 不需要（不換引擎），gate `orca-grant-check` 選 B。app 開著時 serve 不會起第二個 runtime，沒有關 app 驗無介面常駐 |

## 驗證中看到的其他事

- 協調者必須是 Orca 管的 terminal。herdr pane 裡的 session 跑 `worker-start` 回 `no_active_sender_terminal: Could not determine the calling terminal for this orchestration command.`。用 `--from` 綁一個跑 `cat` 的 Orca terminal 當協調者，ask 和 worker_done 都進了 Run 信箱，但 `delivered_at` 是 null：Orca 只叫醒它認得的 agent，不會叫醒一般 terminal。換句話說，opsx 的協調者要搬進 Orca 裡跑，叫醒才有用。
- `worker-start --agent claude` 沒有傳任意 CLI 參數的旗標，只有 `--model` 和 `--effort`。要帶 `--settings`、`--permission-mode`、`--add-dir`，只能先 `orca terminal create --command "claude …"`，再用 `worker-start --terminal <handle>` 把任務交給它。
- 新目錄的 claude 會先停在信任對話框。`orca terminal create` 起的 worker 要有人在對話框按確認（這次用 `orca terminal send --text j` 加 `--enter`）。`worker-start --agent claude --worktree current` 解析成家目錄，worker 卡在同一個對話框，回 `start_failed`、`Agent startup blocked: agent-trust-workspace`。opsx 現在用 launch 預先寫入信任，換成 Orca 也要做同一件事。
- `--worktree current` 對 sandbox 外的 orca 來說是家目錄（`orca worktree current` 回 `path: /Users/mikaela_lin`），不是呼叫者的 worktree。

## 結論

使用者 13:2x 定下 2.0 的方向：Orca 當工作台，herdr 照舊當引擎，Orca worker 不接 opsx 卡。實測也支持不換引擎：叫醒只對 Orca 裡的 agent terminal 有效，opsx 的協調者得整個搬進 Orca；自訂啟動參數要繞道 `terminal create`；信任對話框要另外處理。這三件都是換引擎前要先改的 opsx 程式。

Orca 當工作台時，terminal 在 Cmd+Q 再打開之後活下來，claude 的對話、`--settings` 與 dontAsk 都還在。terminal 由獨立的 terminal daemon 持有（`daemon/daemon-v55.pid`：pid 66203，11/11 17:22 啟動，由 `Orca Terminal Host.app` 起），不歸視窗管。不過這次 Cmd+Q 連 app 主 process（pid 69717）都沒有結束，所以這次只證明 terminal 熬過關視窗再打開；app 主 process 真的換 pid、或重開機之後 terminal 還在不在，都沒有驗。

結論：不換
依據：worker_done 叫醒、自訂啟動參數、授權閘門、orca serve 常駐
