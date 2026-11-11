# opsx-workflow 改寫要求：融合 pstack 與 grill-me

狀態：討論中，2026-11-04
範圍：`~/code/sandbox/opsx-workflow/`（plugin source）與 `~/.claude/skills/{grill-me,grill-with-docs}/`
來源：pstack v0.15.34（`~/.claude-work/plugins/cache/cursor-plugins/pstack/0.15.34/`）

## 1. 目標

opsx-workflow 保留「生命週期 + 持久化狀態」的骨架，把 pstack 的「單任務內的嚴謹度」接進每個步驟裡，並把 grill-me 收成工作流中的一個固定閘門。三者各管一層：

| 層 | 誰管 | 管什麼 |
|---|---|---|
| 外層 | opsx-workflow | 什麼時候做什麼、狀態存在 `openspec/changes/` 與 `workplan.yaml` |
| 閘門 | grill | explore 之後、propose 之前，把決策樹走完，產出編號決策 |
| 內層 | pstack | apply 實作一個 task 時怎麼做、review 時怎麼對抗、PR 怎麼寫 |

## 2. 已決定

| # | 決定 | 理由 |
|---|---|---|
| D1 | opsx 當外層骨架，pstack 當內層 | CLAUDE.md §6 已強制每個 change 走 propose → apply；pstack 沒有跨 session 的狀態模型，只有 session-pickup 和 show-me-your-work 的 tsv |
| D2 | grill 是獨立 skill，不併進 explore | explore 另有使用者；explore 已 214 行 |
| D3 | grill-me 與 grill-with-docs 合併成一個 | 兩者加上 explore 的 grilling 段落，目前是三個互相重疊的入口 |
| D4 | ~~門檻「一兩個檔案就跳過」~~ 改為：grill 是閘門，只在 explore.md 待決非空時有事（2026-11-04 改） | 小事 explore 各步 skip、待決為空，自然沒有 grill |
| D5 | grill 保留 AskUserQuestion 彈窗 | 題數靠分類規則（§4.1）降低，形式不變 |
| D6 | grill 的產出是編號決策 D1…Dn，每條帶理由與被否決的替代方案 | propose 直接抄進 design.md；review 的 spec-conformance agent 已要求 MUST_FIX 引用 D-id，形成閉環 |

## 3. 目標工作流（2026-11-04 定稿）

```
+ 收       一句話 → openspec new change <slug> --schema opsx → changes/<slug>/inbox.md
   │        開 change 殼 = 一張卡。殼不是空的：inbox.md 帶 type / source / found / 證據 / 內文
explore    發散（必經；固定步驟表，小事各步 skip）：查資料、debug、影響範圍、跑實驗 → explore.md
   │        結尾一段「待決」：只有人能答的題，每題附推薦答案；查得到、跑得出的不進這段
   ├─ 待決為空 → 直接 propose
   └─ 待決非空 → grill 閘門：一題一題答（chat 打 /grill 用彈窗，或看板上像回 gate 一樣答）→ grill.md（D1…Dn）
                  grill 不是節點，是閘門；跟 apply 裡 worker 問人的 gate 同一個機制
propose    不討論，只整理：proposal / specs / design（D1…Dn 原樣進入）/ tasks；explore 待決沒答完就擋
   │
apply      每個 task：pstack playbook 步驟進 todo → gate / inbox 卡 / decisions → commit（§5）
   │
review     spec conformance（引 D-id）+ code quality + 四桶 → report.md（§6）
   │
pr         mr-note 格式，glab / gh（§7）
   │
archive    整個目錄進 archive/
```

**順序由 openspec 本身強制**：fork 預設 schema 為 `opsx`，artifact 鏈 `inbox → explore → proposal → specs → design → tasks`，每個 `requires` 前一個。`openspec status` 自己會顯示 blocked。grill.md 不在鏈上：`/propose` 開頭自己檢查 explore.md 的「待決」段，有沒答的就停並指向 `/grill`。`/propose` 其餘不改：它本來就只產 status 裡 pending 的 artifact。

**openspec/ 在所有 repo 都不進 git**（本機工作目錄；Infra 最近那顆 `stop tracking openspec working artifacts` 就是這條）。所以卡、gates、decisions、report 全是本機檔，不另設全域 store；ADR 不需要，決定在 grill.md → design.md。

`/explore` 從「不動」改成主流程第一個節點。pstack 的 `how`、`blast-radius`、`why`、`prototype` 全掛在它的步驟表裡（§8.1）。

## 3.1 架構總覽（2026-11-04 定稿）

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  你                                                                          │
│  收 ──────▶ 挑 ──────────────▶ 等 ─────────────────────▶ 收尾               │
│  丟一句話    派 / 先 grill / 丟掉   回 gate（允許·選·打字）      merge            │
└────┬──────────┬─────────────────────┬──────────────────────────┬────────────┘
     ▼          ▼                     ▼                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  看板 = 投影，不存真相。網頁（herdr plugin 開瀏覽器）＋ herdr 右側 pane         │
│  讀：herdr agent list · workplan.yaml · tasks.md · inbox/ · gates · decisions  │
│  按：派 → dispatch.sh      回 gate → herdr agent prompt      merge → glab      │
└────┬────────────────────────────────────────────────────────────────────────┘
     │ dispatch.sh（機械：開 worktree + pane + 送 prompt + 記 dispatch.json）
     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  worker session（一個 PR 一個，自己的 worktree + herdr pane，agent 名 = PR 名） │
│  hook 注入「你在 branch X，對應 change Y，下一步 /apply」                        │
│  opsx 外層：/grill ─▶ /propose ─▶ /apply ─▶ /review ─▶ /pr ─▶ /archive        │
│              D1…Dn    changes/    task 迴圈  雙 agent+四桶  MR                 │
│  pstack 內層（每個 task）：命名 data shape → 跨邊界先 architect →               │
│    playbook 步驟逐字進 todo（skip 留痕）→ bug 先重現 → self-check → 一 change 一 commit │
│    要問人：寫 gate，繼續做能做的　　task 外的問題：寫 inbox 卡，不修             │
│  Agent subagent：test agent · review A（spec）· review B（code）               │
└─────────────────────────────────────────────────────────────────────────────┘
```

| skill | 讀 | 寫（看板靠這些檔） |
|---|---|---|
| + 收 | 一句話 / agent 發現 / GitLab issue | `openspec new change <slug>` + `inbox.md` |
| /explore | inbox.md · codebase | `explore.md`（影響範圍、相關檔、實驗結果、未確定的） |
| /grill | explore.md · CONTEXT.md | `grill.md`（D1…Dn：決定 / 理由 / 否決） |
| /propose | grill.md | `proposal.md` · `specs/` · `design.md`（D-id 原樣）· `tasks.md`；workplan.yaml（PR 名符合 `[a-z0-9_-]`） |
| /apply | tasks.md · workplan | tasks.md 勾 · commit · `gates.md` · 新的 change 殼（撈到的 bug）· `decisions.tsv` |
| /review | diff · design.md 的 D-id | `report.md` |
| /pr | report.md · mr-note | MR |
| /archive | changes/ | archive/、workplan merged |
| /dispatch | workplan · grants | dispatch.json · herdr worktree/pane/agent |

```
每個 repo（本機，openspec/ 整個不進 git）          全域（~/.local/state/opsx/）
openspec/workplan.yaml                             dispatch.json   pr → pane · agent · 開始時間
openspec/changes/<slug>/                           grants.toml     授權；Always pause 不可改
  .openspec.yaml      kind                          agents.toml     [agent.claude] [agent.codex] command
  inbox.md            收：type / source / found / 證據   bypass.log      commit 閘門逃生口紀錄
  explore.md          發散
  grill.md            D1…Dn
  proposal.md · specs/ · design.md · tasks.md
  gates.md · decisions.tsv · report.md
openspec/changes/archive/
```

看板的「inbox」段 = 只有 inbox.md 的 change；「待派」= 有 tasks.md 還沒 dispatch 的；沒有獨立的 inbox 目錄。

## 3.5 調度層：herdr 當 pstack 的「中心」

pstack 的調度中心是 `/poteto-mode` chat 加 Cursor cloud agents（orchestrate / autopilot-full：一個 PR 一個 owner，root 驗收）。Claude Code adapter 對 cloud agent 的處理是跳過，剩下的 Agent subagent 共用主 session context、不可見、主 session 結束即消失。herdr 的原語補上這塊：

| pstack 需要的 | herdr 原語 |
|---|---|
| 一個 PR 一個 owner，獨立環境 | `herdr worktree create --branch <pr.branch> --base main --label <pr>` + `herdr agent start <pr> --kind claude --pane <id>` |
| 派工 | `herdr agent prompt <pr> "/apply --auto --pr <pr>"` |
| 等 owner 完成 | `herdr agent wait <pr>`，狀態 idle / working / blocked / done |
| owner 卡在 approval | `--until blocked` → `herdr agent read` → `herdr notification show` 通知使用者 |
| 狀態看板 | pane 本身，使用者可隨時進入或打斷 |
| 跨 session 狀態 | `openspec/workplan.yaml` |

### 角色與資料

會做事的只有三種：使用者（決定哪些 PR 可做、merge）、coordinator（一個 session）、worker（每個 PR 一個 session，從 apply 到開 MR 全程負責到完成）。其餘都是資料，自己不會動。

### 跨 repo 總表（已定：看板 `collect.sh` 掃 `~/code/*/openspec/`，見 §3.6；下表留作評估紀錄）

`workplan.yaml` 是單一 repo 的，coordinator 需要一份跨 repo 的「哪些 PR 可做」總表。兩個選項：

| 選項 | 做法 | 有畫面 |
|---|---|---|
| tsk | 已裝（herdr-tsk plugin，`prefix+t`），板目前是空的。一個 PR 一筆任務 `-p <repo>`，title = workplan PR name。狀態 ready / started / blocked / review / done 與調度流程一對一；tsk 規則「agent 只能設 review，done 由人設」等於「coordinator 不 merge」 | 有 |
| 掃檔 | coordinator 直接掃 `~/code/*/openspec/workplan.yaml` 列 `pending` PR | 無，進度看 herdr pane |

### 三層

```
coordinator（一個 Claude session，跑 /dispatch，即「派工」）
  讀總表 → 挑 pending 且 depends-on 全 merged 的 PR
  → 在該 repo 開 worktree + pane → prompt → wait → 回寫總表與 workplan 狀態
  不寫 code；gate 照固定規則答；不 merge（merge 永遠人）
    │
worker（一個 PR 一個 session，一個 worktree）
  被 opsx hook 注入 branch / change / 下一步 → /apply → /review → /pr → 寫 report.md
    │
subagent（opsx apply 現有的 test agent、雙 review agent，不變）
```

大卡拆成 session / 主 change / 子 change 的四層定義與三層依賴（2026-11-10 定）見 `references/work-split.md`。

### 設計決定

- 派工表是 tsk（跨專案、人挑）+ `workplan.yaml`（單 repo、機器細節），不另發明 pstack 的 plan markdown。coordinator 只是兩者的讀者。
- 一個 PR 一個 worktree 結構性地解掉「多 session 共用 working tree 要 stage by name」的問題（pstack：separate-before-serializing-shared-state）。
- `/dispatch` 必須由使用者打，不自動觸發。herdr 的 skill 文件明定只在使用者提到 herdr 時才用。
- coordinator 不 merge，也不核准合併：merge 永遠人（板上按「合併」，或在 forge 網頁合）。實作是 `opsx coordinate`，launchd 每 5 分鐘一輪（openspec/specs/opsx-coordinate）。人合併後 coordinator 收尾，看到 merged **自動派依賴它的 PR（已定 2026-11-05）**。這是中控唯一自己做的決定，規則寫死：只派 workplan 裡 `depends-on` 全部 merged、且已有 tasks.md（propose 做過、kind 已確認）的 PR；收件匣裡的東西永遠不自動派。agent、自主程度沿用被依賴那張卡 dispatch.json 的值，kind 用該卡 `.openspec.yaml` 的；decisions.tsv 記一行「自動派：因 <父卡> merged」，開頁 banner 列出來。你在板上可以「停止」它。
- coordinator 只替派出去的卡答 gate，照固定規則：授權題允許這次、真機驗證題標成等使用者驗、等別張卡的題不答並停 pane、要人動手的題不答。worker 的 `blocked` 狀態（終端機等輸入）不代答，只在 log 記 `??`。
- `/dispatch` 是 skill 帶一支 `dispatch.sh`：派工與 wait 的迴圈是確定性的交給腳本，worker 回報的判斷留給 skill。
- coordinator 只關閉自己開的 pane 與 worktree。

> 整包的 ASCII 總覽（角色與層 · 資料 · 一張卡的一生 · hook · 自主程度 · 四種待處理）在 Obsidian 工作 vault `01-Projects/opsx 架構總覽.md`（2026-11-05 核對過）。

## 3.6 看板：人機協作的最外層（自製，herdr plugin + 網頁）

決定：看板自己寫，不用 tsk / herdr-board / portal / vibe-kanban 的調度；調度是 opsx 自己的 `/dispatch`。看板可以派工，按鈕接的是同一支 `dispatch.sh`。已評估不採用：tsk（有內建 dispatch + coordinator skill，但調度不在自己手上，TUI 無法改樣式）、herdr-board（188 stars，Rust，daemon 自己派工）、herdr-portal（已裝，純監看，長相一般）、vibe-kanban（全包但取代 herdr）、Backlog.md（與 openspec 重複）、agentboard（2 stars、tmux）。

### 設計原則（從 pstack / openspec / grill 撈出來的人機分工）

- 最外層只回答兩個問題：**現在什麼在等我**、**我沒看的時候發生了什麼**。其餘是背景。
- 只有「只有人能做的事」才進「等我」：產品選擇、核准、merge、不可逆動作、授權、dead end（pstack ketchup）。每一項要能從卡片本身就做決定：連結、對使用者改變什麼、證據、風險、agent 的建議、沒回答時的預設（pstack gates.md）。
- 授權問一次（merge / push / deploy / credentials），之後不再問。Always pause 清單不可授權掉：force-push 共用分支、deploy、刪資料、對客戶發話（pstack autonomy）。
- 只在有追蹤到的變化時報告：PR 開了、verdict、merge、agent 卡住 + 已採取的動作、blocker 增減、替你做的決定。沒變化就靜默（pstack orchestrate tick）。
- 每個 PR 宣告模式：interactive / autopilot / drive（到 merge-ready）/ check。核准是等待不是阻塞，merge 永遠要人明說（pstack babysit）。
- agent 替你做的每個決定留一行 decisions.tsv；每個 PR + SHA 一個驗證 verdict（ledger）。「有沒有驗過」看 ledger（pstack show-me-your-work）。
- 板是 cache，不存狀態；每次開板重讀三個來源：本機 `openspec/`（卡、節點、gates、decisions、report）、herdr（agent 狀態、pane）、git / GitLab（branch、MR、merged）。空板給最多兩個下一步建議（opsx status）。
- worker 要問人時不在終端等，寫一個 gate 然後繼續能做的事（never-block-on-the-human 在此架構的落點）。

### 卡片模型

一張卡 = 一件工作。工作流節點只是其中一個屬性，不是欄位。

```
card
├ 身分    repo · 標題 · kind（七種，§8.1）· 來源（agent:<pr> / me / gitlab#N）
├ 工作流  節點：inbox → explored → proposed → planned → dispatched → review → mr → merged
│         不存，從檔案推：changes/ 存在 = proposed，在 workplan = planned，在 dispatch.json = dispatched，
│         有 report.md = review，有 MR = mr，workplan merged = merged
├ 等你    四種（已定 2026-11-05），各自的來源和按鈕：
│         ① 等待授權  gates.md type=approval  → 允許這次 / 這張卡 / 這個 repo 永遠 / 拒絕 / 打字
│         ② 等待決定  gates.md type=decision  → 選項按鈕 / 打字
│         ③ 可以合併  collect.sh 推的，不是 gate：report.md 有 MR URL ∧ glab state=opened 非 draft
│                     ∧ has_conflicts=false ∧ pipeline success ∧ 未解 threads=0 → 合併（glab mr merge --squash）
│                     少一個條件就不進等你，留在進行中，顯示「MR 卡在 X」，動作是叫 /babysit
│         ④ 終端機等待輸入  herdr agent_status=blocked 且 gates.md 沒對應項：Claude Code 自己的權限框
│                     板答不了（herdr 文件：去 pane 看再按）→ 開啟 pane / 停止 / 重新指派。
│                     照規則不該發生（要授權的動作應寫 gate），出現 = skill 漏了，但仍列進等你
│         每項帶：問題 · 選項 · agent 建議 · 證據 · 風險 · 沒回答的預設
├ 授權    生效的 grants 與模式（interactive / autopilot / drive / check）
├ 執行中  agent 家 · pane · `status.json`（phase · step/total · label · at，見「新增的儲存」）· herdr agent_status · `agent read` 最後幾行
├ 證據    changes/ · adr · report.md · MR · decisions.tsv · ledger verdict
└ 變化    上次看板之後的追蹤事件
```

「等你」是卡的狀態，任何節點都可能同時「等你」。

**畫面用字（已定 2026-11-05：標準詞，不用自創的）**：本文件裡的 要你 / 在跑 / 待派 / inbox / 完成 在畫面上寫成 **待處理 / 進行中 / 待指派 / 收件匣 / 已完成**；動作寫成 **指派 / 先 explore / 捨棄 / 合併**（explore 是指令名，保留）；四種等你寫 **等待授權 / 等待決定 / 可以合併 / 終端機等待輸入**。文件內部用詞不改，只改畫面。

### 人的工作流（已定，2026-11-04）

畫面從這四步推出來，不從機器狀態推。tab、卡、動作都只能是這四步的投影，不會再長。

```
收 ──▶ 挑 ──▶ 等 ──▶ 收尾
```

| 步 | 人做什麼 | 對應 tsk | 對應 pstack |
|---|---|---|---|
| 收 | 什麼都先進 Inbox，不處理。來源：我隨手丟、agent 撈到的 bug、GitLab 同步的 issue | `open`（inbox，captured not yet picked） | autonomous-run 第 4 步：mid-run 發現不修 task 外的事，寫下來 |
| 挑 | 看 Inbox，決定：派給誰 / 先 grill / 不做 | `ready`（picked, up next）由人設 | coordinator skill：一個 task 一個 builder，一次問清授權（grants） |
| 等 | agent 在跑。要人時卡浮到最上面，人回一下 | `started` / `blocked`（agent 設） | ketchup action item：只有人能做的事才算；gate 卡上帶建議 / 證據 / 風險 / 沒回預設；never-block-on-the-human：worker 寫 gate 後繼續做能做的 |
| 收尾 | MR 好了人 merge | `review`（agent 設，done by the agent waiting on you）→ `done`（只有人設） | babysit 第 9 步：approval is a wait, merge 永遠要人明說；Always pause 清單 |

tsk 規則照抄：**agent 只能把卡推到「等你 merge」，done 永遠是人按的。**

### 一個畫面，照 tsk 的結構（取代三個 tab）

tsk 的板：頂上一列範圍 `desk · <user> ▾ · projects`，下面分段 NEEDS YOU / IN MOTION / ON DECK，inbox 摺在最底。照抄：

```
全部 · <workspace> ▾                    ← 範圍：全部 / 一個 workspace / 它底下一個 repo（「依 agent」拔掉，2026-11-05）
要你 ────────────                      ← 紅，最上面
在跑 ────────────
待派 · <workspace> ───                   ← 挑過要做、還沒派
▾ inbox · N                            ← 摺疊，展開看三種來源
▸ 完成                                  ← 摺疊
```

**範圍兩層：workspace → repo（已定 2026-11-05）。** 卡的歸屬永遠是 repo + slug（殼在 `~/code/<repo>/openspec/changes/`，herdr 沒開卡還在）；人看板的單位是 herdr workspace，一個 workspace 可以掛好幾個 repo（例如 `develop` 掛 Agentory-AI、Agentory-CS、Agentory-Infrastructure）。選單：

```
全部
develop ▾      Agentory-AI · Agentory-CS · Agentory-Infrastructure
gmtc-rag       gmtc-rag
沒掛的         scam-guard            ← 有 openspec/ 但沒掛到任何 workspace 的 repo
```

選單在首頁和收件匣就地展開、就地篩選，不跳頁。

選 workspace 看整組，選底下一個 repo 看單一 repo。repo ↔ workspace 的對應 herdr 推不出來（它只有 pane 的 cwd，而 cwd 常是家目錄），所以表是 opsx 自己的：`~/.local/state/opsx/workspaces.toml`。兩個來源餵它：`/dispatch` 把卡派進某個 workspace 時自動記 repo ↔ workspace；看板「workspace」頁（授權頁旁邊）手動掛、搬、拆。派工時 pane 開進該 repo 掛的 workspace；沒掛 → 新開一個以 repo 命名的 workspace 並記下來。

**agent 怎麼對到卡：不經過 cwd。** `/dispatch` 自己開 pane，寫 `dispatch.json`：`{ card: <repo>/<slug>, workspace: w2, pane: 9, agent_session: <id> }`。看板用 pane id / session id 去 `herdr agent list --json` 對狀態（活著嗎、等輸入還是在跑、最後動靜）。你手動開的 agent 不在 dispatch.json，板上掛不到卡，列在「進行中」最底一行「沒對到卡」，不猜 repo。

網頁和面板同一個結構。面板是它的 mono 版，一行一卡；網頁的列多一句問題 + 建議 + 按鈕。

**收件匣獨立成一個 tab（2026-11-05 改，推翻上面「摺在最底」）**：網頁頂列兩個 tab，**首頁**（待處理 / 進行中 / 待指派 / 已完成）和 **收件匣**（帶未處理數；＋新增、上次同步 · 立即同步、四組來源都在這頁）。範圍選單兩個 tab 共用。面板仍是一份清單、收件匣摺在底，因為 pane 沒有 tab。

不是分段的：
- 「變了什麼」= 開頁時頂上一條 banner「離開期間 …」，只列追蹤到的變化（pstack orchestrate tick 規則），看完關掉。**列什麼（已定 2026-11-05）**：新開的 gate、新開的 MR、merged、agent 停了或 blocked、agent 替你做的決定、自動派出的卡。**不列**：進度步數、沒有新卡的同步、你自己按的事。只算上次開板之後（`~/.local/state/opsx/last-seen` 時間戳）；關掉就不再出現
- 「紀錄」有兩層（2026-11-05 改）：點開一張卡看它自己的 decisions、ledger、report；另外網頁第三個 tab **紀錄**，跨卡的時間軸，來源是每張卡的 `decisions.tsv` + `dispatch.json` 的時間 + 同步腳本的 log + archive。一行一事件：時間 · 卡（可點）· 誰（你 / agent 名 / 系統）· 做了什麼 · 標籤（已允許 / 已決定 / 替你決定 / 已指派 / 已合併 / 同步 / 驗證）。按日分組，篩選四種：全部 / 你回的 / 替你做的決定 / 指派與合併。範圍 ▾ 同樣作用。面板不做紀錄

### 一張卡

```
[精靈]  標題                         repo · 多久了
        要你：問題一句 · 建議一句      [主按鈕] [次按鈕]
```

列表只有這些。其餘（證據、風險、沒回預設、工作流節點、playbook 步驟、report、decisions）點開才看。

### 動作，五個

| 在哪 | 動作 | 背後 |
|---|---|---|
| Inbox 卡 | **派** | 選誰去（claude / codex）、多自主（互動 / 自動＝開到可合併）、**kind**（七種，預設從來源提示猜）、**模型**（已定 2026-11-05：預設照 kind 給，dev / refactoring / perf / experiment → opus 5.5，bug-fix / chore / ops → sonnet 5.5，可以改；codex 只有 gpt-5）→ `dispatch.sh`：worktree + pane + `agent start … -- --model <id>` + prompt，kind 寫進 `.openspec.yaml`，model 記在 dispatch.json |
| Inbox 卡 | **先 explore** | herdr 開 pane 跑 `/explore <卡>`（explore 做完待決非空，同一個 pane 接 `/grill`） |
| Inbox 卡 | **丟掉** | status: dropped |
| 進行中卡 | **回它** | 按建議或打字 → `herdr agent prompt`；gate 關；記 decisions 一行 |
| 進行中卡 | **merge** | 只有人；`glab mr merge`；卡 → 完成 |

全頁：**+**（丟一句話進 Inbox，建殼寫 `changes/<slug>/inbox.md`）。停 / 重派在卡展開後的小字。

**授權和同步不在頂列（已定 2026-11-05）**：授權的三個答案在 gate 上；「這個 repo 永遠」那份（`grants.toml`）跟著 repo 範圍走：範圍選到單一 repo 時分段上方多一行「此 repo 長期授權：push · 建立 MR ｜ 管理」，在那裡收回；merge 永遠不可勾。同步只影響收件匣，所以「上次同步 13:40 · 立即同步」放在收件匣標題列右邊，單向。repo ↔ workspace 的掛載在範圍選單裡 repo 旁邊直接改，不另開頁。頂列只剩：範圍 · 待處理數 · ＋。

**點開一張卡看到的（依資料來源排）**：頭（repo · branch · agent · mode · pane）→ 等待你（有才有）→ 進度（status.json 的 phase · step/total · label；apply 時再附 tasks.md 勾選）→ 最後輸出（`herdr agent read --lines 10`）→ 合併請求（glab 五個條件逐條打勾，哪個沒過一眼看到）→ 紀錄（decisions.tsv · report.md ledger）→ 小字：開啟 pane · 停止 · 重新指派 · 檔案路徑。

### 面板（herdr 右側 pane）

同一份清單、同一個分段結構（要你 / 在跑 / 待派 / ▾inbox / ▸完成），一行一卡，要你的在上。`↑↓` 選、`Enter` 跳 pane、`o` 網頁開這張、`+` 丟 Inbox、`Tab` 換範圍、`z` 全屏、`q` 關。不在面板回 gate、不派工。

### 已作廢

六視角、分組 chip、存排列、精靈圖鑑、三方向比較：全部多餘，不做。設計系統擇一即可。**已定 2026-11-05：Open Design 的 `mission-control`**（`/Applications/Open Design.app/Contents/Resources/open-design/design-systems/mission-control/`）：深色單一主題（navy `#0B1120` / 面板 `#111827`）、amber `#FFB800` 給資料與待處理、cyan `#00D4FF` 給主要動作、紅 `#FF4757` 給錯誤、綠 `#26DE81` 給正常；Inter 標籤、JetBrains Mono 所有資料；圓角 ≤4px；badge 全大寫 10px；只有警示和狀態會動。精靈改科技風：晶片形外框、LED 眼睛，廠商色只在邊框和 LED。

### 授權三級（已定 2026-11-04）

| 級 | 意思 | 動作 |
|---|---|---|
| **直接做** | 可逆、本機、不影響別人。worker 不問 | 讀檔、改 worktree 裡的檔、跑測試 / lint / build、commit 到自己的分支、寫 inbox 卡 / gate / decisions、開子 agent |
| **要授權** | 碰共用的東西或有副作用，但可收回。沒授權 → 寫 gate 等人 | push 分支、開 MR、改 MR description、本機 `db:migrate` / `db:reset`、刪檔、裝套件、呼叫 LiteLLM 以外的外部 API、測試檔放非慣例位置、寫 `.env.*`、`git rebase` 自己的分支 |
| **永遠要人** | 不可逆或對外。pstack Always pause，任何授權蓋不掉，一律 gate | merge、deploy、force-push 共用分支、刪資料 / drop table、對客戶或外部人發話、改 CI、改 secrets |

**怎麼授（已定）**：不預先分類。每個動作每張卡預設都問，gate 卡上三個答案：

| 答 | 效果 | 記在哪 |
|---|---|---|
| 這次 | 只放這一個動作 | 不記 |
| 這個 session | 這張卡跑完前同一動作不再問 | `dispatch.json` 那張卡底下 |
| 這個 repo 永遠 | 以後這個 repo 任何卡都不問 | `grants.toml` |

第一級不記、第三級不可記。收回：看板「授權」頁刪。

### 兩種自主程度怎麼實作（已定 2026-11-05；2026-11-06 由三種收成兩種）

模式存在 dispatch.json，`dispatch.sh` 照模式起 agent，router hook 照模式注入一句行為規則。查過 CLI：Claude Code 有 `--permission-mode`（acceptEdits / auto / bypassPermissions / manual / dontAsk / plan）、`--allowedTools` / `--disallowedTools`、`--settings <json>`；codex 有 `-a/--ask-for-approval`、`-s/--sandbox`。舊值 `drive` 一律讀成「自動」。

| 模式 | claude 怎麼起 | codex 怎麼起 | opsx 這邊 |
|---|---|---|---|
| 互動 | 預設 permission mode，Claude 自己的權限框照跳，人在 pane 按 | `-a on-request -s workspace-write` | router 注入「interactive：要授權就直接問，不寫 gate」。板上的 blocked 是正常的「終端機等待輸入」 |
| 自動（開到可合併） | `--permission-mode dontAsk` + `--settings` 一份 dispatch.sh 產的 JSON：allow 直接做那級（讀寫 worktree、`pnpm test*`、`git commit*`、常用唯讀與測試指令…）、deny 永遠要人那級（`git push --force*`、`deploy.sh*`…）。「這個 repo 永遠」的授權也渲染進 allow。不在 allow 的指令直接被拒、不跳框，agent 繞過去或寫 gate | `-a never -s workspace-write`；sandbox 擋網路，push 本來就出不去 | **PreToolUse `opsx-grant-gate.sh` 是真正的閘門**：要授權那級的指令進來，查 `grants.toml`（repo 永遠）和 dispatch.json（這張卡）；有授權放行，沒授權回 deny，deny 訊息就是「寫 gates.md 然後做能做的」。router 注入「autopilot：要問人的寫 gates.md，不用 AskUserQuestion」；explore / grill / propose 對產品取捨或不可逆的題寫 gate，其餘採 Recommended 記「自動採用」。dispatch 一律起 `drive.sh <slug>` 迴圈（pid 由 drive 自己寫進 dispatch.json，手動跑的也算）：`herdr agent prompt "/<stage> <slug>" --wait` 等 settled → 重讀 `changes/<slug>/` 狀態（跟 hook 的 Router 表同一張）→ … → `/babysit` → 五個合併條件全綠就停（merge 永遠你）。中途開了 gate 就 `herdr agent wait --until working` 再等 settled。herdr 錯誤不空轉：`agent_not_found` 結束、`agent_blocked` 阻塞等人、其他等 poll 秒。同一個 `/stage` 連送兩次階段沒動，就寫一個「drive 卡在 /X」的 gate 等人。**等待一律用 `herdr agent wait` 阻塞，不准定時 prompt 問「好了沒」**（已定 2026-11-05；每一句 prompt 都是一輪 token，輪詢一天會多吃幾 M）。「停止」= kill 迴圈 + `herdr agent stop`。codex 沒 hook，靠 AGENTS.md 同一段文字 + sandbox，弱一級 |

`--permission-mode auto` 語意沒查，不用。acceptEdits 會對 allow 以外的指令跳框，pane 變 blocked，drive 送不進 prompt（2026-11-06 真機三張卡各空轉 200 輪），所以自動改用 dontAsk。

### 新增的儲存（其餘皆投影）

1. `changes/<slug>/inbox.md`：收件卡，建殼時就寫。frontmatter：type / source / found / related；內文帶證據。`source` 六種（已定 2026-11-04）：

   | source | 誰寫 | 怎麼進來 |
   |---|---|---|
   | `me` | 你按 + | 一句話 + 時間 |
   | `agent:<pr-name>` | worker 撈到 task 外的問題 | 自動，帶證據和它正在做的 PR |
   | `gitlab:<repo>#<iid>` | 同步腳本 | `glab issue list`，AI / CS / Infra / evals / gmtc |
   | `github:<repo>#<n>` | 同步腳本 | `gh issue list`，scam-guard / Skills |
   | `obsidian:<path>` | 同步腳本 | 掃 `sources.toml` 指定的 vault 資料夾（`/opsx init` 時填，已定 2026-11-05） |
   | `customer:<id>` | 同步腳本 | 內部平台的客戶回報：base URL、token 的環境變數名、列表端點都在 `sources.toml`（`/opsx init` 時填）；沒填就不啟用這個來源 |
   | `paste` | 你按 + 時附上 | 轉貼的檔案 / 文字 / artifact 連結。內容原樣存 `changes/<slug>/attachments/`，inbox.md 引用 |
   | `shortcut:<file>:<line>` | ponytail-debt 掃描 | code 裡刻意留的 `shortcut:` 註解（見搬遷清單 §6） |

   同步一律單向：拉進來變卡；卡走到 MR 時回原處留一行連結，不回寫狀態。每個來源一支腳本，放 `opsx-workflow/herdr-board/sync/`。

   **註冊 → 每天撈 → 去重**（已定）：
   - 註冊：`~/.local/state/opsx/sources.toml`，列哪些 gitlab / github repo、哪個 obsidian 資料夾、customer 平台的連線。沒註冊的不撈。**由 `/opsx init` 問答產生（已定 2026-11-05）**：plugin 第一次裝、或你打 `/opsx init` 時逐項問（gitlab / github 從 `~/code/*/.git` 的 remote 自動列、obsidian 資料夾路徑、customer 平台三個欄位），寫檔後印回來；改設定就再跑一次。
   - **沒有 repo 的來源（obsidian、customer）：同步時不建殼，先放 `~/.local/state/opsx/unfiled/<slug>.md`**（已定 2026-11-05，「我分類，它要問」）。收件匣多一組「待分類」，列上第一個動作是選 repo（下拉），選了才建殼搬進該 repo 的 `changes/`，之後跟別的卡一樣。指派、先 explore 對待分類的卡不可按。
   - 排程：每天一次（launchd，跟 `daily-obsidian-sync` 同一套做法），看板「同步」按鈕是手動觸發同一支。
   - 去重：以 `source` id 為鍵（`gitlab:Agentory-CS#412`），已存在於任何 repo 的 `changes/`（含 archive/）就不再建殼；原 issue 有更新只改那張卡的 inbox.md，不開新卡。不同來源講同一件事（例如 GitLab issue 和 agent 撈到的是同一個 bug）不自動合，看板「併進既有的卡」由人按。
2. `changes/<slug>/gates.md`：worker 要問人時寫；關閉時在 decisions.tsv 補一行。
3. `grants.toml`：`~/.local/state/opsx/`，每 repo × 動作（push / mr / migrate）一個布林，只收「這個 repo 永遠」那級；「這張卡」那級在 dispatch.json。見 §3.6 授權三級。
4. `dispatch.json`：`~/.local/state/opsx/`，執行期。每張派出的卡一筆：card（repo/slug）、workspace、pane、agent_session、mode、這張卡層級的 grants。
5. `workspaces.toml`：`~/.local/state/opsx/`，repo ↔ herdr workspace 對應表（見上「範圍兩層」）。
6. `changes/<slug>/status.json`（已定 2026-11-05）：`{ "phase": "apply", "step": 4, "total": 8, "label": "實作 + self-check", "at": "2026-11-05T15:03:00+08:00" }`。**來源是這個檔，不是 Claude Code 的 todo 檔**（路徑不穩、codex 沒有）。誰寫：每條 skill（explore / grill / propose / apply / review / pr）每一步結束跑 `opsx status <phase> <n>/<total> <label>`，claude、codex 都一樣；同一支指令在 `HERDR_ENV=1` 時順手 `herdr pane report-metadata --source opsx <pane> --tokens phase=… step=…`，讓 herdr 側欄也看得到，但那只是鏡像。重複寫同值無害。每條流程表的「產出」欄視同多了這個檔。
7. openspec 的 `opsx` schema：`openspec schema fork spec-driven opsx`，加 inbox / explore / grill 三個 artifact。

### 對其他 skill 的要求

- `/dispatch`：agent 名 = PR 名；寫 dispatch.json。
- `/apply`：超出 task 範圍的問題不修，寫 inbox 卡；收尾寫 report.md；要問人時寫 gate 不阻塞。
- `/explore`：PR 名符合 `[a-z][a-z0-9_-]{0,31}`。

### 形態

**CLI helper `bin/opsx`（已定 2026-11-05）**：plugin 帶一支 bash 入口 `bin/opsx`，子命令各一檔在 `bin/lib/<cmd>.sh`；plugin 裝好不會上 PATH，所以 `/opsx init`（slash）第一次跑時 `ln -s <plugin root>/bin/opsx ~/.local/bin/opsx`，之後終端機直接 `opsx …`，slash 和 shell 同一支腳本。目前 plugin 沒有任何 helper（只有 skills / hooks / agents），這是從零寫。

```
opsx init            在 repo 根目錄跑（沒 .git 就拒絕）
  ├ 沒 openspec/     → openspec init --tools claude
  ├ schema           → openspec schema fork spec-driven opsx 是 **repo 層**的（寫到 openspec/schemas/opsx/，查過 openspec 1.3.1），
  │                    所以每個 repo 都做一次；fork 後插入 plugin 帶的 schemas/opsx/artifacts-head.yaml（inbox / explore / grill）
  │                    + 覆蓋 templates/{inbox,explore,grill,tasks}.md，proposal 改成 requires explore，再 openspec schema validate
  ├ 不進 git         → openspec/ 寫進 .git/info/exclude（不動 .gitignore，跟 worklog 一樣）
  ├ 登記 repo        → 讀 git remote，gitlab / github 自動填進 sources.toml
  ├ 掛 workspace     → 問一次：這個 repo 掛哪個 herdr workspace → workspaces.toml
  └ 印出做了什麼；重跑是 no-op
opsx init --global   第一次裝 plugin 時跑一次
  ├ ln -s bin/opsx → ~/.local/bin/opsx
  ├ ~/.local/state/opsx/{sources,grants,workspaces}.toml 建空檔
  ├ 問 obsidian 資料夾、customer 平台三個欄位（跳過就不啟用）
  ├ launchd：每日同步（照 daily-obsidian-sync 那套）
  └ herdr plugin link 看板
opsx status <phase> <n>/<total> <label>   skill 每步呼叫，寫 status.json；HERDR_ENV=1 時順手 pane report-metadata
opsx dispatch · opsx sync · opsx board    後面階段才寫
```

herdr plugin（薄）：manifest 一個 action `open-board` + `collect.sh`（`herdr agent list --json` + 掃 `~/code/*/openspec/` + 讀 `dispatch.json`、`workspaces.toml`）+ 本機 server 開瀏覽器。repo 清單只來自掃目錄，herdr 不提供 repo 資訊。網頁是好看的部分。放 `opsx-workflow/herdr-board/`，`herdr plugin link` 掛上。herdr 的 pane 只能是終端程式，所以 TUI 只做最小操作面，主畫面在網頁。

### 前置條件

- coordinator session 的 sandbox 必須放行 `~/.config/herdr/herdr.sock`。本次討論的 session 被擋（`herdr status` 回 PermissionDenied），這是 settings 層設定。
- worker 的 permission 模式決定它能自主多久（§9）。
- `HERDR_ENV=1` 才能用 herdr 命令；coordinator 必須在 herdr pane 內啟動。

## 4. grill（新 skill，取代 grill-me 與 grill-with-docs）

### 4.1 問出口前先分類

每一題在問使用者之前先歸類，只有第三類才問：

1. 查 codebase 能答 → 自己查（grill-me 現有規則）
2. 跑一次能答（行為、時間、layout、輸出、perf）→ 自己跑，用 pstack 的 prototype playbook，結果決定答案（pstack Non-negotiables 第二條）
3. 只有使用者能答（產品、偏好、風險胃口）→ AskUserQuestion，2–4 個具體選項，第一個是推薦答案並標 `(Recommended)`（grill-with-docs 現有規則）

### 4.2 行為

- 一次一題，等答案再下一題（grill-me 現有）
- 每題 2–4 個具體選項，不出 Yes / No（grill-me 現有）
- 開場先載入 CONTEXT.md / CONTEXT-MAP.md、`docs/adr/`、`openspec/workplan.yaml`（grill-with-docs 現有）
- 使用者用詞與 CONTEXT.md 或程式碼不一致時當場指出（explore 現有，複製一份）
- 不給回答用的簡寫 token，使用者用自己的話答（pstack）

### 4.3 門檻

沒有獨立門檻。grill 只在 explore.md 的「待決」段非空時有事做；空的就沒有 grill 這一步，`/propose` 直接走。打 `/grill` 而待決為空 → 回一句「沒有待決」就停。

### 4.4 產出

```markdown
## 決策
- D1 <決策一句話>
  - 理由：
  - 否決：<替代方案> 因為 <原因>
- D2 …

## 未決
- <只有跑了才知道的事，附預計怎麼驗證>
```

決策同時寫入 `docs/adr/`（grill-with-docs 現有行為）。propose 讀這段生成 design.md 時 D-id 不重編。

### 4.5 位置

已定：放 `opsx-workflow/skills/grill/`，隨 plugin 安裝。user-level 的 `grill-me`、`grill-with-docs` 刪掉；`/explore` description 的「grill me」trigger 詞拿掉。**opsx plugin 裝進所有開發中的 repo**（含 agentory-evals、gmtc-rag，不只 Agentory-Skills installer 蓋的三個），以後只用這個 plugin 做開發。

## 5. apply 改寫要求

### 5.1 每個 task 的實作步驟

在 6i / 6a「Make the code changes」之前插入：

1. 命名這個 task 的 data shape 與組織結構（state machine / table / typed model），寫進 todo（pstack：model-the-domain）
2. 改動跨 function 邊界 → 先出 type / signature 草圖再填 body（pstack：architect，去掉 arena 多模型部分）
3. 依 kind 載 playbook（§8.3；七種 kind 見 §8.1）
4. bug-fix 先重現再修，拿到 runtime 證據（pstack：bug-fix playbook、fix-root-causes）

### 5.2 保留 opsx 現有

- 一個 change 一個 commit，不採 pstack 的「commit liberally 再 rebase」
- 自我檢查四個 grep
- 測試 agent、2 次修復上限、scope guard
- workplan 更新

### 5.3 回覆格式

採 pstack「Writing the reply」：短句、每個 claim 同句帶證據或標 measured / inferred / guess、先講對使用者和維護者的影響。點名哪條原則改變了哪個決定，只引用本 session 讀過的。

## 6. review 改寫要求

- 保留雙 agent（spec conformance + code quality）與證據不足自動降級
- 合併階段加 pstack interrogate 的 lead judgment：每條 finding 歸入 Act on / Consider / Noted / Dismissed，附一行理由；兩個 agent 不約而同的 finding 標為高訊號
- 第三個對抗式 reviewer：**加，用 pstack 的 `interrogate/references/reviewer-prompt.md` + `rubric.md` 當 Agent C，每次都跑**（已定 2026-11-05；原本只在設計有爭議時才跑）。三個 agent 分別是：A = 你的 opsx review 的 spec conformance（D-id、non-goal、勾的 task 真做了）；B = 你的 code quality + ponytail-review 六類（bug / 安全 / 負載 / 沒測試的風險 / 慢 / 多餘）+ pstack 的 code-quality lens；C = pstack 的對抗式 reviewer：站在「這個改法是錯的」那邊，攻擊前提、找替代方案、問什麼情況下會壞，外加測試先行後多一題「測試有沒有真的證明驗收條件、邊界漏了哪個」。三份 finding 一起進 lead judgment 四桶。

## 7. pr 改寫要求

現況：`~/.claude/skills/pr` 與 opsx `skills/pr` 是同一個檔（md5 相同），只會 `gh`，body 泛用。定案格式 mr-note 只存在 `Agentory-AI/.claude/skills/mr-note/`，`~/.claude/hooks/mr-note-reminder.sh` 只提醒不載入。pstack opening-a-pr 的 body 與 mr-note 衝突且內容已被涵蓋，一項不採。

拆成兩層後合併進 opsx：

- **格式層**：mr-note 內容原封搬到 `skills/pr/references/mr-note.md`，含 glab 403 時走 REST API 的方法。格式規則以該檔為準，不在 SKILL.md 複述。
- **動作層**：`/pr` 只剩機制，步驟表：
  1. `Read references/mr-note.md`
  2. 收 commits：`git log --oneline <base>..HEAD`，撈測試檔：`git diff --name-only <base>..HEAD | grep -iE 'test|spec'`
  3. 判斷 forge，一個 session 只判斷一次（pstack）：有 `gitlab` remote 或 origin 指向 gitlab.tsg-navigator.com → `glab mr create`，否則 `gh pr create`
  4. 標題 = 分支 commit subject，Conventional Commits
  5. 寫 description，寫完 GET 回來驗長度與表格
- 不採 pstack「never draft」，draft 交給使用者
- 收尾：刪 `~/.claude/skills/pr`；`Agentory-AI/.claude/skills/mr-note/` 改為指向 plugin 或刪除；hook 提醒文字改指 plugin 路徑

## 8. pstack 採用與不採用清單

### 採用

| pstack 項目 | 進到哪 |
|---|---|
| AskQuestion 前先分類（事實不問人） | grill §4.1 |
| 推薦答案 | grill §4.1 |
| ~~門檻「一兩個檔案就跳過」~~ 改為待決段為空即跳過 | grill §4.3 |
| model-the-domain、architect（單模型版） | apply §5.1 |
| bug-fix playbook、fix-root-causes | apply §5.1 |
| Writing the reply 格式 | apply §5.3、grill 總結 |
| interrogate 四桶 lead judgment、不約而同 = 高訊號 | review §6 |
| forge 一個 session 只決定一次 | pr §7 |
| playbook 機制：入口由人打、子件用 Read 路徑、步驟逐字進 todo、跳過留 `skip:` | 全部 skill §8.5 |
| encode-lessons-in-structure：規則寫成 hook 不寫成文字 | §8.5 |
| prove-it-works：對真實產物驗證，不接受「it compiles」 | apply 測試步驟的說明文字 |
| 24 條原則 | 作為 reference 供 apply / explore 引用，碰到才讀（§8.2 已定） |

### 不採用

| pstack 項目 | 原因 |
|---|---|
| 多模型 panel（opus + grok） | Claude Code 裡 grok 映射成 inherit-parent，全是 Claude，分歧變成只有 effort 差異 |
| `/deslop`、`control-ui`、`control-cli`、Bugbot、Cursor Automations | 來自 cursor-team-kit，此環境沒有 |
| multi-phase-plan 的 10 條 live lane + perf 雙邊 gate | 針對有 UI 控制 skill 的環境設計；opsx 的 workplan.yaml 已承擔 plan 角色 |
| commit liberally 再 rebase | 與一 change 一 commit 衝突 |
| never draft、`gh` 寫死 | 主遠端是 GitLab |
| never-block-on-the-human 當預設 | 與 grill 的存在目的相反；只在 grill 的分類規則裡採用其精神 |
| opening-a-pr 的 body 結構 | 與 mr-note 定案格式衝突，內容已被 mr-note 涵蓋（Rollback / risk ≈ Blast Radius，Reviewer notes ≈ Scope） |
| 回覆不用長破折號、冒號不當連接詞 | 風格偏好，不強制 |

## 8.1 Skill 架構：主流程 + 平行流程（2026-11-04 定稿）

```
入口 router（hook，每次 prompt；§8.5）
  讀：prompt 本身 · branch → change → .openspec.yaml 的 kind · tasks.md 進度 · workplan
  沒特別指定 → 主流程當前節點；prompt 明說 → 對應的平行流程
  │
  ├─ 主流程（預設；節點固定，一個不能少，順序不能換；順序由 openspec opsx schema 強制）
  │    收 ─▶ explore ─▶ propose ─▶ apply ─▶ review ─▶ pr ─▶ archive
  │              └ 待決 → grill 閘門（不是節點）┘
  │    每個節點 = opsx 現有 SKILL.md 步驟 ＋ 掛進該節點的擴充步驟
  │
  └─ 平行流程（各自由別的 skill 組成；有自己的入口；做完接回主流程某點，或不接）
       babysit · pickup / pause · perf · dispatch · UI · correct / reflect
```

**不耦合**：用到的 pstack / ponytail 檔**複製進 opsx，變成 opsx 自己的 skill 或 reference**，不保留上游的目錄巢（2026-11-05 定：plugin 裡不放 `vendor/`）。來源與版本記在 `UPSTREAM.md`（每個檔一行：本地路徑 ← 上游路徑 @ 版本），升版時拿這張表逐檔 diff。文內 `<pstack>` 一律指 `UPSTREAM.md` 列的那個本地檔。Cursor 專有步驟照 `references/harness-claude-code.md` 跳過並印 `Skipped in Claude Code`。

目錄（只這些，其餘不搬）：

```
opsx-workflow/
  skills/
    explore/ grill/ propose/ apply/ review/ pr/ archive/ status/ dispatch/   opsx 本體
    how/ why/ blast-radius/ architect/ interrogate/ benchmark-checklist/      pstack，各含 references/
    tdd/ technical-writing/ unslop/ show-me-your-work/ ketchup/ correct/
    reflect/ teach/ bro/ sharpen/ typescript-best-practices/
    babysit/ pickup/ pause/ forensics/                                        pstack playbook 升格成 skill（有自己入口）
    audit/                                                                     ponytail-audit
    deepen/                                                                    你的 improve-codebase-architecture
  skills/apply/references/playbooks/{dev,bug-fix,refactoring,perf,hillclimb,eval}.md   dev = pstack feature.md
  skills/explore/references/{prototype,investigation}.md
  skills/review/references/ponytail-review.md
  skills/pr/references/mr-note.md
  references/principles/<name>.md        24 條
  references/{writing-the-reply,comments,bugbot-triage,harness-claude-code}.md
  references/architecture-language.md    module / interface / seam / adapter / depth / leverage / locality
  herdr-board/sync/debt.sh               ponytail-debt
  bin/opsx                               CLI 入口（init / status / dispatch / sync / board）
  bin/lib/{init,status,dispatch,sync,board}.sh
  hooks/{openspec-router,openspec-commit-gate,opsx-grant-gate,mr-format-gate,openspec-stop-gate}.sh
  UPSTREAM.md
```

開工順序（已定 2026-11-05）：openspec schema fork → `bin/opsx`（init、status）→ grill → hooks → apply（含 CLAUDE.md 合併、status.json、測試先行）→ review / pr → dispatch → 看板（herdr plugin 用新流程自己做）。

**進度（2026-11-05 晚）**：到 dispatch 為止都寫好、`bash tests/run.sh` 五套全綠（init / status / hooks / dispatch / drive）。Router 表的唯一實作在 `bin/lib/stage.sh`，hook 和 `drive.sh` 共用。看板還沒做，留給新流程開卡。實作時定的細節：`herdr tab create` 回 `.result.root_pane`，dispatch 用它當 pane；drive 的 MR 五條件讀 `glab mr view -F json`（`state` / `draft` / `has_conflicts` / `head_pipeline.status` / `unresolved_discussions_count`）或 `gh pr view --json`；gates.md 每條 `status: open|answered`，drive 看到 open 就 `herdr agent wait --until working`；`opsx stop` = kill drive pid + `herdr pane close` + dispatch.json `mode: stopped`。

搬進來後要動的：playbook 之間的相對路徑改成新位置；`subagent_type: poteto-agent` → `general-purpose`；model slug 依 harness 表映射；`/deslop`、`control-ui`、`cursor-team-kit` 的步驟改成一行 skip；arena → 單一候選；eval 的 arena → 一般 subagent；hillclimb 的 autonomous-run wake 刪；babysit 的 watch-pr / shipping → glab 查一次；create-skill → skill-creator；show-me-your-work 的跨模型 review 刪。其餘原文不改，改了 `UPSTREAM.md` 的 diff 就失去意義。

**蒸餾（一次性，不留參考目錄）**：下面六對，留的那邊讀一次被蒸餾的那邊，把它沒有的邏輯補進去，然後被蒸餾的不搬。pstack 的比較好就保留 pstack 的，不硬併。

| 留 | 被蒸餾 | 補什麼 |
|---|---|---|
| `skills/tdd/`（pstack） | `~/.claude/skills/tdd` | 你的 integration test 段 |
| `explore/references/prototype.md`（pstack） | `~/.claude/skills/prototype` | 你的 UI 多方案 toggle 分支 |
| `playbooks/bug-fix.md` + `skills/forensics/`（pstack） | `~/.claude/skills/diagnose` | 你的 minimise / instrument 步 |
| 看板 banner | pstack `recall` | 狀態摘要格式 |
| `~/.claude/CLAUDE.md` §7 + `shortcut:` | pstack `no-comments` | 註解判準 |
| `skills/pr/`（mr-note） | pstack `opening-a-pr` | forge 判斷段 |
| `skills/propose/` | 你的 `to-issues`、`to-prd` | task 垂直切（tracer bullet，不分層切）；proposal 模板加 Testing Decisions、Out of Scope 兩段；AFK / HITL ＝ 看板 待派 / 要你（2026-11-05 做了：`schemas/opsx/templates/proposal.md` 多 Acceptance / Testing Decisions / Out of Scope 三段，propose 步 4 規則） |
| 收、gate、archive | 你的 `triage` | AGENT-BRIEF 四條（不寫路徑、寫行為、驗收條件可獨立驗、明寫範圍外）進 proposal 模板；`.out-of-scope/` → 「不做」的卡歸檔留理由、收件時對一次去重；needs-info 模板 → gate 問法（2026-11-05 做了：proposal 模板註解、inbox artifact instruction 去重、archive 無 tasks.md 時要理由 + `outcome: declined`、apply 步 5 的 已確認／還需要你答） |

你的五個 skill 處置（2026-11-05 定）：`to-issues`、`to-prd`、`triage` 蒸餾後刪；`zoom-out` 刪（`how` 的 explainer 就是它）；`improve-codebase-architecture` 留成平行流程 `skills/deepen/`（見平行流程表），它的 LANGUAGE.md 抽成 `references/architecture-language.md` 給 architect 和 refactoring playbook 共用。

### kind（已定 2026-11-04）

`/propose` 寫進 `.openspec.yaml`，七種；判不出別的就是 `dev`（2026-11-05 定：feature 改名 dev，當一般開發的預設，否則不是什麼都進 feature 就是 feature 從來沒人用）。apply 依它載 `skills/apply/references/playbooks/<kind>.md`，完成條件也跟著它：

| kind | 工作 | 完成條件 | pstack playbook | 常見 repo |
|---|---|---|---|---|
| dev（預設） | 一般開發：新功能、改行為、加東西 | 測試綠、review 零 bug、MR | `dev.md`（pstack `feature.md`） | AI、CS |
| bug-fix | 修一個錯 | 重現腳本紅 → 綠 | `bug-fix.md`（+ tdd） | AI、CS |
| refactoring | 改結構不改行為 | 測試前後都綠 | `refactoring.md` | AI |
| perf | 變慢、吃資源 | 基線 → 改後數字 | `perf-issue.md` + benchmark-checklist | AI、gmtc-rag |
| experiment | 試方法、調參、跑 eval 比分數；產物是結論和數字，不一定有 code 進 MR | 結果表 + 結論（做 / 不做 / 再試） | `hillclimb.md` 或 `eval.md` | evals、gmtc-rag、scam-guard |
| ops | 部署、compose、env、secrets | 部署後 healthcheck 綠 | 無；apply 步驟 + Infra deploy 流程 | Infra |
| chore | docs、config、版本號 | 無驗證，直接 MR | 無 | 全部 |


### 主流程：節點 × 掛進去的擴充

| 節點 | opsx 現有（不動） | 掛進去的擴充步驟 | 來源 |
|---|---|---|---|
| **收** | — | `openspec new change <slug> --schema opsx` + 寫 inbox.md（一句話 / agent 發現含證據 / GitLab issue 內文） | — |
| **explore** | 讀檔、查 codebase、ASCII 圖、術語對 CONTEXT.md（不寫 code） | 固定步驟表：① 讀 inbox.md ② `how` 受影響子系統 ③ `blast-radius` 會動到誰 ④ `why` 只在要改結構時 ⑤ 有「跑了才知道」的問題 → `prototype` ⑥ 寫 explore.md：影響範圍、相關檔、實驗結果、未確定的。小事各步 `skip: 原因`，節點不跳過 | pstack `how`、`blast-radius`、`why`、playbook `prototype` |
| **grill**（閘門，非節點） | 一題一題、AskUserQuestion | ① 讀 explore.md 的待決段，空 → 回「沒有待決」停 ② 每題附推薦答案 ③ 碰到查 code / 跑一次能答的題 → 退回 explore 補，不問人也不自己查 ④ 輸出 D1…Dn 進 grill.md ⑤ 總結過 unslop | Non-negotiables 的分類規則、grill-with-docs、`unslop` |
| **propose** | proposal / specs / design / tasks（殼在「收」時已建） | ① 檢查 explore.md 待決段，沒答完 → 停，指向 /grill ② 把 kind 寫進 `.openspec.yaml`（七種） ③ D1…Dn 原樣進 design.md ④ proposal.md、design.md 過 technical-writing → unslop | `technical-writing`、`unslop` |
| **apply** | workplan 選目標、task 迴圈、self-check 四 grep、test agent、一 change 一 commit | ① 依 kind `Read skills/apply/references/playbooks/<kind>.md`，步驟逐字進 todo，skip 留原因 ② 先命名 data shape ③ 跨 function 邊界 → `architect`（單候選） ④ 要問人 → 寫 gate（建議·證據·風險·沒回預設），繼續做能做的 ⑤ task 外的問題 → 寫 inbox 卡不修 ⑥ 量到數字 → `benchmark-checklist` ⑦ 對真產物驗，不接受 it compiles ⑧ 收尾寫 decisions.tsv 一行、report.md 給 Stop gate | pstack playbooks、`principle-model-the-domain`、`architect`、never-block-on-the-human、ketchup action item、show-me-your-work、prove-it-works |
| **review** | 雙 agent（spec conformance + code quality）、證據不足自動降級 | ① 合併用四桶 lead judgment（Act on / Consider / Noted / Dismissed） ② 兩 agent 不約而同標高訊號 ③ 設計有爭議 → `Read skills/interrogate/references/reviewer-prompt.md` 再跑一輪 | `interrogate` |
| **pr** | 收 commits、開 MR | ① body 照 `references/mr-note.md` ② 過 technical-writing → unslop ③ forge 一個 session 判一次（gitlab / gh） | `technical-writing`、`unslop`、opening-a-pr 的 forge 規則 |
| **archive** | 檢查完成、歸檔、workplan merged | 長任務才 → `reflect` 把做法存回 skill | `reflect` |

所有節點共用：回覆照 pstack Writing the reply（短句、每句帶 measured / inferred / guess）；點名的原則只准引用本 session `Read` 過的 `principle-*` 檔。

### 平行流程：各自的入口、組成、接回哪

| 流程 | router 怎麼認 | 組成 | 做完接回 |
|---|---|---|---|
| ~~investigation~~ | 已併入 explore 節點步驟 ②③④ | | |
| ~~prototype~~ | 已併入 explore 節點步驟 ⑤；grill 中碰到跑了才知道的分叉 → 回 explore 補跑 | | |
| **babysit** | 「MR 怎麼樣了」「回 review 留言」「CI 紅了」 | `skills/babysit/`，只用 check / threads-only | pr 之後；不 drive、不 merge |
| **pickup / pause** | 接手別人做一半的；要離開 | `skills/pickup/`、`skills/pause/` | 主流程當時的節點 |
| **perf** | 「變慢了」「把 X 推到 Y」 | `playbooks/perf.md` 或 `hillclimb.md` + `benchmark-checklist` + `principle-explain-the-number` | 變成 change 走 apply，kind = perf |
| **dispatch** | 看板按「派」或打 `/dispatch` | opsx `dispatch.sh` + herdr worktree / agent start / prompt | 開一個 worker，worker 自己走主流程 |
| **UI / 看板** | 「做畫面」「做看板」「做 artifact」 | Open Design `skills/frontend-design` → `impeccable-design-polish`，檢查 `craft/anti-ai-slop.md`；pstack 無此項 | 那個 change 的 apply |
| **correct / reflect** | 「又犯了」「這次學到什麼」 | `skills/correct/`（修在最高能強制的層級）、`skills/reflect/` | 改 opsx 自己 → skill-creator |
| **TypeScript** | 在 Agentory-AI 的 apply 讀寫 TS 時 | `skills/typescript-best-practices/` | apply 當下 |
| **deepen** | 「找 shallow module」「這區太散」「架構體檢」 | `skills/deepen/`：Explore subagent 找摩擦 → deletion test → 候選清單（Files / Problem / Solution / Benefits）→ 人挑一個 → grill 走設計樹 → 依賴四類定怎麼跨 seam 測 | 每個選定的候選開一個 kind=refactoring 的殼 |

### Router 規則（hook 注入的那一行）

```
判斷順序：prompt 明說平行流程的關鍵詞 → 該流程
          branch 對到 change → 主流程該節點（看 tasks 勾到哪、report 在不在）
          沒 change → grill
注入格式：階段 · kind · 要 Read 的檔清單
          例：apply · bug-fix · skills/apply/SKILL.md ·
              skills/apply/references/playbooks/bug-fix.md · skills/tdd/SKILL.md
平行流程做完：下一次 prompt hook 重讀狀態，自然接回主流程
```

### 不用的 pstack skill

`poteto-mode` 本體（router 由 hook 做）、`arena`、`swarm`、`orchestrate`、`autopilot-*`、`shipping`、`make-bot-ui`、`ketchup-video`、`statechart`、`create/maintain-*-verification-skill`、`automate-me`、`in-your-own-words`、`figure-it-out`、`watch-pr`、`multi-phase-plan`、`autonomous-run`、`visual-parity`、`setup-pstack`。原因：要多模型、要 Cursor 專有功能、或跟 opsx 既有的重疊。`recall`、`no-comments`、`opening-a-pr` 不搬但蒸餾（見上表）。

## 8.2 原則：pstack 24 條全搬，與既有 `~/.claude/CLAUDE.md` 的融合

規則：**碰到才讀那一條**（`references/principles/<name>.md`），回覆裡點名的只准引用讀過的。這跟 pstack 原設計相同：它的 24 條各是 `disable-model-invocation: true` 的 skill，只能被 Read，`poteto-mode/SKILL.md` 內嵌一張 Principles index（每條一行「什麼情況用」），碰到才讀那條。差別只有放的位置（不當 skill，當 reference）和 index 放哪：index 放 `skills/apply/SKILL.md` 與 `skills/explore/SKILL.md` 各一段，hook 注入時不帶。pstack 的 24 條理論上全收；既有 CLAUDE.md §1–§7 不刪。重疊的以下表為準，衝突的寫明誰贏。

| 既有 CLAUDE.md | pstack 對應 | 關係 |
|---|---|---|
| §1 Think before coding：先講假設、不確定就問、多種解讀都攤出來 | Foundational Thinking、Attack the Premise | 互補。pstack 多一條：兩個修法共用同一前提都失敗 → 先寫下前提去測 |
| §1「不確定就問」 | Never Block on the Human | **衝突，分層解**：人在 grill 時照 §1 問；worker 在 apply 時照 pstack 寫 gate 不阻塞。兩條都留，各管一層 |
| §2 Simplicity first：最少 code、不做沒要的、不抽象 | Laziness Protocol、Subtract Before You Add、Minimize Reader Load | 同一件事，pstack 寫得更具體（collapse one-caller wrappers、shrink mutable scope）。全收 |
| §3 Surgical changes：只碰該碰的、不順手改鄰近 code | Migrate Callers Then Delete Legacy APIs、Outcome-Oriented Execution | **衝突，§3 贏**：pstack 要同一波把舊 API 的 caller 全遷掉並刪掉，§3 說不動不相關的。解法：pstack 這兩條只在 change 自己的範圍內適用（design.md 寫明要遷的 caller 清單）；範圍外的照 §3 留著、寫 inbox 卡 |
| §4 Goal-driven：先定可驗證的成功條件 | Prove It Works、Sequence Verifiable Units、Test Behavior Not Implementation | 互補。pstack 補了「驗真產物不驗代理」「每個小單位驗完才下一個」「測行為不測實作」 |
| §5 Code style：import 頂部、no nested def、**no speculative fallback**、不 `except Exception` | Boundary Discipline、Type System Discipline、Fix Root Causes 的「guard 只有在那個狀態合法時才算修」 | 互補，§5 更嚴且 Python 專用。pstack 的「邊界驗證、內部信任型別」跟 §5「不合格就 raise 並指名欄位」是同一個精神 |
| §6 Workflow is not optional：每個改動走 propose → apply | 無 | §6 獨有，pstack 靠 poteto-mode 入口。這裡由 hook 強制（§8.5） |
| §7 Verification before volume：先證明能驗、不重裝環境、hunk 級決定、印錯誤再診斷、批次改逐個看 | Prove It Works、Explain the Number、Build the Lever、Encode Lessons in Structure | 互補。pstack 補「量到的數字先解釋」「做工具不手做」「同一指令寫第二次就改成 lint / script」 |
| 無 | Model the Domain、Redesign from First Principles、Make Operations Idempotent、Separate Before Serializing Shared State、Guard the Context Window | pstack 獨有，全收。Model the Domain 已掛進 apply ②；Separate Before Serializing 是「一 PR 一 worktree」的依據；Guard the Context Window 是 review 用 subagent 的依據 |
| 無 | Experience First、Exhaust the Design Space | pstack 獨有，**限範圍收**：只在 prototype 流程裡用（grill 碰到跑了才知道的分叉時做 2–3 個比），不在 apply 裡用，否則跟 §2 打架 |

三個衝突的裁決寫死：
1. 問人 vs 不阻塞 → 分層：grill 問人，worker 寫 gate
2. 不動鄰近 code vs 同波刪舊 API → §3 贏，pstack 只在 design.md 列的範圍內
3. 做 2–3 個比 vs 最少 code → 只在 prototype 流程

## 8.3 每條流程：步驟 × skill × 產出 × hook（2026-11-04 定）

讀法：每條流程一張表。「Read」= 載 `skills/<x>/SKILL.md` 或它的 `references/`。「產出」是這步結束時磁碟上**一定要有**的檔，少一個就是沒做完。「hook」是誰把這條流程叫起來、哪個閘門擋它。

### Router（hook 每次 prompt 看狀態決定注入哪一條）

| 狀態（在 `changes/<slug>/` 看） | 注入 |
|---|---|
| prompt 明說平行流程關鍵詞 | 該平行流程 |
| prompt 說「tdd」 | `/apply <slug>` 的 3b 步：只寫測試不實作，寫完停（給你想先看測試長什麼樣的時候） |
| 沒有任何 change 對到目前 branch | `/explore`（先建殼） |
| 有 inbox.md，沒 explore.md | `/explore <slug>` |
| 有 explore.md，待決段非空，沒 grill.md | `/grill <slug>` |
| 有 explore.md（待決空或 grill.md 已有），沒 tasks.md | `/propose <slug>` |
| 有 tasks.md，有未勾的 | `/apply <slug>` + kind 對應的 playbook 路徑 + `skills/tdd/SKILL.md` |
| tasks.md 全勾，`status.json` tests 不是 green（或有 task 沒測試檔） | `/apply <slug>`，注入「先把測試補到綠」 |
| tasks.md 全勾且 tests green，沒 report.md | `/review <slug>` |
| 有 report.md，沒 MR | `/pr <slug>` |
| workplan 標 merged，還在 changes/ | `/archive <slug>` |

注入格式一行：`階段 · slug · kind · Read 清單`。

### 收（指令，不是 skill）

| 步 | 做什麼 | Read | 產出 |
|---|---|---|---|
| 1 | `openspec new change <slug> --schema opsx --description "<一句話>"` | — | `changes/<slug>/.openspec.yaml`、README.md |
| 2 | 寫 inbox.md：type / source / found / related / 內文 / 證據 | — | `inbox.md` |
| 3 | 有附件（paste）→ 存進去 | — | `attachments/*` |

來源：me（+ 鈕）、agent（apply 步 6）、gitlab / github / obsidian / customer（同步腳本）、paste、shortcut（ponytail-debt）。

### explore（主流程節點 1，必經）

| 步 | 做的條件 | Read | 產出到 explore.md 的哪段 |
|---|---|---|---|
| 1 | 永遠 | inbox.md、attachments/ | — |
| 2 how | 跨 2 檔以上，或本 session 沒讀過該子系統 | `how`（簡單路徑：一個 explainer；複雜：2–4 explorer + explainer，subagent 用 general-purpose） | 「怎麼運作」五段 |
| 3 blast-radius | 動到的符號有別人用（export、DB 欄、API、config、env） | `blast-radius`（步 6 arena 刪） | 「影響範圍」：安全的那個事實 + 證據級、風險、已排除 |
| 4 why | 要改結構 / ownership，或要刪看起來刻意的東西 | `why`（只跑 git + code-archaeology + incident-postmortem 三個 investigator） | 「為什麼現在這樣」+ Preserve / Change / Avoid / Risk |
| 5 prototype | 有「跑了才知道」的題，且一小時內草得出 | `explore/references/prototype.md` | 「實驗結果」：方案、觀察到的、建議；scratch 路徑 |
| 6 跟 code 對照 | inbox.md 裡有「系統會 X」的陳述 | — | 「陳述 vs code」不一致清單 |
| 7 寫待決 | 永遠 | — | 「待決」：只有人能答的題，每題附推薦答案；空就寫「無」 |
| 8 | 永遠 | `explore/references/investigation.md` 的輸出格式、`unslop` | explore.md 完成 |

產出：`explore.md`（已知 / 待決 / 不做 / 步驟 四段；步驟段每步一行，含 §3 的「查資料」共九行，格式與條件見 `skills/explore/SKILL.md` 的 Steps）。hook：inbox.md 有、explore.md 沒 → 注入。

### teach（explore 之後，人叫才跑，不是節點）

| 步 | Read | 產出 |
|---|---|---|
| 1 讀 explore.md | — | — |
| 2 一句定義 → 對到這張卡 → 分層加深 → 三個以上元件就逐圖疊 | `teach`（how / why 不重跑，用 explore.md 的） | chat 裡的解釋；不寫檔 |

### grill（閘門，待決非空才有）

| 步 | Read | 產出 |
|---|---|---|
| 1 讀待決段；空 → 回「沒有待決」停 | explore.md | — |
| 2 一題一題 AskUserQuestion，2–4 選項，附推薦；對照 CONTEXT.md 詞彙（有的話） | opsx `skills/grill/SKILL.md`、`references/CONTEXT-FORMAT.md` | — |
| 3 碰到查 code / 跑一次能答的 → 退回 explore 補 | — | explore.md 補段 |
| 4 全部答完 → 寫 D1…Dn：決定 / 理由 / 否決 | — | `grill.md` |
| 5 總結過 unslop | `unslop` | — |

hook：explore.md 待決非空、grill.md 沒 → 注入；propose 開頭檢查，沒答完就停。看板上答 gate 也走同一條，寫同一個 grill.md。

### propose（主流程節點 2）

| 步 | Read | 產出 |
|---|---|---|
| 1 檢查 explore.md 待決是否答完（看 grill.md） | — | 沒答完 → 停 |
| 2 確認 kind（**已定 2026-11-05：kind 在指派時由你選**，指派對話框預設從來源提示猜：GitLab label bug / agent 回報 bug → bug-fix、shortcut → refactoring、「太慢」→ perf、其餘 → dev；dispatch.sh 寫進 `.openspec.yaml`）。propose 讀 explore.md 後覺得不對，可以改，但要在 decisions.tsv 記一行「kind 改 X：原因」，板上卡會標出來 | — | `.openspec.yaml` 的 kind（已有，確認或改） |
| 3 產 proposal / specs / design（D1…Dn 原樣進 Decisions）/ tasks。**tasks.md 每個 task 帶兩行**（已定 2026-11-05）：`驗收：` 指到 specs 的 Requirement / Scenario；`測試：<檔案路徑>` 是 apply 要先寫的那支（含邊界案例：空值、上限、錯誤輸入、權限外）。沒有可驗收行為的 task（搬檔、純 config、文件）寫 `測試：無 · <原因>`，propose 要能說出為什麼無 | opsx `skills/propose/SKILL.md`、`openspec instructions` | `proposal.md`、`specs/**`、`design.md`、`tasks.md`（每 task 有 驗收 / 測試 兩行） |
| 4 proposal.md、design.md 過 technical-writing → unslop | `technical-writing`、`unslop` | — |
| 5 寫 workplan.yaml：PR 名（`[a-z][a-z0-9_-]{0,31}`）、branch、depends-on | — | `workplan.yaml` 新增一筆 |

hook：explore.md 有、tasks.md 沒 → 注入。

### apply（主流程節點 3）：共用骨架 + 依 kind 的 playbook

**共用骨架**（每個 task 都跑）：

| 步 | Read | 產出 |
|---|---|---|
| 0 `Read playbooks/<kind>.md`，步驟逐字進 TodoWrite，不做的留 `skip: 原因` | 依 kind | todo |
| 1 寫之前：列改動要到的每一處（caller、tests、fixtures、config）；爬梯子 ①需要存在嗎 ②已有嗎 ③標準庫 ④已裝套件 ⑤一行 ⑥最小 | `~/.claude/CLAUDE.md` §2–§3（ponytail 已併入，§8.4.1） | — |
| 2 命名 data shape 與組織結構 | `principle-model-the-domain` | — |
| 3 跨 function 邊界 → 先出 signature 草圖 | `architect`（Phase B 單一候選；design-red-flags 照用） | — |
| **3b 先寫測試（已定 2026-11-05，每種 kind）**：照 tasks.md 這條 task 的 `驗收：` 和 `測試：` 寫測試檔，正常路徑 + 邊界案例（空值、上限、錯誤輸入、權限外）；跑一次**確認是紅的**（綠的表示測試沒測到東西，重寫）；失敗測試先 commit。`測試：無` 的 task 跳過這步，todo 留 `skip: 無可驗收行為` | `tdd`（紅 → 綠 → 重構；integration 段蒸餾自你的 tdd） | 測試檔、一顆 `test:` commit |
| 4 實作到剛才的測試綠為止 → self-check 四個 grep。綠了之後才准加沒被測試要求的東西 | opsx apply | code |
| 5 要問人（第二級授權沒給、或決定題）→ 寫 gate，繼續做能做的 | ketchup 的 action item 欄位 | `gates.md` 追加一筆 |
| 6 task 外的問題 → 開新殼寫 inbox.md，不修 | — | `changes/<新slug>/inbox.md`（source: agent:<pr>） |
| 7 實作時冒出 tasks.md 沒列的分支 / 迴圈 / parser / 錢 / 安全 → 補一個小測試，加進同一支測試檔 | `~/.claude/CLAUDE.md` §4（ponytail 測試門檻，§8.4.1 #4） | 測試檔 |
| 8 跑 test agent：這張卡**所有** task 的測試檔都要跑、都要綠，不只這條；有量到數字 → 先過七問 | `benchmark-checklist` | 測試結果（寫進 status.json 的 `tests: green|red`） |
| 9 對真產物驗，不接受 it compiles | `principle-prove-it-works` | — |
| 10 勾 tasks.md（**這條 task 的測試綠才准勾**）；一 change 一 commit（`git commit -- <paths>`）；PreToolUse 閘門看 branch 對不對得到卡 | — | tasks.md 勾、commit |
| 11 decisions.tsv 一行（what / why / evidence / result） | `show-me-your-work`（格式 + log.sh） | `decisions.tsv` |
| 12 回覆：Writing the reply + 結尾「跳過 / 沒查 / 風險」 | `references/writing-the-reply.md` | — |

**依 kind 的 playbook**（骨架步 0 載入的那份，步驟疊在骨架 1–12 之間）：

| kind | Read | 它多做的步 | 完成條件（Stop hook 和看板看的） |
|---|---|---|---|
| dev | `playbooks/dev.md` + `tdd` | how（若 explore 沒做）→ architect → **每 task 先寫測試含邊界，確認紅** → 實作到綠 → throughput checkpoint 四項 → 驗 → 有爭議 interrogate | tasks 全勾、每 task 的測試檔存在且全綠 |
| bug-fix | `playbooks/bug-fix.md` + `tdd` | **自己重現**拿 runtime 證據 → 二分法找 mechanism → 失敗測試（repro + 邊界）先進 git → 修 → 原 repro 要過 | repro 腳本紅 → 綠，commit 順序失敗測試在前 |
| refactoring | `playbooks/refactoring.md` + `tdd` | 先釘行為契約（characterization test，含邊界）→ 命名目標形狀 → 先刪 → 小步移，每步 pin 綠 → 等價證明 → reader load 真的降，沒降 revert | pin 前後都綠、等價腳本輸出一致 |
| perf | `playbooks/perf.md` + `benchmark-checklist` + `tdd` | 先寫行為不變的測試（改完要照過）→ 抓 baseline trace 過七問 → 七句 mantra 順序試 → 改 → 再量 → 比 artifact | 行為測試綠、baseline 數字、改後數字、delta、artifact 路徑 |
| experiment | `playbooks/hillclimb.md` 或 `playbooks/eval.md` | hillclimb：定指標 + 停止條件 → 建 harness 過七問後凍結 → decision.tsv → 一假設一改一量，過噪音才留 → 達標停。eval：候選環境去識別 → 一個 organic prompt → N 候選 → 盲 judge → 從 transcript 驗。harness 就是它的測試 | 結果表 + 結論（做 / 不做 / 再試）；decision.tsv |
| ops | 無 pstack playbook；opsx apply + Infra `deploy.sh` 流程 | compose validate → sops → pre-up → up → healthcheck；碰到腳本的 task 照 3b 先寫測試（bats 或 shell 斷言） | healthcheck 綠；deploy 是第三級，永遠 gate |
| chore | 無 | 骨架 3b（碰 code 才有）、4、10、11、12 | commit；碰 code 的 task 測試綠 |

hook：tasks.md 有未勾 → 注入 `/apply` + playbook 路徑 + `skills/tdd/SKILL.md`（每種 kind 都載）；PreToolUse 擋沒對到卡的 commit；Stop 擋 tasks 沒勾完或 `status.json` 的 `tests` 不是 green。

**順序寫死（已定 2026-11-05）：propose 出 tasks → 每 task 先寫對應測試和邊界測試 → 實作到綠 → 整張卡的測試全綠 → 才 review。** review 看到任何 task 沒有測試檔、或測試紅，不審，退回 apply。

### review（主流程節點 4）

| 步 | Read | 產出 |
|---|---|---|
| 0 前提：tasks.md 每條 task 的 `測試：` 檔存在（或標 `無`）且 `status.json` `tests: green`；不成立 → 不審，注入 `/apply <slug>` 回去補 | — | — |
| 1 `git diff main...HEAD`、design.md 的 D-id | — | — |
| 2 Agent A：spec conformance（每個 D 有對應 code、non-goal 沒 code、勾的 task 真做了）。**模型 sonnet 5.5**（已定 2026-11-05） | opsx review | finding 清單 |
| 3 Agent B：code quality，prompt 併入 ponytail-review 的六類（bug / 安全 / 負載 / 沒測試的風險 / 慢 / 多餘）+ interrogate 的 code-quality lens；每條要具體失敗案例。**模型 sonnet 5.5** | `review/references/ponytail-review.md`、`interrogate/references/code-quality-review.md` | finding 清單 |
| 3b Agent C：對抗式（每次都跑，已定 2026-11-05；**模型 opus 5.5**，三個裡只有它要判斷力；lead judgment 在主 session 做）：假設這個改法是錯的，攻擊 design.md 的前提、列被略過的替代、找什麼負載 / 輸入 / 順序會壞；再對 tasks.md 每條的測試檔問「有沒有證明驗收條件、邊界漏了哪個」；每條要具體失敗案例，說不出就不列 | `interrogate/references/reviewer-prompt.md`、`rubric.md` | finding 清單 |
| 4 合併：同義合併、兩個以上 agent 都提的標高訊號；四桶 Act on / Consider / Noted / Dismissed | `interrogate/references/lead-judgment.md` | — |
| 5 （併入 3b，刪） | — | — |
| 6 證據不足自動降級；Bug / Must-fix 才 auto-fix，一輪 | opsx review | fix commit |
| 7 寫 report.md：四桶、修了什麼、沒修的、ledger verdict | — | `report.md` |

hook：tasks 全勾且 tests green、report.md 沒 → 注入；Stop 擋沒 report.md。

### pr（主流程節點 5）

| 步 | Read | 產出 |
|---|---|---|
| 1 讀 report.md、收 commits、撈測試檔 | opsx pr | — |
| 2 body 照 mr-note：Summary / Changes 表 / Test plan / Reviewer notes | `skills/pr/references/mr-note.md` | description 檔 |
| 3 過 technical-writing → unslop | `technical-writing`、`unslop` | — |
| 4 forge 一個 session 判一次（gitlab remote → glab，否則 gh） | `skills/pr/SKILL.md`（opening-a-pr 的 forge 段已蒸餾進去） | — |
| 5 開 MR，GET 回來驗長度和表格；PreToolUse 擋沒表格的 | — | MR；URL 寫進 report.md |

hook：report.md 有、MR 沒 → 注入；PreToolUse `glab mr create` 閘門。

### archive（主流程節點 6）

| 步 | Read | 產出 |
|---|---|---|
| 1 確認 MR merged、tasks 全勾、report.md 有 | — | — |
| 2 長任務 → reflect：三 reviewer + synthesizer → Accepted / Rejected / Backlog → 人批准才改 skill | `reflect`（create-skill → skill-creator；改的是 opsx 自己） | 改 opsx 的 change 殼 |
| 3 `openspec archive`，workplan 標 merged | opsx archive | `changes/archive/<date>-<slug>/`、workplan |

hook：workplan merged、殼還在 → 注入。

### 平行流程（各自入口）

| 流程 | 入口 | 步 | Read | 產出 |
|---|---|---|---|---|
| babysit | 人：「MR 怎麼樣了」「回留言」 | 宣告 check 或 threads-only → `glab mr view` → 衝突只報 → 留言照 bugbot-triage 判 fix / dismiss / ask → 不 merge | `skills/babysit/SKILL.md`（watch-pr、shipping 段刪）、`references/bugbot-triage.md` | report.md 追加一段；留言回覆 |
| session-pickup | 人：「接手」「繼續上次的」 | 找 transcript / branch → 重建狀態 → 做完 vs 待做 → 路由回主流程節點 | `skills/pickup/SKILL.md`（路徑改 Claude Code） | 無新檔；回到該節點 |
| pause-safely | 人：「我要走了」 | 停在原子步 → `wip:` commit → resume note | `skills/pause/SKILL.md` | commit、`/tmp/<slug>-resume.md` |
| 診斷 | 人：「變慢了」「吃滿了」「這個 profile 檔看一下」 | live → runtime-forensics；有檔 → trace-forensics；縮到 smoking gun → 對回 source | `skills/forensics/SKILL.md`（runtime + trace 兩段） | 新殼 inbox.md（type: perf 候選）或既有 perf 卡的 explore.md |
| correct | 人：「又犯了」 | 找錯誤類別（兩次才算）→ 修在最高層：架構 > 型別 / lint > 測試 > 文件 → 證明新 check 在舊錯上會紅 → 規則表 | `correct` | 改 opsx 或 CLAUDE.md 的 change 殼；規則 ↔ 強制表 |
| audit | 人：「這個 repo 體檢」 | 讀 docs / config / entry point → 追 data flow → 六類 → ≤20 條三級 | `skills/audit/SKILL.md` | 每條一個新殼 inbox.md（source: audit） |
| debt 同步 | 每日排程 | 掃 `shortcut:` | `herdr-board/sync/debt.sh` | 新殼 inbox.md（source: shortcut:<file>:<line>） |
| dispatch | 看板「派」或 `/dispatch` | 讀 workplan + grants → 依賴全 merged → `herdr worktree create` + `agent start <pr>` + `agent prompt "/apply <slug>"` → 寫 dispatch.json | opsx `dispatch.sh` | `dispatch.json` |
| UI | 「做畫面」 | frontend-design → impeccable-design-polish → anti-ai-slop 檢查 | Open Design 的三個檔 | 那個 change 的 code |
| 一般工具 | 人叫 | bro（白話重講）、sharpen（prompt 變深） | `bro`、`sharpen` | chat |
| deepen | 人：「架構體檢」「這區太散」 | 讀 CONTEXT.md（有的話）→ Explore subagent 找摩擦（追一個概念要跳幾個 module、shallow、pure function 抽出來但 bug 在呼叫處、跨 seam 漏）→ 每個候選過 deletion test → 候選清單 → 人挑 → grill 走設計樹（約束、依賴類別、deepened module 的形狀、seam 後面放什麼、哪些測試活下來）→ 介面設計（候選數見 §9 未決） | `skills/deepen/SKILL.md` + `references/{deepening,interface-design}.md`、`references/architecture-language.md` | 每個選定候選一個新殼：inbox.md（source: deepen）+ grill.md 直接帶過去，kind=refactoring |

## 8.4 ponytail 融合（2026-11-05 定）

來源：DietrichGebert/ponytail v5.3.3，commit `96608e0`（2026-10-29）。`skills/ponytail/SKILL.md`（52 行）與 `.agents/rules/ponytail.md`（30 行）內容相同，後者沒有 frontmatter 和 Levels 表，**合併時用後者當來源**。

定案：ponytail 核心是行為規則不是流程。上游對 Cursor / Windsurf / Kiro 出貨的就是 rules 檔，對 Claude Code 則靠 hook 每輪注入同一段文字。我們不裝它的 hook，直接把規則併進 `~/.claude/CLAUDE.md`，每輪都在、不靠 skill 載入。三個 skill 各有去處；levels、session 持續性、band、gain、help、三個 hook 不採。

### 8.4.1 核心規則 → `~/.claude/CLAUDE.md`

一條一條對到既有章節。「要加的文字」是實作時直接貼的句子；已有同義句的不重複加，寫「已有」。

| # | ponytail 零件 | 進哪一節 | 要加的文字 |
|---|---|---|---|
| 1 | 寫之前（Before you write） | §3 Surgical Changes，「When editing existing code」之前加一段 **Before editing** | 列出改動要到的每一處：caller、tests、fixtures、config、exports。想它會弄壞使用者什麼：會毀掉或外洩的資料、會停擺的 caller。那是範圍；多出來的功能不是。 |
| 2 | 梯子（六步） | §2 Simplicity First，現有四條 bullet 之前加一段 **The ladder**，照順序問、停在第一個成立的 | ① 需要存在嗎？沒人要的功能、option、彈性直接跳過，一行點名。模糊的要求（「做個 X」）給最小能做核心的版本。② 這個 codebase 已經有嗎（helper、component、service、pattern）？照周圍 code 的用法用。③ 標準庫或平台有嗎？用，除非專案自己有一份（house component 勝過 native widget）。④ 已裝的套件有嗎？用。絕不為幾行 code 加套件。⑤ 能寫成一行讓人一眼看懂嗎？一行。⑥ 以上都不是，才寫最小能動的 code。 |
| 3 | 規則（八條 bullet） | §2 Simplicity First，現有四條 bullet 之後加 | 對解法懶，對改動不懶：task 需要的每一部分都做完，包括被你改壞的 caller、tests、fixtures。／不加沒人要的 abstraction、wrapper、型別轉換、option、config、boilerplate、「以後用」的 code。值保持平台給的形式。刪勝過加。保持 codebase 既有的 layers、interfaces、conventions。／知道全部要動的地方之後，最短能動的 diff 贏；要解碼的一行不算短。／移動或合併的 code 保留它原本的錯誤處理與驗證。／同樣大小的選項，選 edge case 對的那個。 |
| 3a | 規則裡「Comment only the why」 | §7 Comments 段 | 已有，不加 |
| 3b | 規則裡「Bug fix: grep every caller, fix root cause once」 | — | 不加；pstack `fix-root-causes` 已涵蓋，bug-fix playbook 第 2 步會載 |
| 4 | 測試門檻 | §4 Goal-Driven Execution，「Transform tasks into verifiable goals」之後加 | 沒帶檢查的懶 code 不算完成：新的非瑣碎邏輯（分支、迴圈、parser、錢、安全、整支新 script 或 app）留一個小測試或 assert 自檢。瑣碎改動不用。 |
| 5 | `shortcut:` 註解 | §7「Comments carry what the next reader needs」那段末尾加一句 | 刻意的捷徑留一行 `shortcut: <上限>, <什麼時候升級>`，例：`shortcut: in-memory cache, fine under 1k users, go redis when multi-instance`。這是唯一准許記「為什麼現在不做完整」的註解形式；看板每天掃它（§8.4.4）。 |
| 6 | 永不砍 | §2 末尾獨立一行 | 永不砍：trust boundary 的驗證、防資料遺失的錯誤處理、安全、無障礙、真硬體要的 calibration、使用者明確要的東西。 |
| 7 | 回覆結尾 | §7「Lead with state」那段末尾加一句；同一句也進 `references/writing-the-reply.md` | 回覆最後一兩行：跳過了什麼、沒檢查什麼、使用者必須知道的風險。 |
| 8 | 開頭人設句、Levels 表、「Active for the whole session」 | — | 不加 |

兩個要對一次的點：
- §2 現有「No error handling for impossible scenarios」與 #6「防資料遺失的錯誤處理永不砍」不衝突（一個講不存在的情境，一個講真會發生的），實作時在 #6 那行後面括號註明。
- §5「No speculative fallbacks」與 #3「移動的 code 保留它原本的錯誤處理」不衝突：保留的是既有的、指名的錯誤處理，不是新加的 fallback。不另寫。

**subagent 吃不吃得到**：ponytail 另裝 SubagentStart hook 就是因為怕 subagent 沒收到規則。實作時驗一次：spawn 一個 general-purpose subagent 問它 CLAUDE.md §2 第一條是什麼。收得到 → 不用做；收不到 → apply、review、how 的 subagent prompt 模板第一行加 `Read ~/.claude/CLAUDE.md §2–§4`。結果記進 §9。

`skills/apply/references/ponytail-ladder.md` 因此不建；apply 骨架步 1 的 Read 欄改成 `~/.claude/CLAUDE.md §2–§3`（§8.3 已改）。

### 8.4.2 ponytail-review → `skills/review/references/ponytail-review.md`

原文去掉 frontmatter 照搬（101 行）。review 的 SKILL.md 在 Agent B 那步寫：

- Scope 不用它的 §1 第一條（「uncommitted or last commit」），review 給定 `git diff main...HEAD`；§1 其餘（讀 caller、被呼叫的、tests、README；追資料流；簽章變了 grep 所有 caller；找預期負載）照做。
- §2 六類 + §3 查證規則照做，再加 `interrogate/references/code-quality-review.md` 的 lens。
- 輸出用它的 §4 格式：Must fix / Should fix / Nice to have，跨組編號，每條四部分（code 做什麼 / 問題 / 修法 / 不修的代價），結尾 verdict + 可砍行數 + 沒查的。
- 「`shortcut:` 註解是決定不是缺陷，除非預期負載已經超過上限」這條保留，它是 #5 的另一半。
- 只報不改；auto-fix 由 review 主線在合併後做（§8.3 review 步 6）。

### 8.4.3 ponytail-audit → `skills/audit/SKILL.md`

原文去掉 frontmatter 照搬（103 行），只改 §4 Output：

- 不出報告檔。每條 finding 跑一次「收」：`openspec new change <slug> --schema opsx`，inbox.md 寫 `type: audit`、`source: audit:<repo>@<commit>`、`severity: must|should|nice`、四部分原文（What this is / Problem / Fix / If we skip it）、檔案位置當證據。
- 開頭的「What this repo does + 假設負載」每張卡的 inbox.md 都帶同一段，卡要能單獨讀。
- `Verdict:`、`Lean:`、`Not checked:` 三行只回 chat，不進卡。
- 去重：建殼前對該 repo 既有殼（含 archive）的 inbox.md 比 `source` 與檔案位置，命中就在既有卡追加一行不新建。
- ≤20 條的上限照舊；超過的說有幾條沒列。

### 8.4.4 ponytail-debt → `herdr-board/sync/debt.sh`

它的 SKILL.md 本質是一條 grep 加一個輸出格式，變成看板的每日同步腳本，不當 skill：

- 掃描：對 `~/code/*/` 每個有 `openspec/` 的 repo 跑 `git grep --no-index --exclude-standard -nE '(#|//|/[*]) ?(shortcut|ponytail):'`。
- source id 不用行號（會漂）：`shortcut:<repo>:<file>:<sha1(註解全文)[:8]>`；行號另存在 inbox.md 裡，每次同步更新。
- 解析：`shortcut: <上限>, <升級時機>` 兩段；缺第二段 → inbox.md 標 `no-trigger: true`。
- 去重：source id 對該 repo 所有殼（含 archive）的 inbox.md；已有就更新行號，沒有才建殼（`type: debt`）。
- 註解從 code 消失但卡還開著 → inbox.md 標 `stale: true`，不自動 archive，看板 inbox 顯示灰色，由人關。
- 不寫 `PONYTAIL-DEBT.md`；帳就是卡。
- 跟 §3.6 其他來源同一支排程（launchd daily）。

### 8.4.5 不採的

| 項目 | 原因 |
|---|---|
| `hooks/claude-codex-hooks.json` 三個 hook（SessionStart activate、UserPromptSubmit mode-tracker、SubagentStart） | 規則在 CLAUDE.md 每輪都在；subagent 那個看 8.4.1 的驗證結果 |
| `hooks/claude-band.json` + `hooks/band/`、statusline 腳本 | 看板做「在跑」cost 欄時再看它 `~/.config/ponytail/band/<project>.csv` 的欄位，現在不裝 |
| Levels（lite / full / ultra）、「stop ponytail」 | 固定 full；ultra 的「質疑需求」是 grill 的事 |
| ponytail-gain、ponytail-help | 廣告、說明 |
| `userConfig` 的 webhook | 不對外送 |

### 8.4.6 UPSTREAM.md 要記的列

```
~/.claude/CLAUDE.md §2–§4、§7（合併段）  ← ponytail/.agents/rules/ponytail.md @ 96608e0
skills/review/references/ponytail-review.md ← ponytail/skills/ponytail-review/SKILL.md @ 96608e0
skills/audit/SKILL.md                       ← ponytail/skills/ponytail-audit/SKILL.md @ 96608e0（§4 改寫）
herdr-board/sync/debt.sh                    ← ponytail/skills/ponytail-debt/SKILL.md @ 96608e0（grep 指令與格式）
references/writing-the-reply.md（結尾句）   ← 同第一列
```

## 8.5 流程強制（所有 skill 共用）

最大痛點是 agent 沒載入 skill、或載入了沒照步驟跑。pstack 把這兩件事分開治，opsx 照抄其機制，並用 hook 補 pstack 沒有的硬閘門。

### 沒載入（trigger 失敗）

1. opsx 的 skill 之間用 `Read <plugin>/skills/<name>/...` 接，不靠 Skill tool 或 description 觸發。SKILL.md 裡寫明路徑。
2. 新增 `SessionStart` 或 `UserPromptSubmit` hook：repo 有 `openspec/` 時注入一行「active changes: <openspec list>；每個改動走 /propose → /apply」。與 `mr-note-reminder.sh` 同模式，差別是每次 prompt 都注入。

### 沒照跑（步驟被跳）

1. 每個 opsx skill 開頭是一份短的編號步驟表。載入後第一個動作是把步驟逐字抄進 TodoWrite，才准加任務自己的 todo。不做的步驟不能刪，留 `skip: <原因>`。長 prose 搬到 `references/`。
2. 每個 skill 結尾有 `**Reply:**` 段，列出回覆必有的段落（pstack playbook 格式）。
3. 新增 `PreToolUse` hook 擋 `git commit`：branch 對應不到任何 `openspec/changes/<name>/`，且 commit message 沒有 `OpenSpec change:` trailer → deny，訊息指回 `/propose`。放 opsx 的 `hooks/hooks.json`，與 security-guard 並列。
4. 原則引用規則：回覆裡點名的原則只准引用本 session 真的 Read 過的檔（pstack）。

### hook 的位置與內容

hook 放 plugin 自己的 `hooks/hooks.json`，用 `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh`，與現有 security-guard 並列。啟用 plugin 即生效，不碰 `~/.claude/settings.json`。plugin hooks.json 支援的 event 與 settings.json 相同（已確認其他已裝 plugin 用了 SessionStart、UserPromptSubmit、Stop）。

| event | 腳本 | 做什麼 |
|---|---|---|
| SessionStart | `openspec-context.sh` | `[ -d openspec ] \|\| exit 0`；`openspec list --json` + `workplan.yaml` 擠成一行 additionalContext：active changes、目前 branch 對應的 change、**下一步該打哪個 skill**（tasks 全勾未 archive → `/review` 或 `/archive`；有 change 未勾完 → `/apply <name>`；沒 change → `/propose`）。等於把 `/status` 的 next action 每次自動出現 |
| UserPromptSubmit | 同一腳本 | 只在 `openspec/` 的 mtime 比上次注入新時才重跑，否則零輸出 |
| PreToolUse (Bash) | `openspec-commit-gate.sh` | `git commit` 時：repo 無 `workplan.yaml` → 不擋，印一行「閘門未啟用」（舊 repo 第一次 `/propose` 後自動生效）；有 workplan → branch 對到卡且 tasks 有勾才放行；對不到 → deny，message 帶 `[no-change]` 放行並記 `~/.local/state/opsx/bypass.log`。只看 commit 的 branch 不看 index，不逼人用 `git add`（Agentory-AI D131 的 pathspec commit 照用） |
| PreToolUse (Bash · Edit · Write) | `opsx-grant-gate.sh` | 自動模式下的授權閘門：指令或路徑落在「要授權」那級（push、開 MR、改 MR description、本機 migrate / reset、刪檔、裝套件、外部 API、寫 `.env.*`、rebase）→ 查 `grants.toml`（repo 永遠）與 dispatch.json（這張卡）；有授權 allow，沒有 deny，deny 訊息：「寫 gates.md（建議 · 證據 · 風險 · 沒回預設），然後做能做的」。「永遠要人」那級（merge、deploy、force-push、刪資料、對外發話、改 CI / secrets）一律 deny，訊息同上。互動模式不裝這支 |
| PreToolUse (Bash) | `mr-format-gate.sh` | `glab mr create` / `gh pr create` 時檢查 description 檔含 `## Changes` 與表格列 `\| 編號 \|`，否則 deny。取代現在只提醒的 `mr-note-reminder.sh` |
| Stop | `openspec-stop-gate.sh` | branch 對應的 `tasks.md` 仍有 `- [ ]`、`status.json` 的 `tests` 不是 green、或有新 commit 但 review 未跑 → block 並說原因 |

前置確認：目前 session 的 config dir 是 `~/.claude-work`，但 opsx 裝在 `~/.claude/plugins/cache/`。先確認哪個 config dir 在跑 opsx，再改 hooks.json。

### 保證範圍

從入口進去後，hook 能保證的是「進得去、出不來除非做完、中間跳步會留痕」。不是每步都能保證。

| 步驟類型 | 機器能否驗證 | 手段 |
|---|---|---|
| 進入：有沒有 change、在哪個 branch | 能 | SessionStart / UserPromptSubmit 注入 |
| 退出：commit 有沒有對應 change | 能 | PreToolUse deny |
| 退出：tasks 全勾、review 跑過才准停 | 能 | Stop block |
| 退出：MR description 格式 | 能 | PreToolUse deny |
| 中間：architect、重現、data shape、self-check、有沒有真的 Read reference | 不能 | todo 可見性 + `skip:` 留痕 + §11 eval 量照跑率 |

pstack 的 `skip: <原因>` 規則本身就是承認模型會跳步，它讓跳步可見，不是不可能。中間步驟的照跑率只能靠 eval 量，不假設。

### 原則依據

pstack 的 encode-lessons-in-structure 與 `/correct`：同一個錯誤修在最高能強制的層級，順序是 architecture > lint / CI > tests > docs。CLAUDE.md §6 的文字是最低層。

## 9. 已決與未決（2026-11-04 整理）

### 已決

| 項目 | 決定 | 寫在 |
|---|---|---|
| 耦合方式 | 不耦合：用到的檔複製進 opsx 當自己的 skill / reference，不留 `vendor/` 巢；來源版本記 `UPSTREAM.md` | §8.1 |
| 重疊的 skill | 一次性蒸餾，不留參考目錄；pstack 的較好就保留 pstack 的 | §8.1 |
| 你的五個 skill | to-issues / to-prd / triage 蒸餾後刪；zoom-out 刪；improve-codebase-architecture → `skills/deepen/` 平行流程 | §8.1 |
| ponytail 版本 | v5.3.3，commit 96608e0（2026-10-29） | — |
| ponytail 放哪 | 核心規則併進 `~/.claude/CLAUDE.md` §2–§4、§7，不裝它的 hook；review 當 Agent B 的 reference；audit 成 `skills/audit/`，產出是卡；debt 成看板同步腳本；levels / band / gain / help 不採 | §8.4 |
| 原則載入 | 24 條全搬，碰到才讀那一條；與既有 CLAUDE.md 的三個衝突已裁決 | §8.2 |
| setup-pstack | 不跑，不用多模型 | — |
| 誰 merge | 永遠人；agent 最多推到「等你 merge」 | §3.6 |
| Stop gate 的 review 痕跡 | `openspec/changes/<name>/report.md` | §5、§8.5 |
| worker 回報格式 | 同上 report.md；不讀終端 | §3.5 |
| 跨 repo 總表 | 自製看板掃 `~/code/*/openspec/`，不用 tsk | §3.6 |
| 等你四種 | 等待授權 / 等待決定（gates.md）· 可以合併（collect.sh 從 report.md + glab 五條件推）· 終端機等待輸入（herdr blocked 無 gate，列進等你，只能開 pane）（2026-11-05） | §3.6 |
| 進度來源 | `changes/<slug>/status.json`，每條 skill 每步 `opsx status` 寫，herdr tokens 只是鏡像；不讀 Claude Code todo 檔（2026-11-05） | §3.6 |
| 畫面用字 | 標準詞：待處理 / 進行中 / 待指派 / 收件匣 / 已完成；指派 / 先 explore / 捨棄 / 合併；授權跟 repo 範圍、同步跟收件匣、workspace 掛載在範圍選單，頂列只剩範圍 · 待處理數 · ＋（2026-11-05） | §3.6 |
| 收件匣位置 | 網頁獨立 tab（首頁 / 收件匣），面板仍摺在底（2026-11-05 改） | §3.6 |
| merged 後自動派依賴 PR | 要，規則寫死：depends-on 全 merged 且有 tasks.md 的才派，沿用父卡的 agent / 模式，kind 用自己的；記 decisions、進 banner、可停止（2026-11-05） | §3.1 |
| 自主程度實作 | 兩種（2026-11-06 由三種收成兩種）：互動 = 預設 permission；自動 = dontAsk + dispatch.sh 產的 settings allow/deny + `opsx-grant-gate.sh` + `drive.sh` 迴圈，開到可合併；codex `-a never -s workspace-write`（2026-11-05） | §3.6 · §8.5 |
| sources.toml 怎麼來 | `/opsx init` 問答產生；obsidian 資料夾、customer 平台連線都在那時填，沒填不啟用（2026-11-05） | §3.6 |
| 沒 repo 的來源 | 同步先放 `~/.local/state/opsx/unfiled/`，收件匣「待分類」組，你選 repo 才建殼；不猜（2026-11-05） | §3.6 |
| 第三個 reviewer | 加，Agent C = pstack interrogate reviewer-prompt + rubric，每次都跑，兼看測試是否證明驗收條件（2026-11-05） | §6 · §8.3 |
| 離開期間 banner | 列 新 gate / 新 MR / merged / agent 停或 blocked / 替你做的決定 / 自動派出；不列 進度、空同步、你自己的動作；以 last-seen 為界（2026-11-05） | §3.6 |
| 紀錄頁 | 網頁第三個 tab，跨卡時間軸（decisions.tsv + dispatch.json + 同步 log + archive），按日分組、四種篩選；卡內紀錄保留（2026-11-05） | §3.6 |
| kind 何時定 | 指派對話框選，預設從來源提示猜；dispatch.sh 寫 .openspec.yaml；propose 只確認，改要記 decisions（2026-11-05，推翻「propose 才定」） | §3.6 · §8.3 |
| 測試先行 | 每種 kind：propose 的 tasks.md 每 task 帶 驗收 / 測試 兩行 → apply 3b 先寫測試含邊界、確認紅 → 實作到綠 → 整卡全綠才 review；review 步 0 擋、Stop hook 擋；Router 加「tdd」關鍵詞（2026-11-05） | §8.3 |
| 看板設計系統 | Open Design `mission-control`，深色單一主題；精靈晶片形 LED 眼（2026-11-05） | §3.6 |
| 看板範圍 | 兩層 workspace → repo；卡歸屬永遠是 repo + slug；對應表 `workspaces.toml` 由 /dispatch 自動記 + 看板手動掛；agent 對卡走 dispatch.json 的 pane / session id，不經 cwd（2026-11-05） | §3.6 |
| 看板 TUI 面 | 照 tsk：範圍列 + 要你 / 在跑 / 待派 / inbox 摺疊，五個鍵 | §3.6 |
| 看板畫面結構 | 首頁 / 收件匣 / 紀錄 三個 tab（2026-11-05 改，推翻「一個畫面分段」） | §3.6 |
| kind 從哪來 | 指派時選，`dispatch.sh` 寫 `.openspec.yaml`，propose 確認（2026-11-05 改） | §3.6 · §8.3 |
| 模型配 kind | dev / refactoring / perf / experiment → opus 5.5；bug-fix / chore / ops → sonnet 5.5；指派對話框可改；review A、B sonnet，C opus；explore / grill / propose 跟卡的模型（2026-11-05） | §3.6 · §8.3 |
| drive.sh 等待 | 只用 `herdr agent wait` 阻塞，不定時 prompt 輪詢（2026-11-05） | §3.6 |
| CLI helper | `bin/opsx` + `bin/lib/*.sh`；`opsx init`（repo 層）/ `opsx init --global`；`/opsx init` 第一次跑時 symlink 到 `~/.local/bin`；`opsx status` 寫 status.json（2026-11-05） | §3.6 · §8.1 |
| explore | 主流程第一個節點，必經，固定步驟表；pstack how / blast-radius / why / prototype 掛在裡面 | §3、§8.1 |
| 一張卡 = 一個 change 殼 | 收件就 `openspec new change`，inbox.md 不空；沒有獨立 inbox 目錄 | §3、§3.1 |
| 順序強制 | openspec schema fork `opsx`：inbox → explore → grill → proposal → specs → design → tasks | §3 |
| openspec/ 進不進 git | 所有 repo 都不進 | §3 |
| gates 放哪 | `changes/<slug>/gates.md`，關閉時 decisions.tsv 補一行 | §3.6 |
| ADR | 不寫；決定在 grill.md → design.md | §3 |
| 授權三級 | 直接做 / 要授權 / 永遠要人；grants 只記第二級 | §3.6 |
| 怎麼授 | 每動作每卡預設問；gate 上答 這次 / 這個 session / 這個 repo 永遠 | §3.6 |
| commit 閘門 | deny，`[no-change]` 逃生口記 log；無 workplan 的 repo 不擋，第一次 propose 後自動生效 | §8.5 |
| grill 放哪 | plugin 內 `skills/grill/`；刪 user-level 兩個；explore 的 trigger 詞拿掉 | §4.5 |
| opsx 裝哪 | 所有開發中的 repo，含 evals、gmtc-rag；以後只用這個 plugin 開發 | §4.5 |
| kind 七種 | dev（預設，一般開發）/ bug-fix / refactoring / perf / experiment / ops / chore，各有完成條件與 playbook | §8.1 |
| inbox 來源八種 | me / agent / gitlab / github / obsidian / customer / paste / shortcut；單向同步 | §3.6 |
| grill 的位置 | 不是主流程節點，是 explore → propose 的閘門；只在 explore.md 待決非空時有事；schema 鏈不含 grill | §3、§4 |

### 未決，要定了才能開工


### 可以邊做邊定

- deepen 的介面設計：3 個 subagent 出 3 種介面（原 skill 做法）只在 deepen 流程准，還是 deepen 也跟 architect 一樣單一候選
- ~~subagent 收不收得到 `~/.claude/CLAUDE.md`~~ 已驗（2026-11-05）：general-purpose subagent 的啟動指令含 `~/.claude/CLAUDE.md` 全文（能背出 §2 第一條和 §7 標題），subagent prompt 不用加 Read。ponytail 合併已做進 §2 / §3 / §4 / §7（§8.4.1 八條：1、2、3、4、5、6、7 加了，3a、3b、8 不加）

- UserPromptSubmit 成本：先每次跑，慢了再改成 mtime 判斷
- `/explore` 要不要同步寫 tsk：不用了，tsk 不進架構

## 10. 非目標

- 不改 explore、status、sync、archive
- 不把 openspec 變成 pstack 的 playbook
- 不引入 pstack 的 autopilot-full / autopilot-stack / orchestrate；opsx 的 `--auto` 已涵蓋需要的自主程度
- 不改 security-guard / secret-mask / conventional-commit 三個現有 hook

## 11. 驗證

改寫完成後，用 skill-creator 的 eval 流程跑三個情境，比較改寫前後：

1. 一個需要 grill 的 feature（多檔案、有真實取捨）：grill 的題數、是否有題目本可靠跑 code 回答、D-id 是否原樣進 design.md 並被 review 引用
2. 一個該跳過 grill 的小 fix：是否正確說明跳過並直接 propose
3. 一個 bug fix 走 apply：是否先重現、commit 是否仍是一 change 一 commit、回覆是否帶證據標記
