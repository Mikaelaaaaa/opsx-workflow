# 拆工：派工、session、主 change、子 change

一張卡太大時，explore 把它拆成幾個主 change 與子 change，使用者確認一次，之後照 workplan 自動做。規則的出處是 subchange-fanout 的 grill.md（D1–D8，使用者 2026-11-10 定）；這份講怎麼用。

例子貫穿全文：subchange-fanout 拆成 session `fanout-flow`（主 change `split-plan`、`apply-fanout`）與 session `fanout-board`（主 change `board-tree`）。

## 四層

| 層 | 是什麼 | workplan 欄位 |
|---|---|---|
| 派工 | 一次送出一批工作（使用者按，或 propose 完自動），可以開多個 session | workplan 裡依賴都滿足、可以開工的部分 |
| session | 一個 Claude pane，依序做一組主題相近的主 change，共用讀過的 context | `features[]` |
| 主 change | 一件完整、可單獨 review 的事：一條 branch、一個 PR | `features[].prs[]` |
| 子 change | 主 change 拆出的一小塊，可單獨測試；一個子 change 一個 commit，由 subagent 實作 | `features[].prs[].changes[]` |

一個 PR 只有一個 change 時，主 change 與子 change 同名，跟以前的卡一樣。

## 殼的位置

- 主殼：`openspec/changes/<主>/`。inbox / explore / grill / proposal / design 涵蓋整件事；tasks.md 一個子 change 一項，勾起來代表那個子 change 已經疊進 PR 分支；specs/ 是各子殼 spec 的合集（openspec archive 只併主殼的 specs）。
- 子殼：`openspec/changes/<主>/subs/<子>/`。各自完整的 inbox / proposal / specs / design / tasks，`.openspec.yaml` 寫 `parent: <主>`，design 引用主殼的 D-id。
- openspec CLI 只認 `changes/<name>/` 一層，`openspec validate` / `status` 只管主殼。子殼齊不齊由 `opsx check <主>` 檢查：四個檔、每個 Requirement 有 Scenario、每個 task 有 `驗收：` 與 `測試：`、D-id 對得到主殼、`parent` 對。
- 讀主殼就讀得到全部子殼；archive 整包一起搬。

## 三層依賴

三層都寫在 workplan，規則一樣：沒依賴就不等，有依賴才等。

```yaml
features:
  - name: fanout-flow            # session
    depends-on: []
    prs:
      - name: split-plan         # 主 change
        branch: feat/split-plan/mikaela-lin
        depends-on: []
        changes:
          - name: workplan-depends   # 子 change
            depends-on: []
          - name: explore-split
            depends-on: [workplan-depends]
      - name: apply-fanout
        depends-on: [split-plan]
  - name: fanout-board
    depends-on: [split-plan]     # 列 PR 名：這些 PR 合併後，這個 session 才開工
```

- session 之間：`features[].depends-on`，列前一個 session 裡相關的 PR 名，全部 merged 才開工。
- 主 change 之間：`prs[].depends-on`。沒依賴的從 main 開新 branch；有依賴的等前一個 PR 合併。
- 子 change 之間：`changes[].depends-on`，只列同一個 PR 底下的子 change。沒依賴的各給一個 subagent 平行做，有依賴的依序做。

用子 change 名派工時，branch 與「是否已合併」都看它所屬的 PR。

## 什麼時候拆

由 explore 拆，時間點有兩個：收件時就看得出很大，或 explore 做完才發現很大。「很大」符合任一條就拆：

1. 跨超過一個子系統（例如 CLI、skill、看板、文件）。
2. 風險不同的混在一起：資料遷移、權限、對外 API 跟一般邏輯在同一個改動。
3. 一個殼的 tasks 會超過 6 個。

explore 每次都把這三條的判斷寫進 explore.md。不以預估行數判斷。

## 確認一次

拆法寫成 gates.md 的一個 decision gate：列出 session、主 change、子 change 和三層依賴。使用者點頭前不建殼、不寫 workplan；autopilot 也一樣。確認後 explore 依序：

1. 每個主 change 用 `openspec new change` 建主殼。
2. 每個子 change 建 `subs/<子>/`，含 inbox.md（frontmatter 寫 `parent`、`depends-on`）與 `.openspec.yaml`。
3. workplan 寫 feature / PR / change 與三層 `depends-on`。
4. 原來的大卡 inbox frontmatter 加 `split_into: <主1>, <主2>`。這張卡的 stage 從此是 `split`：router 不再推下一站，drive 結束，看板歸已完成。

之後全自動，合併仍是使用者。

## 看板

一個 session 一張卡。列表一行，例如「看板主題 · 主 change 1/2 · 子 change 4/7 · 在 review」；點開是一棵樹：主 change → 子 change，每行寫誰在做（session 或哪個 subagent）、到哪一站、卡在哪個 gate。使用者不需要任何操作。（樹狀顯示由 board-tree 實作。）

## 跟 fan-out 的差別

- 拆工（這份）：一張大卡在開工前拆成主 change 與子 change，依賴寫在 workplan，使用者確認一次。
- fan-out（`references/fan-out.md`）：一張卡合併後，`opsx chain` 找出依賴它、已經 propose 好的卡，交給同一個 pane 代管、由 subagent 做。它處理的是合併之後的續接，不決定怎麼拆。
