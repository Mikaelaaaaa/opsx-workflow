#!/usr/bin/env bash
# 用法：bash setup.sh <dest>
# 建一個沒有 remote 的 repo，內含一張報表匯出的邏輯表與它的 design.md、explore.md。
# 不是 opsx commit 的快照，所以不用 _lib.sh。fallback_role 只寫在 design.md 與邏輯表，explore.md 沒提。
set -euo pipefail

dest="${1:?dest}"
mkdir -p "$dest"
git -C "$dest" init -q -b feat/report-export/dev
ch="$dest/openspec/changes/report-export"
mkdir -p "$ch"

cat > "$ch/logic-map.md" <<'EOF'
# 邏輯表：feat/report-export/dev

範圍：`main...feat/report-export/dev` · 讀的檔：2 個 · 功能：1 個

## 功能 1：使用者匯出報表前先過三道檢查

### 做了什麼
1. `export_report()` 收到匯出請求，載入使用者與報表（`src/export.py`）。
2. 帳號停用就擋下，記成 `export_denied: disabled`。
3. 取使用者角色；角色欄位空時用 `fallback_role = "viewer"`（`src/export.py`）。
4. 角色不在 `EXPORT_ROLES` 就擋下，記成 `export_denied: role`（`src/permissions.py`）。
5. 報表部門跟使用者部門不同就擋下，記成 `export_denied: dept`。
6. 三道都過，產生 CSV 回給使用者。

### 流程圖
```
匯出請求 → D1 帳號停用? ─是→ 擋，記 export_denied: disabled
               └否→ 取角色（空→viewer） → D2 角色在EXPORT_ROLES? ─否→ 擋，記 export_denied: role
                                                └是→ D3 報表部門=使用者部門? ─否→ 擋，記 export_denied: dept
                                                         └是→ 產生CSV
```

### 條件表
| 節點 | 決策 | 條件（FEEL） | 結果 | 位置 |
|---|---|---|---|---|
| D1 | 帳號停用? | `user.disabled = true` | 是：擋，記 `export_denied: disabled`；否：取角色 | `src/export.py:12` |
| D2 | 角色在 EXPORT_ROLES? | `list contains(["admin","analyst"], if user.role = null or user.role = "" then "viewer" else user.role)` | 否：擋，記 `export_denied: role`；是：到 D3 | `src/permissions.py:8` |
| D3 | 報表部門=使用者部門? | `report.dept = user.dept` | 否：擋，記 `export_denied: dept`；是：產生CSV | `src/export.py:21` |

### ⚠ 要看的地方
1. D2：`EXPORT_ROLES` 寫死成 `["admin","analyst"]` 兩個角色，要加一個能匯出的角色就得改程式（`src/permissions.py:3`）。
2. D2：角色欄位空時用 `fallback_role = "viewer"`，沒角色的帳號被當 viewer 擋下，使用者看到的是 `export_denied: role`，而不是「沒設定角色」（`src/export.py:16`）。
EOF

cat > "$ch/design.md" <<'EOF'
## Context

報表頁要加「匯出 CSV」。只有 admin 與 analyst 能匯出。停用的帳號不能匯出。不能匯出別的部門的報表。

## Goals / Non-Goals

**Goals:**
- 匯出前依序檢查帳號停用、角色、部門，任一不過就擋，並記下擋的原因。

**Non-Goals:**
- 不做排程匯出，不做 Excel 格式。

## Decisions

三道檢查的順序：先看 `user.disabled`，再看角色是否在 `EXPORT_ROLES = ["admin", "analyst"]`，最後比 `report.dept == user.dept`。擋下時記 `export_denied: <原因>`，原因是 `disabled`、`role`、`dept` 三者之一。

舊帳號有些角色欄位是空的。為了讓角色檢查不碰到空值，實作時在取角色的地方加 `fallback_role = "viewer"`：角色欄位空就當成 viewer。viewer 不在 `EXPORT_ROLES`，所以這些帳號會在角色檢查被擋下。

`EXPORT_ROLES` 先寫成常數放在 `src/permissions.py`，不做成設定。

## Risks / Trade-offs

- [角色欄位空的帳號被擋時，記的原因是 role，看不出是沒設定角色] → 先不處理。
EOF

cat > "$ch/explore.md" <<'EOF'
# 報表匯出

## 已知
- 只有 admin 與 analyst 可以匯出報表。
- 帳號停用的人不能匯出。
- 不能匯出別的部門的報表，只能匯出自己部門的。
- 被擋時要記下原因，方便客服查。

## 待決

## 不做
- 排程匯出。
- Excel 格式，只做 CSV。
EOF

git -C "$dest" add -A
git -C "$dest" -c user.name=dev -c user.email=dev@example.com commit -q -m init
