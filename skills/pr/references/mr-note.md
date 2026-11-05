# MR/PR note 工程規範

來源：`Agentory-AI/.claude/skills/mr-note/SKILL.md`（2026-11-05 版），搬進 opsx 後所有 repo 共用；hook `mr-format-gate.sh` 擋沒照這個格式的 MR。

所有對外工程輸出零 buzzword。MR note 給工程師 review、也給 PM 讀業務層。**這個格式是定案的，不要即興發揮成作文。**

## 硬規則

1. **標題照 Conventional Commits：`<type>(<scope>): <summary>`**，純英文祈使句、一行寫完、前綴不可省。type 用 `feat|fix|refactor|docs|test|chore|ci|perf|build`；scope 用模組名。不塞括號修飾詞、不 emoji、不「— …」補充子句。MR 標題應與該分支的 commit subject 一致。
   - ✅ `feat(auth): add Google OAuth2 login support`
   - ❌ `Route bulkUpdate through the guarded bulkUpdateIssues`（漏 `type(scope):`）
   - ❌ `feat: unify tri-store ACL — single SQL predicate + consumer convergence (F040-F051)`
2. **section 標頭不准加括號解釋。** `## Changes` 就是 `## Changes`。
3. **不要把內部慣例寫成給讀者看的文字。** 表格欄位、命名規則、格式約定是你產出時遵守的規則，不是成品內容。不自造怪用詞或箭頭符號串當標頭。
4. **禁止**：emoji 標題、mermaid 勵志圖、「一句話給 PM」、「N 條鐵律」、「這波…」這類標語。
5. **section 標頭用英文**（Summary / Changes / Migrations / Test plan / Reviewer notes），**表格內容用中文**。
6. **表格是必須的**。每個變更一列，欄位固定：`編號 | 程式碼改動 | 業務層邏輯 | 對應測試`。「業務層邏輯」寫這對產品 / 使用者實際代表什麼，不是把程式碼改動用術語再講一遍。
   - ✅ `刪任務後，它在摘要檔裡那筆原本會留著（看起來像還在）；修好後刪了就從摘要移除`
   - ❌ `delete_issue 的 write-once 投影未 strip GENERATED 區的 tombstone entry`
7. 測試欄填**真實測試檔名**。opsx 的來源是 tasks.md 每個 task 的 `測試：` 那行；沒有的用 `git diff --name-only <target>..<source> | grep -iE 'test|spec'`。

## 固定結構

Summary / Changes / Test plan / Reviewer notes 四段必有。其餘段依內容判斷。

```markdown
## Summary

<2-4 句：改什麼、為什麼、範圍。技術事實，不要標語。>

Related: <issue / 上游 change / 前置 MR。有才放>

## Changes

### <子系統英文標頭>

| 編號 | 程式碼改動 | 業務層邏輯 | 對應測試 |
|---|---|---|---|
| <task 編號 / 分支名> | <改了哪個檔 / 函式，精簡> | <對使用者 / 業務的意義，白話> | <真實測試檔名> |

## Breaking changes

<破 API / schema / env / 型別 / 退役函式時才放：破了什麼、下游要改什麼。>

## Migrations

| # | 內容 |
|---|---|
| 0139 | <一行> |

Deploy notes: <順序、backfill DML、Tier-C 對齊。有 migration 就要有這行。>

## Test plan

- <怎麼驗的：merge-gate 命令、關鍵守門測試、review 結論。gate 有紅要誠實列哪幾檔紅、為什麼、誰收。>

## Reviewer notes

- 範圍界定（本線 vs 夾帶的）
- Rollback / risk（動 ACL / schema / 執法路徑時必放：最壞情況 + 怎麼退 + 風險等級）
- 已知偏離 / 未完成的設計點
- Follow-up（連到 change 名 / inbox 卡）
- Screenshots / UI（有 UI 變更時放）
```

| 段 | 放的條件 |
|---|---|
| Summary / Changes / Test plan / Reviewer notes | 一律放 |
| Related / Closes | 有連到的 issue / 上游 change / 前置 MR 才放 |
| Breaking changes | 破 API / schema / env / 型別 / 退役函式時放 |
| Migrations + Deploy notes | 有 DB migration 才放 |
| Rollback / risk | 動 ACL / 執法 / schema / 資料遷移時放 |
| Screenshots / UI | 有 UI 變更放 |

## GitLab description 更新（token 受限時）

glab 常因 token scope 卡 403。可行路徑：push option 開 MR（需該次 push 帶新 commit），或 description 用 PAT 打 REST API：

```bash
PAT=$(tr -d '\n\r\t ' < <token檔>)
curl -sS --request PUT --header "PRIVATE-TOKEN: $PAT" \
  --url "https://gitlab.tsg-navigator.com/api/v4/projects/<group>%2F<repo>/merge_requests/<iid>" \
  --data-urlencode "description=$(cat <note檔>)" -o /dev/null -w "HTTP %{http_code}\n"
```

用 `--data-urlencode "description=$(cat file)"`，不要 `description@file`（會送空值）。PUT 後**一定 GET 回來驗**長度 > 0 且含表格，HTTP 200 也可能寫進空值。
