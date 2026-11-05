# Explore: 加入 User 概念 + Admin 可見所有 Todo

## 先理解現在的狀況

我看了一下現在的 codebase。這是一個非常簡單的 in-memory todo API：

```
src/
  index.js          — Express app, 掛載 /api/todos
  routes/todos.js   — CRUD routes, todos 存在 memory array 裡
```

Todo 的 schema 目前是：

```js
{ id, title, done }
```

沒有 DB，沒有 auth，沒有 user 概念。這個設計選擇會影響我們接下來怎麼做。

---

## 術語挑戰：「user」這個詞太模糊了

你說「加一個 user 的概念」，但 user 在不同系統裡可能是非常不同的東西。讓我挑戰一下這個詞：

**你說的 user，是指：**

| 選項 | 意思 |
|------|------|
| A. **Session User** | 透過 token/header 識別的呼叫者，不需要真的存在 users table |
| B. **Named Account** | 系統裡有一張 users table，每個 user 有 id + name（maybe email）|
| C. **Authenticated User** | 有密碼的登入系統，JWT session 等 |
| D. **Tenant / Workspace** | 每個 user 其實是一個隔離的租戶（多租戶架構）|

現在這個 API 連 auth 都沒有，所以「user 是誰」的問題其實有不同層次：

1. **Identity 層** — 我們怎麼知道這個 request 是誰發的？
2. **Ownership 層** — todo 屬於誰（`userId` foreign key）？
3. **Authorization 層** — admin 看得到全部，一般 user 只看自己的？

這三個問題可以各自有不同複雜度的答案。

---

## 探索幾個方向

### 方向 A：最簡單 — header-based identity（無 DB）

```
GET /api/todos
Header: X-User-Id: user-123
```

Todo 加上 `userId` field。沒有真的 users table，auth 靠 header 傳入（trust-based）。Admin 透過另一個 header 或 hardcoded user list。

**優點：** 改動最小，符合現在 in-memory 架構  
**風險：** 沒有真的身份驗證，任何人可以假裝是任何 user  
**適合：** prototype、internal tool、或還不需要真正 auth 的階段

---

### 方向 B：加 users table + simple auth

```
POST /api/auth/login    — 拿 token
GET /api/todos          — token 決定是誰
```

需要加 `/api/users` routes，users 存在 memory（或之後換 DB）。Token 可以是 simple JWT 或 session。

**優點：** 比較真實，可以之後換 DB  
**風險：** 工作量大很多，現在沒有 DB 的話 session 重啟就消失  
**適合：** 如果這個 API 之後要上 production

---

### 方向 C：middleware-based ownership（折衷）

不做完整 auth，但加一個 `userId` middleware 從 header 讀取，加上一個 `users` in-memory map 存 `{ userId, role }`。Admin role hardcoded 或透過另一個 endpoint 設定。

```
// middleware
req.user = users.get(req.headers['x-user-id']) ?? { id: req.headers['x-user-id'], role: 'user' }
```

**優點：** 有明確 user + role 概念，但不需要完整 auth  
**適合：** 你想要有清楚架構但不想現在做 JWT 的情境

---

## 幾個需要釐清的問題

在往下走之前，我需要理解幾件事：

**Q1: 「admin」是怎麼決定的？**

- A. Hardcoded（某幾個 userId 是 admin）
- B. 有個 `role` field 在 users table
- C. 另一個 header（`X-Admin-Key`）
- D. 用環境變數設定 admin user list

*[模擬回答：選 B — users 有 role field，這樣最乾淨]*

**Q2: 現在需要真的 auth（密碼登入）嗎？**

- A. 不需要，用 header trust-based 就好
- B. 需要，要做完整的 login endpoint
- C. 之後再說，先做架構讓它容易插入

*[模擬回答：選 A — 先 header-based，之後可以換]*

**Q3: Todo ownership 的 edge case：**

- 如果 request 沒帶 userId header，怎麼辦？
  - 拒絕（401）？
  - 允許匿名 todos（屬於 "anonymous"）？
- Admin 可以修改別人的 todo，還是只能「看」？

*[模擬回答：沒有 userId 就 401；admin 只能看不能改]*

---

## 基於上面的假設，我建議的方向

**路線：Middleware-based ownership，users in-memory，role 在 user object**

理由：
1. 符合現在的 in-memory 架構，不需要引入 DB
2. 有清楚的 `User` 概念（有 id + role）
3. Admin 靠 role 決定，不 hardcode
4. 後續換 DB 時，改的是 user store，不是整個架構

---

## 新的 Data Model

```
User: { id: string, role: 'user' | 'admin' }
Todo: { id: number, title: string, done: boolean, userId: string }
```

**注意術語：**
- `User` 而不是 `Account`（保持簡單）
- `role` 而不是 `isAdmin`（更 extensible）
- `userId` 在 Todo 裡（ownership，非 auth）

---

## 架構草圖

```
Request flow:

  GET /api/todos
       │
  [auth middleware]   ← reads X-User-Id header, looks up users map
       │                 → sets req.user = { id, role }
       │                 → 401 if no header / unknown user
       │
  [todos router]      ← if req.user.role === 'admin': return all todos
                         else: return todos.filter(t => t.userId === req.user.id)


  POST /api/todos
       │
  [auth middleware]
       │
  [todos router]      ← creates todo with userId = req.user.id


  POST /api/users     ← 建立 user（可設定 role）
  GET  /api/users     ← 只有 admin 可以看
```

---

## 風險 + 假設

1. **Security**: header trust-based 意味著 client 可以假裝是任何人。這在 internal tool 可接受，但 public API 不行。
2. **Persistence**: 重啟 server 就清空。如果需要 persistence 要換成 DB 或 JSON file。
3. **Bootstrap**: 誰可以建立第一個 admin？要有某種 seed 機制（hardcode 第一個 user 或 env var）。

---

## 工作分解

假設我們要實作這個，工作可以拆成：

### PR 1: User 基礎架構（低風險，先 merge）

- **commit 1**: 加 `users` in-memory store + `/api/users` CRUD routes
- **commit 2**: 加 `auth` middleware（讀 X-User-Id header，查 users map，掛 req.user）

### PR 2: Todo Ownership（有點風險，改動現有邏輯）

- **commit 3**: Todo schema 加 `userId` field，POST 時自動帶入
- **commit 4**: GET /todos 加 filter 邏輯（一般 user 只看自己的，admin 看全部）
- **commit 5**: PATCH/DELETE 加 ownership check（不能改別人的 todo）

### PR 3: Bootstrap + Edge Cases（polish）

- **commit 6**: Admin seed（env var `ADMIN_USER_ID` 或 hardcoded initial user）
- **commit 7**: 401 handling + 403 handling（auth errors 統一格式）

---

## 想繼續探索的問題

在固定方向之前，還有幾個值得想的：

1. **User 要不要 CRUD 完整？** 還是只有 POST（建立）和 GET？
2. **Admin 可以 DELETE 別人的 todo 嗎？** 你說「看到」，但 modify 呢？
3. **User 有沒有 email/name？** 還是只有 id + role 就夠了？
4. **有沒有要做 user 的 self-service？** 還是只有 admin 能建立 user？

---

我建議先確認這幾個問題，然後就可以開始寫 workplan 並 propose 具體的 changes。

你想先往哪個方向深入？
