# Todo API 使用者認證設計與工作拆解

## 現況分析

這是一個極簡的 Express Todo API：
- 純記憶體儲存（`todos` 陣列，沒有資料庫）
- 無任何認證/授權機制
- 4 個端點：GET / POST / PATCH / DELETE
- 沒有「使用者」概念，todos 是全域共享的
- 只有一個 dependency：`express`

加入認證前，需要先決定兩件事：
1. **要不要加資料庫**（目前是記憶體，重啟就消失）
2. **要不要加 role 分級**

---

## 建議決策

### JWT vs Session

**建議選 JWT。** 理由如下：

| 考量點 | JWT | Session |
|--------|-----|---------|
| 無狀態 | 是，易橫向擴展 | 否，需 session store |
| API-first 適合度 | 高（Bearer token） | 低（設計上更偏瀏覽器） |
| 目前專案複雜度 | 輕量，只需加 `jsonwebtoken` | 需要 `express-session` + store |
| 登出/撤銷困難度 | 較難（需 blacklist 或短 TTL） | 容易（刪 session 即可） |

這個 Todo API 是 REST API 風格，沒有 server-rendered 頁面，JWT 是更自然的選擇。用短 TTL（例如 15 分鐘）+ refresh token 可以緩解撤銷問題，但初版可以先用單一 access token 保持簡單。

### 要不要分 Role

**建議初版加兩個 role：`user` 和 `admin`。** 理由：

- `user`：只能 CRUD 自己的 todos
- `admin`：可以看所有使用者的 todos、刪除任何 todo

這樣的設計成本低，但為未來擴展保留了彈性。如果完全不加 role，之後要補會需要改 JWT payload 結構和所有需要授權的端點，代價更大。

---

## 前置假設（eval 模式下自行選定合理預設值）

- 加入一個輕量資料庫（**SQLite + better-sqlite3**，零設定、適合單機）
- 使用者表格：`users(id, email, password_hash, role)`
- Todo 表格加上 `owner_id` foreign key
- 不做 refresh token（初版，降低複雜度）
- JWT secret 從環境變數讀取（`JWT_SECRET`）

---

## 工作項目拆解

以下工作按照依賴順序排列，每個 issue 都可以獨立執行。

---

### Issue 1：加入資料庫層（SQLite + schema）

**目標**：建立持久化基礎，讓後續的使用者和 todo 資料有地方存。

**工作內容**：
- `npm install better-sqlite3`
- 建立 `src/db/index.js`，初始化 SQLite 連線
- 建立 migration/init script，建立 `users` 和 `todos` 兩張 table：
  ```sql
  CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'user'
  );
  CREATE TABLE todos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    done INTEGER NOT NULL DEFAULT 0,
    owner_id INTEGER NOT NULL REFERENCES users(id)
  );
  ```
- 把 `src/routes/todos.js` 裡的記憶體陣列改成查 SQLite

**驗收條件**：
- 啟動後 `todos.db` 自動建立
- 現有 CRUD 端點行為不變（不含認證）

---

### Issue 2：密碼 hash 工具 + 使用者 model

**目標**：建立使用者資料的讀寫邏輯，為之後的註冊/登入端點準備。

**依賴**：Issue 1

**工作內容**：
- `npm install bcrypt`（或 `bcryptjs` 如果想避免 native binding）
- 建立 `src/models/users.js`，包含：
  - `createUser(email, password, role='user')` — hash 密碼後寫入 DB
  - `findUserByEmail(email)` — 回傳整筆 user 含 `password_hash`
  - `findUserById(id)` — 回傳 user（不含 `password_hash`）
- 撰寫單元測試（`src/models/users.test.js`），覆蓋 create + findBy

**驗收條件**：
- `npm test` 對 users model 全綠
- 密碼不以明文存入 DB

---

### Issue 3：JWT 工具函式（簽發 + 驗證）

**目標**：封裝 JWT 邏輯，讓 auth routes 和 middleware 都能統一使用。

**依賴**：無（可與 Issue 2 平行）

**工作內容**：
- `npm install jsonwebtoken`
- 建立 `src/lib/jwt.js`：
  - `signToken(payload)` — 簽發 JWT，TTL 15m，secret 從 `process.env.JWT_SECRET`
  - `verifyToken(token)` — 驗證並回傳 payload，失敗拋出錯誤
- 撰寫單元測試：正常 sign/verify、過期 token 應拋錯

**驗收條件**：
- 測試全綠
- `JWT_SECRET` 未設置時啟動要報錯（fail-fast）

---

### Issue 4：Auth 路由（註冊 + 登入）

**目標**：提供 `POST /api/auth/register` 和 `POST /api/auth/login` 端點。

**依賴**：Issue 2、Issue 3

**工作內容**：
- 建立 `src/routes/auth.js`：
  - `POST /register`：接收 `email` + `password`，建立 user，回傳 JWT
  - `POST /login`：驗證 email/password（bcrypt compare），回傳 JWT
- 在 `src/index.js` 掛上 `app.use('/api/auth', authRouter)`
- 錯誤處理：email 重複 → 409、密碼錯誤 → 401
- 撰寫整合測試

**驗收條件**：
- 可用 curl/httpie 走完 register → login → 拿到 token 流程
- 錯誤狀態碼正確

---

### Issue 5：Authentication middleware

**目標**：建立 `requireAuth` middleware，保護需要登入的端點。

**依賴**：Issue 3

**工作內容**：
- 建立 `src/middleware/auth.js`：
  - `requireAuth`：從 `Authorization: Bearer <token>` 解出 JWT，注入 `req.user`，失敗回 401
- 撰寫 middleware 單元測試（mock req/res）

**驗收條件**：
- 沒帶 token → 401
- 帶壞 token → 401
- 帶好 token → `req.user` 有 `{ id, email, role }`，呼叫 `next()`

---

### Issue 6：Authorization middleware（role check）

**目標**：建立 `requireRole(role)` middleware，支援 admin-only 端點。

**依賴**：Issue 5

**工作內容**：
- 在 `src/middleware/auth.js` 加上 `requireRole(role)` factory：
  - 若 `req.user.role` 不符合要求 → 403
- 撰寫測試：user 嘗試 admin 端點 → 403；admin 可通過

**驗收條件**：
- middleware 測試全綠
- role 不符時回 403（不是 401）

---

### Issue 7：Todo 端點加上 owner 隔離 + admin 可覽全局

**目標**：把 todos 的 CRUD 與登入使用者綁定，user 只看自己的，admin 看全部。

**依賴**：Issue 1、Issue 5、Issue 6

**工作內容**：
- 所有 todo 端點加上 `requireAuth` middleware
- `GET /` → user 只回傳 `owner_id = req.user.id` 的 todos；admin 回傳全部
- `POST /` → todo 的 `owner_id` 設為 `req.user.id`
- `PATCH /:id`、`DELETE /:id` → user 只能操作自己的（非自己的 → 403）；admin 無限制
- 更新 `src/routes/todos.js` 的整合測試

**驗收條件**：
- user A 無法看到/刪除 user B 的 todo
- admin 可操作任何 todo
- 未登入呼叫任何 todo 端點 → 401

---

### Issue 8：環境設定 + 文件

**目標**：讓新開發者一個指令就能跑起來。

**依賴**：以上所有 issues

**工作內容**：
- 建立 `.env.example`：
  ```
  PORT=3000
  JWT_SECRET=changeme
  ```
- 更新 `package.json` scripts 加上 `"db:init": "node src/db/init.js"`
- 在 README（或 `docs/auth.md`）寫下：
  - 環境變數說明
  - 快速起步步驟（clone → cp .env.example .env → npm install → npm run db:init → npm run dev）
  - 端點列表含認證需求

**驗收條件**：
- 照 README 步驟可以在乾淨環境跑起來

---

## 執行順序建議

```
Issue 1（DB）
    ├── Issue 2（User model）
    │       └── Issue 4（Auth routes）
    │                   └── Issue 7（Todo owner 隔離）
    └── Issue 3（JWT util）── Issue 5（Auth middleware）── Issue 6（Role middleware）
                                                                    └── Issue 7
                                                                    
Issue 8 最後
```

Issues 2 和 3 可以平行進行；Issue 7 是整合點，等所有前置完成再做。

---

## 補充：後續可以考慮但不在初版範圍內

- Refresh token（access token 短 TTL + refresh token 換新）
- Email 驗證（註冊後寄驗證信）
- Rate limiting（防暴力破解 /login）
- Admin 管理介面（CRUD users）
- 把 role 改成更彈性的 permissions table
