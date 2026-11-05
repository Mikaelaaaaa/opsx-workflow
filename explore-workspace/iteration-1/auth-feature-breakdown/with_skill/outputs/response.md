# Explore: 使用者認證設計討論

## 先看一下現在的 codebase

我先把 repo 掃了一遍。這是一個非常乾淨的 Express todo API：

```
src/
  index.js          — 啟動 express，掛 /api/todos router
  routes/todos.js   — CRUD: GET / POST / PATCH /:id / DELETE /:id
package.json        — 只有 express 一個 dependency，ESM module
```

**關鍵觀察：**
- Todos 存在記憶體 array（`const todos = []`），沒有資料庫
- 完全沒有 middleware，也沒有任何 auth 相關的東西
- 沒有 CONTEXT.md、沒有 docs/、沒有 openspec/

所以這是一張白紙，設計決策的空間很大，但也表示很多事情要從頭建。

---

## JWT vs Session — 讓我先挑戰一下問題本身

在選技術之前，有一個更根本的問題：

**這個 API 的消費者是誰？**

- 如果是**前端 SPA**（React/Vue）呼叫 → JWT 比較自然（stateless，前端存 token）
- 如果是**瀏覽器 + cookie-based 的 web app**（server-side session）→ session 比較直覺
- 如果是**mobile app 或其他服務**呼叫 → JWT 幾乎是標準選擇

目前 codebase 沒有前端，純 API，這讓我往 JWT 傾斜。但讓我把兩邊的 trade-off 說清楚：

### JWT vs Session 比較

| 面向 | JWT (stateless) | Session (stateful) |
|------|-----------------|-------------------|
| 架構複雜度 | 低 — 不需要 session store | 中 — 需要 Redis/DB 存 session |
| 水平擴展 | 好 — 任何 instance 都能驗證 | 需要 sticky session 或共享 store |
| 即時撤銷 token | 難 — JWT 到期前無法廢止 | 容易 — 刪 session 即可 |
| 實作難度 | 中（需要 refresh token 機制）| 低（express-session 幾行搞定）|
| 適合這個 repo | **是** — 輕量、純 API | 不太適合 — 多餘的複雜度 |

**結論傾向：JWT。** 理由：這是純 API，沒有 session 需要的瀏覽器 cookie 場景，stateless 對純 API 更乾淨。

不過 JWT 有個常見的陷阱需要決策：**要不要實作 refresh token？**

- 只有 access token（簡單）→ token 過期就得重新登入，適合內部工具或短期 token
- Access + refresh token（標準做法）→ 更安全但要多存一層 refresh token state（這時又微妙地需要 DB）

由於 todos 現在存在記憶體，如果要上 refresh token，幾乎必然要引入 DB（至少存 users 和 refresh tokens）。

---

## Role 的問題 — 先問「為什麼」

你說不確定要不要分 role。讓我問一個更基本的問題：

**誰會用這個 API？會有不同的人需要不同的權限嗎？**

幾個常見情境：
1. **只有一種使用者**（每個人都能 CRUD 自己的 todos）→ 不需要 role，只需要 ownership
2. **有管理員需求**（例如可以看所有人的 todos、刪除任何人的 todo）→ 需要 role
3. **多租戶**（不同 team 或 organization 的 todos 隔離）→ 比 role 複雜，需要 tenant 概念

Simulated decision（eval default）: 使用情境是「每個使用者只能管理自己的 todos，另外有一個 admin 可以看所有 todos」→ 需要簡單的 role（user / admin 兩種）。

---

## 目前我看到的核心 gap

現在 todos 存在記憶體 array，要加 auth 的話，幾乎必須同步解決這些問題：

```
目前狀態:
  todos = []   ← 記憶體，沒有 owner 概念，沒有持久化

加 auth 需要:
  users 表/物件  ← 存帳號密碼（hashed）
  todos 加 userId  ← 每個 todo 要知道屬於誰
  某種持久化  ← 不然重啟就掉資料（包括 user 帳號）
```

**這是一個隱藏的 scope 問題。** 加 auth 不只是加 middleware，還拉出了「要不要加 DB」這個問題。

可能的路徑：
- **Path A：最小可行** — 用 in-memory users map（`Map<id, User>`），不加 DB，接受重啟掉資料。適合原型/學習。
- **Path B：加 SQLite** — 輕量、file-based，不需要跑 server，適合這個規模的 API。
- **Path C：加 PostgreSQL** — 如果之後要部署上 GCP 或配合 Agentory-CS 的 infra，這是正確的方向。

Simulated decision（eval default）: 選 **Path B（SQLite）**，因為比記憶體多一點真實感，又不需要 Docker。

---

## 整體設計草圖

```
POST /api/auth/register   → 建立帳號（hash password with bcrypt）
POST /api/auth/login      → 驗證，回傳 JWT access token
POST /api/auth/logout     → （可選）廢止 token

middleware: authenticate  → 驗證 JWT，把 user 掛到 req.user
middleware: authorize(role) → 檢查 req.user.role

GET  /api/todos           → 回傳 req.user 自己的 todos
POST /api/todos           → 建立，自動帶 userId = req.user.id
PATCH /api/todos/:id      → 只能改自己的
DELETE /api/todos/:id     → 只能刪自己的
GET  /api/admin/todos     → [admin only] 所有人的 todos
```

Todo 資料結構要加 `userId`:
```js
{ id, title, done, userId, createdAt }
```

---

## 工作拆分

整個功能可以拆成三個 PR，按風險和關注點分開：

### PR 1: `feat/auth-infra` — 基礎設施（低風險，先合）
建 DB schema、user model、auth utilities。不動現有任何 route。
- 變更 1: `add-sqlite-and-schema` — 引入 better-sqlite3，建 users 和 todos 表
- 變更 2: `add-auth-utilities` — bcrypt hash/verify、JWT sign/verify 工具函數

### PR 2: `feat/auth-core` — 認證邏輯（核心，仔細 review）
Auth routes + middleware。depends on PR 1。
- 變更 1: `add-auth-middleware` — `authenticate` + `authorize(role)` middleware
- 變更 2: `add-auth-routes` — POST /auth/register、POST /auth/login

### PR 3: `feat/todos-auth-integration` — 整合（最後，depends on PR 1 + PR 2）
把現有 todos route 接上 auth。這是破壞性變更，需要謹慎。
- 變更 1: `migrate-todos-to-db` — 把 in-memory array 換成 SQLite
- 變更 2: `add-todo-ownership` — todos 加 userId，所有 CRUD 加 authenticate middleware，過濾自己的資料
- 變更 3: `add-admin-todos-route` — GET /admin/todos，加 authorize('admin')

---

**Simulated AskUserQuestion:**

> 這個拆法你覺得如何？有幾個選項：
>
> A. 照這個三 PR 計畫走，先建 infra，再建 auth，最後整合
> B. 把 PR 1 + PR 2 合併成一個（因為 infra 很小），只做兩個 PR
> C. 不加 DB，用 in-memory map 就好，讓計畫更簡單
> D. 我有其他想法

**Default answer chosen: A** — 三 PR 拆法，照計畫走。

---

Workplan 已寫入 `openspec/workplan.yaml`。可以用 `/apply` 開始執行第一個 PR。
