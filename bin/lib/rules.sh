#!/usr/bin/env bash
# 每張卡依模式要遵守的行為規則，一個來源：router hook 每句 prompt 注入（claude），
# dispatch 渲染進 codex worktree 的 AGENTS.md（bin/lib/agents-md.sh）。改這裡兩邊一起變。
# 不含前導 ` · `；段與段用 ` · ` 隔開，AGENTS.md 依它拆成條列。

rule_autopilot() {
  printf '%s' 'autopilot：要問人的事寫 gates.md（type: approval | decision；要使用者在終端機跑指令的另加 needs: run；type: approval 的要寫 action:，值照 hook deny 訊息裡的抄；type: decision 的題要等別張卡合進 main 才能做的，另加 waits-on: <卡名>，coordinate 只憑這一行停 pane），不用 AskUserQuestion、不在 pane 問；gate 一律由使用者答，協調者不代答；不是產品取捨、也可逆的題採 Recommended，記「自動採用」；操作類的題（等 subagent、等背景工作、要不要跑全套測試）不開 gate，照建議做、記「自動採用」 · Bash 會被 dontAsk 拒的寫法：for / while（不寫迴圈）、把命令替換的結果賦值給變數再展開、命令替換裡放 pipe、{ } 群組、source 或 .、bash -c 跑多段、印 $?；一個 Bash 呼叫做一件事，讀多個檔用 Read 或 cat a b c，記決定用 opsx log，路徑寫字面絕對路徑 · worktree 裡沒有 `openspec/`（不進 git）：openspec 指令寫成 cd <主 checkout 絕對路徑> && openspec …，下一個指令先 cd <worktree 根> 回來（cd 會留到後面每個 Bash 呼叫，測試、opsx、git、router 都看 cwd），卡的檔案讀寫主 checkout 的 openspec/changes/<slug>/ · 跑測試一律 bash tests/run.sh <檔名過濾>，指令前不加 `VAR=…` 或 `export`（前綴環境變數對不到 dontAsk 的 Bash(bash tests/:*)）'
}

rule_interactive() {
  printf '%s' 'interactive：要授權就直接問，不寫 gate'
}
