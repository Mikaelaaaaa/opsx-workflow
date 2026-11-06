# 改寫前後對照：§11 三個情境

要求檔 §11 的驗證。量測日期 2026-11-06，改寫後版本為 `f321dc6` 之後的 main（`ea7f12f`）。

## 怎麼量的

- **新版**：本 repo 的 `skills/` 與 `references/`。**舊版**：opsx-workflow 0.1.0 plugin 的 `skills/`，加上 `~/.claude/skills/grill-me`（0.1.0 沒有 grill）。
- 五個題目，情境 1 拆成 grill、propose、review 三段分開測，每段的輸入事先寫好。題目在 `skills/<skill>/evals/fixtures/`，判分條件在 `skills/<skill>/evals/evals.json`，`bash tests/run.sh scenarios` 驗題目的前置條件。
- 每題新舊各跑 3 次，同一句 prompt，skill 放在工作 repo 的 `.claude/skills/`（`evals/prepare-run.sh`）。
- 每題一個 grader 一次判完 6 次執行，只看到 A / B 標籤；過程題（先重現、讀了哪些檔、有沒有繞過 hook）讀執行紀錄，不採信自述。
- 第一輪（每組 1 次）用來修題目與判分條件，不併入下表。

## 成績

| 題目 | 新版 | 舊版 | 差值（百分點） | 情境 | 新版時間 / token | 舊版時間 / token |
|---|---|---|---|---|---|---|
| small-fix-skips-grill | 93% | 90% | +3 | 2 小 fix 跳過 grill | 52 s / 66.0k | 58 s / 66.7k |
| three-bucket-pending | 87% | 43% | +43 | 1 grill 段 | 77 s / 65.4k | 72 s / 66.4k |
| decisions-carried-verbatim | 100% | 62% | +38 | 1 propose 段 | 189 s / 92.5k | 177 s / 80.1k |
| finding-cites-violated-decision | 60% | 100% | -40 | 1 review 段 | 333 s / 87.8k | 148 s / 83.3k |
| bug-fix-reproduce-first | 67% | 77% | -10 | 3 bug fix 走 apply | 133 s / 78.3k | 110 s / 74.5k |

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

- **情境 1（需要 grill 的 feature）：前半變好，後半變差。** grill 段新版明顯較好（+43）：只問人能答的題、不把查得到的事實編成 D、會把答完的題移出待決。propose 段新版明顯較好（+38）：D1–D3 3 次都逐字進 design.md，舊版 0 次。review 段新版較差（-40）：修一輪超出 skill 自己的範圍限制、輸出沒有逐條 D 對照，D2 有一次沒被點名。§11 問的「D-id 原樣進 design.md 並被 review 引用」，新版在 propose 做到，在 review 斷了一截。
- **情境 2（該跳過 grill 的小 fix）：沒差（+3）。** 兩版都正確說明不需問人、下一步 propose；失分都來自宣稱跑過但沒跑的驗證。題目已把要問人的空間關掉，這題區辨力低。
- **情境 3（bug fix 走 apply）：新版較差（-10）。** 先重現兩版都做到；一 change 一 commit 新版 0/3，原因是 apply 自己同時寫了「一個 commit」與「先 commit 失敗測試」；回覆證據標記兩版都 0/3；新版 3 次都試圖繞過 commit hook，舊版 1 次。

建議：grill 與 propose 的改寫留著；review 與 apply 先修下面的卡再重跑對照。

## 限制

- 每組 3 次，grader 是同一個模型；差值 10 個百分點以內（情境 2、情境 3）不足以下結論。
- 這個 session 的可寫路徑都含 `claude`，`hooks/security-guard.sh` 因此誤擋所有 commit（`guard-commit-path` 卡），情境 3 的 commit 指標受影響，判分規則已依此調整。
- 已知題目缺陷：grill 段的 answers.md 一開始就在 repo，「先寫 questions.md 再讀答案」那條 6 次全滅；review 段植入的 commit 另有讀 body 失去 timeout 的瑕疵；review 段「不改 src/」那條跟新版的修一輪設計衝突，拿掉那條新版是 75%、舊版 100%。都記在 `scenario-fixtures-v2` 卡。
- grill 段原本的 93% vs 48%（對「沒 skill」）的題目已失傳，本次重建後不可直接比較。

## 開的卡

- `apply-bugfix-commits`：apply 對修 bug 的卡要求兩個 commit，與一 change 一 commit 衝突
- `apply-hook-block`：apply 沒說被 hook 擋下時要停下寫 gate，新版 3/3 試圖繞過
- `apply-reply-evidence`：§5.3 的證據標記沒人照做
- `review-fix-scope`：review 修一輪超出範圍、輸出缺逐條 D 對照
- `guard-commit-path`：security-guard 掃整條指令，路徑含 claude 就誤擋
- `scenario-fixtures-v2`：本次題目與判分條件的缺陷，下一輪前修
