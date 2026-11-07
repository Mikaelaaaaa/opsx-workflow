---
type: bug
source: you
found: 2026-11-06
---

## 一句話

標題結尾有標點時，網址多一個 `-`：「Hello World!」產生 `/posts/hello-world-`，應該是 `/posts/hello-world`。開頭有標點也一樣（「(Draft) Notes」產生 `-draft-notes`）。

- 後台存檔時已經擋掉沒有英文字母或數字的標題，slugify 不會收到這種輸入
- 網站還沒公開，沒有已發布的舊網址要轉址
