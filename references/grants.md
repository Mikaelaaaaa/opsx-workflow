# 授權三級

| 級 | 意思 | 動作 |
|---|---|---|
| **直接做** | 可逆、本機、不影響別人。不問 | 讀檔、改 worktree 裡的檔、跑測試 / lint / build、commit 到自己的分支、`git merge origin/main` 進自己的分支（推出去另算，見要授權）、寫 inbox 卡 / gate / decisions、開子 agent |
| **要授權** | 碰共用的東西或有副作用，但可收回。沒授權就寫 gate 等人 | push 分支、開 MR、改 MR description、開新 MR 時回原 issue 留 MR 連結（只有連結，歸在 `mr`）、本機 `db:migrate` / `db:reset`、刪檔、裝套件、呼叫 LiteLLM 以外的外部 API、測試檔放非慣例位置、寫 `.env.*`、`git rebase` 自己的分支 |
| **永遠要人** | 不可逆或對外，任何授權蓋不掉，一律 gate | 合 MR（merge）、deploy、force-push 共用分支、刪資料 / drop table、對客戶或外部人發話、改 CI、改 secrets |

「對客戶或外部人發話」閘門不判：hook 看不到 email、聊天訊息；`glab issue note` / `gh issue comment` 它一律當 `mr` 判。沒被擋不代表可以做：除了 `/pr` 步驟 5b 那一則 MR 連結，其他 issue 留言都是第三級：發話前自己寫 `type: approval` 的 gate，停在這個動作。

第一級不記，第三級不可授權。授權由人在 gate 上答（這次 / 這張卡 / 這個 repo 永遠）；沒答就做能做的，別繞過去。

閘門的程式碼形式在 `hooks/opsx-grant-gate.sh` 與 `bin/lib/authz.py`；改這份清單時兩邊一起看。
