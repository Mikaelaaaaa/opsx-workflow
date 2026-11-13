# Logic map examples

Three complete maps. The first two are real opsx code at `main` 6312881. The third is a product feature, to show the format outside opsx.

---

## Example 1: a Bash hook (PR #100, commit gate)

# 邏輯表：fix/commit-gate-cwd/mikaela-lin

範圍：`58f3045...7b30eef` · 讀的檔：1 個 · 功能：1 個

## 這支 PR 在做什麼（業務說明）
這支 PR 影響在 opsx 裡做卡、要 commit 的使用者或 agent。以前 commit 閘門拿 session 所在的 repo 找卡，現在改從指令裡切換的目錄算出 commit 寫進的 repo。例：session 開在主目錄，指令先切到卡的 worktree 再 commit，閘門就用那個 worktree 的分支找卡，看卡上有沒有勾掉的 task。目錄寫成變數或家目錄符號這類讀不出的寫法時，閘門算不出目標，改看 session 所在的 repo：那個 repo 有用 opsx 就擋下，請對方改寫成實際路徑；沒用 opsx 就放行。

## 功能 1：commit 閘門用 commit 實際作用的 repo 來對卡

### 業務上在做什麼
agent 在卡的 worktree 下 commit 指令。閘門先從指令算出 commit 寫進哪個 repo；那個 repo 沒用 opsx，或 commit 訊息帶了不需要卡的標記，就放行，否則用它的分支找卡，找不到卡或卡上沒有勾掉的 task 就擋。agent 看到被擋的原因與該怎麼改；目錄讀不出時，閘門改看 session 所在的 repo，有用 opsx 才擋，並請對方改用實際路徑。

### 做了什麼
1. 從 Bash 指令取出骨架，不是 `git commit` 就放行（`hooks/openspec-commit-gate.sh`）。
2. 從骨架找 `git -C <目錄>` 與它前面最後一個 `cd <目錄>`。
3. 目錄含引號、變數、`~` 或萬用字元時記成「讀不出」。
4. 讀得出時，以 session 目錄為起點接上 `cd` 再接 `-C`，得到 commit 的目標目錄。
5. 目標 repo 沒有 `openspec/workplan.yaml` 就放行；有的話，讀不出的目錄直接擋。
6. commit 訊息有 `[no-change]` 就放行並記 `bypass.log`。
7. 用目標 repo 的 branch 找卡；找不到卡或 tasks.md 沒勾就擋。

### 流程圖
```
Bash 指令 → D1 是 git commit? ─否→ 放行
                 └是→ D2 目錄讀得出? ─是→ 目標 = cwd + cd + -C ─┐
                          └否→ 記 bad_dirs ───────────────────┤
                                                                ▼
D3 有 workplan.yaml?（既有） ─否→ 放行，提示未啟用
     └是→ D4 有 bad_dirs? ─是→ 擋：改用字面路徑
              └否→ D5 有 [no-change]?（既有） ─是→ 放行，記 bypass.log
                       └否→ D6 branch 對得到卡?（既有） ─否→ 擋：先開卡
                                └是→ D7 tasks.md 有勾?（既有） ─否→ 擋：先做完一個 task
                                         └是→ 放行
```

### 條件表
| 節點 | 決策 | 條件（FEEL） | 結果 | 位置 |
|---|---|---|---|---|
| D1 | 是 git commit? | `matches(骨架, "(^|\s|&&|\|\||;)git\s+(-C\s+\S+\s+)?commit(\s|$)")` | 否 → 放行 | hooks/openspec-commit-gate.sh:9 |
| D2 | 目錄讀得出? | `every d in [cd目錄, C目錄] satisfies not(d in ["\"\"", "''"]) and not(matches(d, "[\"'$`~\\*?\[{]"))` | 否 → 記 bad_dirs | hooks/openspec-commit-gate.sh:23 |
| D3 | 有 workplan.yaml?（既有） | `exists(file 目標repo + "/openspec/workplan.yaml")` | 否 → 放行並提示 | hooks/openspec-commit-gate.sh:38 |
| D4 | 有 bad_dirs? | `bad_dirs != ""` | 是 → 擋 | hooks/openspec-commit-gate.sh:42 |
| D5 | 有 no-change?（既有） | `contains(指令全文, "[no-change]")` | 是 → 放行並記 log | hooks/openspec-commit-gate.sh:46 |
| D6 | branch 對得到卡?（既有） | `card_dir(branch(目標repo)) != null` | 否 → 擋 | hooks/openspec-commit-gate.sh:53 |
| D7 | tasks.md 有勾?（既有） | `tasks_done(卡) > 0` | 否 → 擋 | hooks/openspec-commit-gate.sh:56 |

D2 只取「`git commit` 前面最後一個 `cd`」：`cd a && cd b && git commit` 只認 `b`，相對路徑時會接錯。D3 排在 D4 前面，所以沒有 workplan 的 repo，目錄讀不出也放行。

### ⚠ 要看的地方
- D2：`cd a && cd b && git commit` 的目標算成 `cwd/b`，實際是 `cwd/a/b`；b 是相對路徑時會對錯卡。
- D2：`git -C` 只取第一個；`git -C a -C b commit` 的 `b` 被略過。
- A1：目標目錄不存在時（`[ -d "$target" ]` 不成立，:32）悄悄退回 session 目錄，沒有提示。

---

## Example 2: a Python decision chain (coordinator answers gates)

# 邏輯表：feat/opsx-coordinate/mikaela-lin

範圍：`<base>...6312881`（節錄 `handle_gate`）· 讀的檔：1 個 · 功能：1 個

## 這支 PR 在做什麼（業務說明）
這支 PR 影響在 opsx 裡做卡的 agent，以及要回答 gate 的使用者。agent 停下來開 gate 時，協調者照固定順序的規則，決定自己代答、轉給使用者，還是讓這張卡停著等別張卡。例：agent 開等待授權的 gate 問要不要開 PR，協調者只看動作和問題，裡面沒有「合併」或 merge，就直接回允許，agent 繼續做。其他 gate 若沒有在等別張卡，只要全文出現「合併」，就算只是要把主線合進分支解衝突，協調者也不答，改發桌面通知給使用者。

## 功能 1：協調者決定代答、轉人，還是停 pane

### 業務上在做什麼
agent 開了 gate 等回覆。協調者由上往下比對規則，第一條成立就照它做，後面不看；等待授權的 gate 只看動作和問題有沒有「合併」或 merge，其他 gate 看全文。agent 收到代答就繼續，或被停住等別張卡；協調者不答時，使用者收到桌面通知，要去看板回答。

### 做了什麼
1. 讀這張卡第一個 open gate（`bin/lib/coordinate.py` `handle_gate`）。
2. 依序比對九條規則，第一條成立就結束，後面不看。
3. 不代答的情況記 `??` log 並發桌面通知（`notify_gate`）。
4. 都不成立時，照 gate 的建議代答（`answer`）。

### 流程圖
```
open gate → D1 要人跑指令? ─是→ 不答，通知
               └否→ D2 等待授權? ─是→ D3 合併授權? ─是→ 不答，通知
                        │                 └否→ 回「允許」
                        └否→ D4 type 不明或拆法確認? ─是→ 不答，通知
                                 └否→ D5 等別張卡? ─是→ 停 pane
                                          └否→ D6 合併類? ─是→ 不答，通知
                                                   └否→ 接 D7（下一段）
```

```
D7 題型? ─驗證→ 回「等使用者驗」
   ├授權→ 回「允許」
   └其他→ D8 有建議? ─否→ 不答，通知
              └是→ D9 建議要人動手? ─是→ 不答，通知
                       └否→ 代答建議
```

### 條件表
| 節點 | 決策 | 條件（FEEL） | 結果 | 位置 |
|---|---|---|---|---|
| D1 | 要人跑指令? | `gate.needs = "run"` | 是 → 不答，通知 | bin/lib/coordinate.py:356 |
| D2 | 等待授權? | `gate.type = "等待授權"` | 是 → D3 | bin/lib/coordinate.py:360 |
| D3 | 合併授權? | `some k in MERGE_WORDS satisfies contains(lower case(gate.action + " " + gate.question), k)` | 是 → 不答；否 → 回「允許」 | bin/lib/coordinate.py:362 |
| D4 | type 不明 / 拆法確認? | `gate.type = "type 不明" or gate.id = "split"` | 是 → 不答，通知 | bin/lib/coordinate.py:374, :378 |
| D5 | 等別張卡? | `gate.waits_on != null` | 是 → 停 pane | bin/lib/coordinate.py:386 |
| D6 | 合併類? | `some k in MERGE_WORDS satisfies contains(lower case(gate 全文), k)`。比對的是全文，所以排在 D7 前面時，含「合併」的驗證題與授權題都在這裡被攔下 | 是 → 不答，通知 | bin/lib/coordinate.py:394 |
| D7 | 題型 | `if some k in VERIFY_WORDS satisfies contains(gate.question, k) then "驗證" else if some k in GRANT_WORDS satisfies contains(gate.question, k) then "授權" else "其他"` | 驗證 → 固定答；授權 → 回「允許」 | bin/lib/coordinate.py:398, :401 |
| D8 | 有建議? | `gate.pick != null and gate.pick != ""` | 否 → 不答，通知 | bin/lib/coordinate.py:404 |
| D9 | 建議要人動手? | `(some k in HUMAN_WORDS satisfies contains(gate.pick, k)) or (some k in HUMAN_QUESTION satisfies contains(gate.question, k))` | 是 → 不答；否 → 代答 | bin/lib/coordinate.py:408 |

詞表（bin/lib/coordinate.py:37–42）：`MERGE_WORDS = ["合併","merge"]`；`VERIFY_WORDS` 8 個（真機、實測、瀏覽器、resume…）；`GRANT_WORDS` 7 個（授權、開 PR、push、rebase…）；`HUMAN_WORDS` 10 個（你、使用者、沙盒外、跑指令…）。

### ⚠ 要看的地方
- D6：用「全文含『合併』或『merge』」判斷合併決定。「把 origin/main 合併進分支解衝突」也成立，協調者就不答。2026-11-11 有三個 gate 因此停住。
- D6 排在 D7 前：問題寫「push 前要先 merge main 嗎」的授權題，到不了 D7 的授權分支。
- D9：`HUMAN_WORDS` 有單字「你」。建議寫「照你上一輪的做法」也算要人動手。
- N：不答時只發桌面通知，沒有送到協調者 session。

---

## Example 3: a product feature (remember user preferences)

# 邏輯表：feat/remember-preferences/mikaela-lin

範圍：`a1b2c3d...e4f5a6b` · 讀的檔：3 個 · 功能：2 個

## 這支 PR 在做什麼（業務說明）
這支 PR 影響跟助理對話的使用者。助理會從對話裡挑出使用者的偏好記下來，之後回答時把相關的偏好帶進去。健康、宗教、政治類的偏好，要使用者明確同意才存。例：使用者說「我今天開始早上都喝黑咖啡」，之前沒記過這項偏好、信心分數也到門檻，助理就存下來；但句子裡有「今天」，到期時間就設成當天晚上 11 點 59 分，隔天的回答不會再帶到它。

## 功能 1：決定要不要記住一個偏好

### 業務上在做什麼
助理從使用者的訊息抽出可能的偏好。系統先看信心分數夠不夠，敏感類還要有明確同意；已經有同一項偏好時，值相同只更新時間，值不同而訊息裡有「以後都」就覆蓋，其他情況先問使用者。使用者看到的是之後的回答有沒有用上這個偏好，或是被問一句要不要更新；訊息裡有「今天」的偏好，當晚就不再用。

### 做了什麼
1. `extract_prefs(msg)` 從訊息抽出候選偏好（`memory/extract.py`）。
2. `should_store(c, existing)` 逐個判斷存不存（`memory/policy.py`）。
3. 存下的偏好若只限今天，到期設成今天 23:59（`memory/store.py`）。

### 流程圖
```
候選偏好 c → D1 可信? ─否→ 丟掉
                └是→ D2 敏感類? ─是→ D3 明確同意? ─否→ 不存
                         │                 └是→ (到D4)
                         └否→ D4 怎麼存? ─問用戶→ 問用戶確認
                                  └新增、覆蓋或更新時間→ D5 只限今天? ─是→ 到期 = 今天 23:59
                                                             └否→ 不設到期
```

### 條件表
| 節點 | 決策 | 條件（FEEL） | 結果 | 位置 |
|---|---|---|---|---|
| D1 | 可信? | `c.confidence >= 0.7` | 否 → 丟掉 | memory/policy.py:14 |
| D2 | 敏感類? | `c.category in ["health","religion","politics"]` | 是 → D3 | memory/policy.py:18 |
| D3 | 明確同意? | `c.explicit_consent = true` | 否 → 不存 | memory/policy.py:19 |
| D4 | 怎麼存? | `if existing[c.key] = null then "新增" else if existing[c.key].value = c.value then "更新時間" else if contains(msg, "以後都") then "覆蓋" else "問用戶"` | 四選一 | memory/policy.py:23 |
| D5 | 只限今天? | `contains(msg, "今天")` | 是 → 到期今天 23:59 | memory/store.py:41 |

### ⚠ 要看的地方
- D1：`0.7` 寫死在程式裡，沒有名字也沒有註解。
- D4：「明講永久」靠訊息含「以後都」判斷。「以後都不要」這種否定句也會覆蓋。
- D5：訊息裡只要有「今天」就設今天到期。「我今天開始吃素」是長期偏好，會在今晚過期。

## 功能 2：把偏好注入上下文

### 業務上在做什麼
使用者送出訊息，助理準備回答。系統先去掉過期的偏好，依跟訊息的相關度排序；總長度超過 500 token 時，從沒有明講、最久沒更新的偏好開始拿掉。使用者看到的回答只用上留下來的偏好；超長的那個偏好如果優先度最高，會排到最後才被拿掉，回答就一個偏好都沒用上，也沒有提示。

### 做了什麼
1. `build_context(prefs, msg)` 去掉 `expires_at < now()` 的偏好（`memory/context.py`）。
2. 依跟訊息的相關度排序。
3. 總 token 超過 500 時，從優先度最低的開始移除。
4. 剩下的接在 system prompt 後面。

### 流程圖
```
偏好清單 → 去掉過期 → 依相關度排序 → D1 超過預算? ─是→ 移除優先度最低 →(回D1)
                                           └否→ 接到 system prompt
```

### 條件表
| 節點 | 決策 | 條件（FEEL） | 結果 | 位置 |
|---|---|---|---|---|
| D1 | 超過預算? | `sum(ctx[item].tokens) > 500`；移除順序 `sort(ctx, function(a,b) a.explicit < b.explicit or (a.explicit = b.explicit and a.updated_at < b.updated_at))` 的第一個 | 是 → 移除後再比 | memory/context.py:27 |

### ⚠ 要看的地方
- D1：只有一個偏好就超過 500 token 時，清單會移除到空，回答時完全沒有偏好，也沒有記錄。
- A2：相關度排序的結果沒有用在移除順序上；移除只看「明講」與時間，最相關的偏好也可能先被移除。
