# 卡的等級：P0 / P1 / P2

等級由程式依寫在檔裡的事實算，agent 不選等級，只填事實。規則的出處是 workplan-priority 的 grill.md（D1–D8，使用者 2026-11-10 定）；計算在 `bin/lib/priority.py`，coordinate、chain、collect 與 `opsx priority` 都呼叫它。這份是唯一一份判斷標準，skill 只指過來，不各自重抄。

## 事實欄位

開收件卡的 agent 在 `inbox.md` frontmatter 填，平的 `key: value`、一行一個：

| 欄位 | 值 | 什麼時候填 |
|---|---|---|
| `kind_of_work` | `incident` 或 `planned` | 每張卡。壞掉、出事、擋路的是 incident；要新做或改進的是 planned。沒寫當 planned |
| `impact` | `security`、`data`、`prod_or_main`、`workaround_exists`、`blocks_all_agents`，逗號分隔，列出來的就是成立的 | 只有 incident 填；沒有就留空 |
| `evidence` | 一行：重現指令、log 位置、測試輸出；長的貼在 `## 證據`，這裡寫指向 | `impact` 有值就一定要填 |

各 impact 的意思：

- `security`：資安漏洞或權限被繞過。
- `data`：資料遺失、毀損或外洩。
- `prod_or_main`：正式環境或 main 分支壞了。
- `workaround_exists`：功能錯，但有替代做法。
- `blocks_all_agents`：流程卡住，所有 agent 都動不了。

沒有證據不能填 impact：`impact` 有值而 `evidence` 空、`kind_of_work` 或 `impact` 有值域外的字，`opsx priority` 都拒絕並說是哪個欄位、哪個值。

例：

```
kind_of_work: incident
impact: security, prod_or_main
evidence: tests/auth.test.sh 第 3 案：未登入可讀 /admin（log 貼在 ## 證據）
```

## 等級怎麼算

- incident：`security`、`data`、`prod_or_main` 任一成立（一定附 evidence）→ P0；否則 `workaround_exists` 或 `blocks_all_agents` 成立 → P1；其他 → P2。
- planned：卡在 workplan 裡、所屬 feature 的 `milestone:` 等於 `current_milestone` → P1；其他 → P2。planned 不會是 P0。
- workplan 沒設 `current_milestone`：在 workplan 裡的 planned 卡一律 P1（照舊自動派）；設了才開始依 milestone 篩（D8）。
- 不在 workplan 的 planned 卡是 P2。agent 自己開的卡預設 planned、不在 workplan，所以是 P2，等使用者升級才派。
- 依賴繼承：沿 workplan 的 `depends-on`（PR 與 feature 層）反向走，有更高等級的卡直接或間接在等它，就升到那一級，理由寫「P0：<那張卡> 在等它」。
- 使用者覆寫的卡以覆寫為準，不再往上升（見「使用者覆寫」）。覆寫只管那張卡自己，不切斷依賴傳遞。
- 等級只影響還沒派出去的卡的排隊順序；已經在跑的卡不會因為等級變動（升或降）被停、被暫停或被搶位子。P0（自己判出或繼承來的）排最前、一起派、不受每輪上限。

`opsx priority <slug>` 印 `<等級>\t<理由>`，例「P0：security（附證據）」「P1：在 <milestone>（<goal>）清單裡」「P2：不在 workplan」。

## milestone

- milestone 由各專案自己定，可以沒有。專案第一次大的 explore 跟使用者一起拆，每個 milestone 一句「做完時使用者能做到什麼」。skill 與程式不寫任何具體 milestone（D1）。
- 寫在 workplan 頂層 `milestones:`，每個有 `name` 與 `goal`；feature 用 `milestone:` 指過去：

  ```yaml
  milestones:
    - name: "<名稱>"
      goal: "<做完時使用者能做到什麼>"
  current_milestone: "<名稱>"
  features:
    - name: <feature>
      milestone: "<名稱>"
  ```

- `current_milestone` 只由使用者設，換階段時使用者改；agent 不設、不改。
- workplan 的 parser 只認一個 YAML 子集：`name` 與 `goal` 一律加雙引號，`goal` 裡有冒號不加引號會拆錯。
- `current_milestone` 或 feature 的 `milestone:` 指到 `milestones:` 沒有的名字，`opsx priority` 拒絕。

## 使用者覆寫

使用者可以改任何一張卡的等級，必須寫理由：

```
opsx priority <slug> --set <P0|P1|P2> --reason <理由>
```

它在 frontmatter 寫 `priority` 與 `priority_reason` 兩行，並記一列 decisions.tsv。agent 只在使用者回覆（gate 或對話）要求時代跑這條，`--reason` 用使用者的話；agent 不自己寫這兩行。覆寫的卡不再參與繼承往上升，但它的等級照樣傳給它依賴的卡。

## P0 審核

填完事實後跑 `opsx priority <slug>`。印出 P0、而且理由不是 `P0：使用者：…`（卡沒有使用者覆寫）時，在那張卡的 `gates.md` 寫這個 gate。使用者負責審 P0（D6）；agent-report-push 合併前，這個 gate 就是 P0 的通知。

```
## p0-review
type: decision
status: open
問題: 這張卡算出 P0（<opsx priority 印的理由>），照 P0 插隊派嗎？
已確認: kind_of_work: incident；impact: <填的值>；evidence: <填的值>
選項: 確認 P0 (Recommended) | 降為 P1 | 降為 P2
建議: <為什麼這個 impact 成立>
風險: 降級後不插隊；P2 不自動派，要使用者升級才會做
預設: 維持 P0，照 P0 派
```

跟其他 gate 一樣用 Edit 或 Write 寫，不寫 `opened_at:`。回覆的處理：

- 確認 P0：不改檔，等級本來就是算出來的 P0。
- 降為 P1 或降為 P2：接到回覆的 agent 跑 `opsx priority <slug> --set <level> --reason <使用者的話>`。
