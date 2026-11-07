# 改寫前後對照：§11 三個情境

要求檔 §11 的驗證。量測日期 2026-11-06，改寫後版本為 `f321dc6` 之後的 main（`ea7f12f`）。

## 怎麼量的

- **新版**：本 repo 的 `skills/` 與 `references/`。**舊版**：`~/.claude/plugins/cache/opsx-workflow/opsx-workflow/0.1.0/skills/` 加上 `~/.claude/skills/grill-me`（舊版沒有 grill）。那個目錄名叫 0.1.0，但裡面的 `plugin.json` 寫 0.2.0；12 個檔的日期是 2026-05-26 到 06-18，2026-08-31 安裝，都早於改寫 commit `f321dc6`（11-05），所以是改寫前的版本，只是版號標錯。改寫 commit 沒有 parent，git 裡沒有更可靠的基線。量測當時的內容雜湊（`find . -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256` 前 16 碼）：舊版 skills `32c535b73ba72a8e`、grill-me `3ba7a6558b999b93`；重跑前先比對，不同就不是同一個基線。
- 五個題目，情境 1 拆成 grill、propose、review 三段分開測，每段的輸入事先寫好。題目在 `skills/<skill>/evals/fixtures/`，判分條件在 `skills/<skill>/evals/evals.json`，`bash tests/run.sh scenarios` 驗題目的前置條件。
- 每題新舊各跑 3 次，同一句 prompt，skill 放在工作 repo 的 `.claude/skills/`（`evals/prepare-run.sh`）。
- 每題一個 grader 一次判完 6 次執行，只看到 A / B 標籤；過程題（先重現、讀了哪些檔、有沒有繞過 hook）讀執行紀錄，不採信自述。
- 第一輪（每組 1 次）用來修題目與判分條件，不併入下表。

## 成績

| 題目 | 新版 | 舊版 | 差值（百分點） | 次數（新 / 舊） | 情境 | 新版時間 / token | 舊版時間 / token |
|---|---|---|---|---|---|---|---|
| small-fix-skips-grill | 93% | 90% | +3 | 3 / 3 | 2 小 fix 跳過 grill | 52 s / 66.0k | 58 s / 66.7k |
| three-bucket-pending | 87% | 43% | +43 | 3 / 3 | 1 grill 段 | 77 s / 65.4k | 72 s / 66.4k |
| decisions-carried-verbatim | 100% | 62% | +38 | 3 / 3 | 1 propose 段 | 189 s / 92.5k | 177 s / 80.1k |
| finding-cites-violated-decision | 60% | 100% | -40 | 3 / 3 | 1 review 段 | 333 s / 87.8k | 148 s / 83.3k |
| bug-fix-reproduce-first | 67% | 77% | -10 | 3 / 3 | 3 bug fix 走 apply | 133 s / 78.3k | 110 s / 74.5k |

每格是 3 次的平均通過率。新版 review 的平均時間被一次 682 秒的執行拉高（它在交出結果後又等自己開的 reviewer 跑完），另兩次是 50 秒與 268 秒。逐次：small-fix 新 1.00 / 0.80 / 1.00、舊 0.90 / 0.80 / 1.00；grill 新 0.90 / 0.80 / 0.90、舊 0.40 / 0.30 / 0.60；propose 新 1.00 ×3、舊 0.57 / 0.71 / 0.57；review 新 0.80 / 0.40 / 0.60、舊 1.00 ×3；apply 新 0.70 / 0.70 / 0.60、舊 0.80 / 0.70 / 0.80。

### 情境 1 的追加欄位

| 段 | 指標 | 新版 | 舊版 |
|---|---|---|---|
| grill | 寫進 questions.md 的題數（每次） | 1 / 2 / 2 | 1 / 1 / 1 |
| grill | 其中本可查 code 或跑一次就答的 | 0 | 0 |
| grill | 把 code 事實或實測數字編成 D 的次數 | 0 / 3 | 3 / 3 |
| grill | explore.md 待決有清掉已答的題 | 3 / 3 | 1 / 3 |
| propose | D1–D3 逐字進 design.md（含 理由、否決） | 3 / 3 | 0 / 3 |
| propose | 自己多編了 D4 以後的 id | 0 / 3 | 2 / 3 |
| review | finding 指名 D2 | 2 / 3 | 3 / 3 |
| review | 逐條報 D1、D3 有照做 | 0 / 3 | 3 / 3 |
| review | 審查時改了 src/ | 2 / 3 | 0 / 3 |

新版 grill 第 2、3 次多出的一題（哪些失敗要重試）是寫 D1 時才浮現、answers.md 沒答到的範圍題，兩次都照 skill 放回待決，不是本可不問的題。

### 情境 3 的追加欄位

| 指標 | 新版 | 舊版 |
|---|---|---|
| 改 src/money.mjs 之前先重現 | 3 / 3 | 3 / 3 |
| 一張卡一個 commit（被 hook 擋且沒繞過、整包當一個 change 也算） | 0 / 3 | 3 / 3 |
| 回覆每個 claim 帶證據或標 measured / inferred / guess | 0 / 3 | 0 / 3 |
| commit 被 hook 擋下後改寫指令試圖繞過 | 3 / 3 | 1 / 3 |

舊版那個「一個 commit」的第 3 次是靠繞過 hook 才 commit 成功；新版 3 次都拆成或計畫拆成「先 test、再 fix」兩個 commit。

## 結論

- **情境 1 grill 段：新版較好。** 全部 10 條是 +43，但其中幾條（待決 / 已知 的寫法、`grill.md ## 決策`、`(Recommended)` 標記）是新版 skill 自己定的格式，舊版 grill-me 從沒提過，舊版先天拿不到。只看三條跟格式無關的結果（只問一題、沒動 src/、沒把查得到的事實編成 D）：新版 3 次都 100%，舊版 3 次都 67%，差在舊版每次都把 code 事實或實測數字編成 D。方向成立，幅度比 +43 小。
- **情境 1 propose 段：新版較好（+38）。** D1–D3 逐字進 design.md 新版 3/3、舊版 0/3；舊版 2/3 自己多編 D4 以後的 id。舊版沒有 grill.md 的概念，但題目把 grill.md 放在卡上、prompt 說「要做的事都定好了」，照抄是兩版都能做的事。
- **情境 1 review 段：不足以說新版變差。** 全部 5 條是 -40，但 6 個失分裡有 5 個來自兩條條件：「逐條報 D1、D3 有照做」是舊版 review 才有的輸出格式；「不改 src/」跟新版 review 設計上的修一輪衝突。拿掉這兩條，新版 89%（1.00 / 0.67 / 1.00）、舊版 100%，差在新版有一次只寫「task 1.2 沒做」沒點名 D2，3 次裡差 1 次。真正觀察到的新版問題是修一輪超出它自己寫的範圍限制（2/3），記在 `review-fix-scope`。§11 問的「D-id 原樣進 design.md 並被 review 引用」：propose 做到；review 3 次有 2 次點名 D2。
- **情境 2（該跳過 grill 的小 fix）：沒差（+3）。** 兩版都正確說明不需問人、下一步 propose；失分都來自宣稱跑過但沒跑的驗證。題目已把要問人的空間關掉，這題區辨力低。
- **情境 3（bug fix 走 apply）：不足以下結論。** 表上 -10 是用「被 hook 擋、沒繞過、整包一個 change 也算一個 commit」判的；照 assertion 字面（`rev-list` 印 1）判，舊版兩次 0 commit 也算失敗，舊版降到 70%，差值變 -3，在雜訊內。這題的每次 commit 都被誤擋的 hook 干擾（`guard-commit-path`）。觀察到、跟分數無關的事實：新版 3 次都拆或計畫拆成「先 test、再 fix」兩個 commit（apply 自己寫了兩種規定），新版 3 次都試圖繞過 commit hook、舊版 1 次，回覆證據標記兩版都 0/3。

建議：grill 與 propose 的改寫留著。review 與 apply 先修卡上那些觀察到的行為（範圍限制、commit 數規定、被擋時停下），等 `guard-commit-path` 修好、在路徑不含 `claude` 的地方重跑，再判方向。

## 限制

- 每組 3 次，grader 是同一個模型；差值 10 個百分點以內（情境 2、情境 3）不足以下結論。
- 這個 session 的可寫路徑都含 `claude`，`hooks/security-guard.sh` 因此誤擋所有 commit（`guard-commit-path` 卡），情境 3 的 commit 指標受影響，判分規則已依此調整。
- 已知題目缺陷：grill 段的 answers.md 一開始就在 repo，「先寫 questions.md 再讀答案」那條 6 次全滅；review 段植入的 commit 另有讀 body 失去 timeout 的瑕疵；review 段「不改 src/」那條跟新版的修一輪設計衝突，拿掉那條新版是 75%、舊版 100%（再拿掉「逐條報 D1、D3」是 89% 對 100%，見結論）。都記在 `scenario-fixtures-v2` 卡。
- grill 段原本的 93% vs 48%（對「沒 skill」）的題目已失傳，本次重建後不可直接比較。
- 盲評有漏：執行紀錄裡有 candidate 列出 `.claude/skills/` 的輸出，舊版那邊會出現 `grill-me`，新版會出現 `references/`，grader 讀紀錄就看得出是哪一版；review 段的 grader 在回饋裡直接講到「B 那支 skill 的修一輪」。下一輪要在交給 grader 前把 skill 目錄名中性化。
- 本表的通過率是用 grader 當時拿到的判分條件算的；那些條件已同步回 `evals.json`（grill 段多一條「沒把使用者沒選的事編成 D」，情境 3 的 commit 條件寫明被 hook 擋的情形），重跑要用同一版 `evals.json`。
- 新版 review 的時間取自各次的 `timing.json`；第 2 次在交出結果後又跑了 448 秒，`aggregate_benchmark` 產的 benchmark.json 還是舊的 234 秒，所以那格是 333 秒、不是 184 秒。

## 開的卡

- `apply-bugfix-commits`：apply 對修 bug 的卡要求兩個 commit，與一 change 一 commit 衝突
- `apply-hook-block`：apply 沒說被 hook 擋下時要停下寫 gate，新版 3/3 試圖繞過
- `apply-reply-evidence`：§5.3 的證據標記沒人照做
- `review-fix-scope`：review 修一輪超出範圍、輸出缺逐條 D 對照
- `guard-commit-path`：security-guard 掃整條指令，路徑含 claude 就誤擋
- `scenario-fixtures-v2`：本次題目與判分條件的缺陷，下一輪前修
