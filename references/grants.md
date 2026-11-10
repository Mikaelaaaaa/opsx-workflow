# 授權三級

| 級 | 意思 | 動作 |
|---|---|---|
| **直接做** | 可逆、本機、不影響別人。不問 | 讀檔、改 worktree 裡的檔、跑測試 / lint / build、commit 到自己的分支、寫 inbox 卡 / gate / decisions、開子 agent |
| **要授權** | 碰共用的東西或有副作用，但可收回。沒授權就寫 gate 等人 | push 分支、開 MR、改 MR description、本機 `db:migrate` / `db:reset`、刪檔、裝套件、呼叫 LiteLLM 以外的外部 API、測試檔放非慣例位置、寫 `.env.*`、`git rebase` 自己的分支 |
| **永遠要人** | 不可逆或對外，任何授權蓋不掉，一律 gate | merge、deploy、force-push 共用分支、刪資料 / drop table、對客戶或外部人發話、改 CI、改 secrets |

第一級不記，第三級不可授權。授權由人在 gate 上答（這次 / 這張卡 / 這個 repo 永遠）；沒答就做能做的，別繞過去。

閘門的程式碼形式在 `hooks/opsx-grant-gate.sh` 與 `bin/lib/authz.py`；改這份清單時兩邊一起看。
