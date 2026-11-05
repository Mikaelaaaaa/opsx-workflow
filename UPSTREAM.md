# UPSTREAM

搬進來或蒸餾過的檔，來源與版本。升版時拿這張表逐檔 diff。沒列的就是 opsx 自己寫的。

| 本地檔 | 來源 | 版本 | 改了什麼 |
|---|---|---|---|
| `skills/explore/references/prototype.md` | cursor-plugins/pstack `skills/poteto-mode/playbooks/prototype.md` | 0.15.34 | 併入 `~/.claude/skills/prototype`（logic / UI 兩分支、一個指令跑、印狀態、用完刪）；「Feature」改成 dev playbook；control skill 改成直接截圖 |
| `skills/grill/SKILL.md` | `~/.claude/skills/grill-me` + `~/.claude/skills/grill-with-docs` | 2026-11-05 當時版本 | 合併成一支；加三桶分類（查 code / 跑一次 / 問人）、D-id 輸出、`opsx status`；去掉 CONTEXT.md 以外的文件更新 |
| `skills/grill/references/ADR-FORMAT.md` | `~/.claude/skills/grill-with-docs/ADR-FORMAT.md` | 同上 | 末段加一句 grill.md D-id 與 ADR 的關係 |
| `skills/grill/references/CONTEXT-FORMAT.md` | `~/.claude/skills/grill-with-docs/CONTEXT-FORMAT.md` | 同上 | 刪 example dialogue 段，加「決定不放這裡」 |
| `schemas/opsx/templates/{proposal,spec,design}.md` | `@fission-ai/openspec` `schemas/spec-driven/templates/` | 1.3.1（`opsx init` 時 fork，不在 repo 裡） | 原樣 |
| `schemas/opsx/templates/tasks.md` | 同上 `tasks.md` | 1.3.1 | 每 task 加 `驗收：` `測試：` 兩行 |
| `references/harness-claude-code.md` | cursor-plugins/pstack `docs/harness/claude-code.md` | 0.15.34 | `<pstack>` 改指 opsx 根；`/pstack:<name>` → `/opsx:<name>`；`poteto-agent`/`comment-sicko` → `general-purpose`；加 principle / playbook 路徑對照列；Models：claude slug 也 omit `model`（單一模型），`pstack-models.mdc` 標「不用」，加「不同 model family → 同一 family 不同 effort」列；刪 setup-pstack 段；Cursor-only 表加 `arena` / `create-skill` / `deslop`、`control-ui` 三列與 glab 指令 |
| `skills/how/SKILL.md` | pstack `skills/how/SKILL.md` | 0.15.34 | adapter 路徑；模型段改「session model，`model` 不設」（上游預設 slug 留在括號）；刪「per the Subagents section of poteto-mode」 |
| `skills/how/references/{explorer,explainer}-prompt.md` | pstack `skills/how/references/` | 0.15.34 | 原樣 |
| `skills/why/SKILL.md` | pstack `skills/why/SKILL.md` | 0.15.34 | adapter 路徑；模型段同 how；Step 2 加 GitLab 的 `glab mr view` 與 `!<iid>` 寫法 |
| `skills/why/references/{epistemics,investigator-prompt,synthesizer-prompt}.md` | pstack `skills/why/references/` | 0.15.34 | 原樣 |
| `skills/why/references/source-playbook.md` | pstack `skills/why/references/source-playbook.md` | 0.15.34 | 六個沒搬的 source playbook（linear/notion/slack/datadog/sentry/databricks）連結改成「not shipped」並加一段怎麼補 |
| `skills/why/references/sources/{code-archaeology,incident-postmortem}.md` | pstack `skills/why/references/sources/` | 0.15.34 | 原樣（其餘六份不搬，搬遷清單 §2 定） |
| `skills/blast-radius/SKILL.md` | pstack `skills/blast-radius/SKILL.md` | 0.15.34 | 步 6 arena → 一個 fresh subagent 再讀一次 |
| `skills/architect/SKILL.md` | pstack `skills/architect/SKILL.md` | 0.15.34 | adapter 路徑；Phase B arena → 單一 runner（上游兩個 runner 留括號）；「Design it twice」改成 runner 必列至少一個結構不同的 alternative；Scrap 步 4「re-run arena」→「re-run the sketch」；開頭「multiple model perspectives」一句改掉 |
| `skills/architect/references/design-red-flags.md` | pstack `skills/architect/references/design-red-flags.md` | 0.15.34 | 原樣 |
| `skills/architect/references/rationale-template.md` | pstack `skills/architect/references/rationale-template.md` | 0.15.34 | Synthesis decision 段：arena 連結改成 runner 自填 |
| `skills/architect/references/runner-prompt.md` | pstack `skills/architect/references/runner-prompt.md` | 0.15.34 | 首尾兩段「parallel runners / different model」改成單一 runner 要列 alternative |
| `skills/interrogate/SKILL.md` | pstack `skills/interrogate/SKILL.md` | 0.15.34 | adapter 路徑；Step 3 reviewer 表改「session model，A 用 session effort、B 低一級；小 diff 只跑 A」；刪 slug 拒絕的 fallback 段；「models」改「reviewers」；刪 poteto-mode 引用 |
| `skills/interrogate/references/{rubric,reviewer-prompt,code-quality-review,lead-judgment}.md` | pstack `skills/interrogate/references/` | 0.15.34 | 原樣 |
| `skills/benchmark-checklist/SKILL.md` | pstack `skills/benchmark-checklist/SKILL.md` | 0.15.34 | 「per the Opening a PR playbook」→「per the `pr` skill」 |
| `skills/tdd/SKILL.md` | pstack `skills/tdd/SKILL.md` | 0.15.34 | description 改成 apply 3b 每種 kind 都讀；加「What a good test looks like」一段：蒸餾 `~/.claude/skills/tdd` 的 integration-style 與反 horizontal-slicing（2026-11-05 做了） |
| `skills/technical-writing/SKILL.md` | pstack `skills/technical-writing/SKILL.md` | 0.15.34 | adapter 路徑 |
| `skills/unslop/SKILL.md` | pstack `skills/unslop/SKILL.md` | 0.15.34 | 原樣 |
| `skills/show-me-your-work/SKILL.md` | pstack `skills/show-me-your-work/SKILL.md` | 0.15.34 | adapter 路徑；transcript 路徑改 `~/.claude/projects/<slug>/`；刪整段「Cross-model review of the trail」（含 Attention 段） |
| `skills/show-me-your-work/references/decision-log-template.tsv` | pstack 同路徑 | 0.15.34 | 原樣 |
| `skills/show-me-your-work/scripts/log.sh` | pstack `skills/show-me-your-work/scripts/log.sh` | 0.15.34 | 原樣（執行位元要自己 `chmod +x`，sandbox 設不了） |
| `skills/ketchup/SKILL.md` | pstack `skills/ketchup/SKILL.md` | 0.15.34 | 原樣（`/visualize` 是 Cursor 內建，這裡沒有，照 adapter 印 skip） |
| `skills/correct/SKILL.md` | pstack `skills/correct/SKILL.md` | 0.15.34 | 原樣 |
| `skills/reflect/SKILL.md` | pstack `skills/reflect/SKILL.md` | 0.15.34 | adapter 路徑；步 1 transcript 路徑與 ls 改 Claude Code；模型表改 session model（上游欄位留著）；步 5「不改 plugins/cache、放 .cursor/skills」改成「改 opsx 自己的 skills/、references/，不動 plugin cache，UPSTREAM.md 記一筆」；`create-skill` → `skill-creator` |
| `skills/reflect/references/synthesizer.md` | pstack `skills/reflect/references/synthesizer.md` | 0.15.34 | `create-skill` → `skill-creator`（三處） |
| `skills/reflect/references/{judgment,tooling,divergent}-reviewer.md` | pstack `skills/reflect/references/` | 0.15.34 | `.cursor/skills/`、`~/.cursor/plugins/` → `.claude/skills/`、plugin 的 `skills/` |
| `skills/teach/SKILL.md` | pstack `skills/teach/SKILL.md` | 0.15.34 | adapter 路徑 |
| `skills/bro/SKILL.md` | pstack `skills/bro/SKILL.md` | 0.15.34 | 原樣 |
| `skills/sharpen/SKILL.md` | pstack `skills/sharpen/SKILL.md` | 0.15.34 | 原樣 |
| `skills/typescript-best-practices/SKILL.md` + `references/patterns.md` | pstack `skills/typescript-best-practices/` | 0.15.34 | 原樣 |
| `skills/apply/references/playbooks/dev.md` | pstack `playbooks/feature.md` | 0.15.34 | 標題 Feature → Dev；步 2 architect 單候選；步 4 模型 → session model、arena → delegate 自己列 shape 選一個、「Comments」→ `references/comments.md`、「Commit liberally」→ 一 change 一 commit；步 8 Opening a PR → `pr` skill |
| `skills/apply/references/playbooks/bug-fix.md` | pstack `playbooks/bug-fix.md` | 0.15.34 | 步 1 control skill → 「用手邊最近的方式重現」；步 2「Cursor's /loop」→「the /loop command」；步 3 模型；步 6 → `pr` skill；刪 Subagents section 引用；蒸餾 `~/.claude/skills/diagnose`：加 1b minimise、步 2 的 3–5 條可證偽假設與 `[DEBUG-…]` 標籤 instrument、5b 收尾清單（2026-11-05 做了） |
| `skills/apply/references/playbooks/refactoring.md` | pstack `playbooks/refactoring.md` | 0.15.34 | Feature → Dev；figure-it-out → 拆成多個 change；步 3 architect 單候選；步 5 migrate-callers 限 design.md 列的 caller，範圍外寫 inbox 卡（§8.2 裁決）、模型；步 6 control skill 一句刪；步 8 → `pr` skill |
| `skills/apply/references/playbooks/perf.md` | pstack `playbooks/perf-issue.md` | 0.15.34 | 改名 perf；步 1 control skill → 「用手邊的 profiler（control skill: skip）」；步 3 模型；步 6 → `pr` skill；hillclimb 路徑改同目錄 |
| `skills/apply/references/playbooks/hillclimb.md` | pstack `playbooks/hillclimb.md` | 0.15.34 | 步 4 路徑 → `perf.md`；步 5 模型、刪 autonomous-run wake 那句；步 8 → `pr` skill |
| `skills/apply/references/playbooks/eval.md` | pstack `playbooks/eval.md` | 0.15.34 | 步 4、5 arena 多模型 → 一般 `general-purpose` subagent、fresh context；步 6 transcript 路徑改 Claude Code；刪 Subagents section 引用 |
| `skills/explore/references/investigation.md` | pstack `playbooks/investigation.md` | 0.15.34 | Feature → Dev；「(see Autonomy)」→ 一句 candor over agreement |
| `skills/babysit/SKILL.md` | pstack `playbooks/babysit.md` | 0.15.34 | 升格成 skill（加 frontmatter）；只留 `check` / `threads-only` 兩個 mode；刪 watch-pr、Origin、`/loop` 輪詢、autopilot 引用、Shipping 交接；步 6 改成一次 `glab mr view` / `gh pr view`；步 8 加 glab 回覆指令；bugbot-triage 路徑改 `../../references/`；forge 預設 glab |
| `skills/pickup/SKILL.md` | pstack `playbooks/session-pickup.md` | 0.15.34 | 升格成 skill；transcript 路徑改 Claude Code；步 1 加 `pause` 的 `wip:` commit 當來源；步 2 加 openspec 的 tasks.md / decisions.tsv / report.md；步 4 routed playbook = apply 依 kind |
| `skills/pause/SKILL.md` | pstack `playbooks/pause-safely.md` | 0.15.34 | 升格成 skill（加 frontmatter），內文原樣 |
| `skills/forensics/SKILL.md` | pstack `playbooks/runtime-forensics.md` + `playbooks/trace-forensics.md` | 0.15.34 | 兩個 playbook 合成一支 skill、兩個 mode；runtime 步 1 control skill → 「用手邊能抓的方式」；刪 Subagents section 引用；開頭加結論去哪（inbox 卡或 perf/bug-fix 的 explore.md） |
| `references/principles/<name>.md`（24 支） | pstack `skills/principle-<name>/SKILL.md` | 0.15.34 | 去 frontmatter；`../principle-X/SKILL.md` 連結改同目錄 `X.md`；explain-the-number 的 benchmark-checklist 連結改 `../../skills/`；prove-it-works 的 adapter 路徑改 `../harness-claude-code.md`；其餘原樣 |
| `references/principles/INDEX.md` | pstack `skills/poteto-mode/SKILL.md` §Principles | 0.15.34 | 每條一行照抄；加四個 §8.2 裁決的括號（outcome-oriented / migrate-callers 限 design.md 範圍、experience-first / exhaust 只在 prototype、never-block 分層） |
| `references/writing-the-reply.md` | pstack `skills/poteto-mode/SKILL.md` §Writing the reply | 0.15.34 | 原樣；PR 連結句加 GitLab 格式；末尾加 ponytail 的「跳過 / 沒查 / 風險」一句（← ponytail `.agents/rules/ponytail.md` @ 96608e0） |
| `references/comments.md` | pstack `skills/poteto-mode/SKILL.md` §Comments | 0.15.34 | 原樣；加 ponytail 的 `shortcut:` 格式一段（← ponytail `.agents/rules/ponytail.md` @ 96608e0） |
| `references/bugbot-triage.md` | pstack `skills/poteto-mode/references/bugbot-triage.md` | 0.15.34 | 開頭 `../playbooks/babysit.md` → `../skills/babysit/SKILL.md` |
| `skills/review/references/ponytail-review.md` | ponytail `skills/ponytail-review/SKILL.md` | v5.3.3 @ 96608e0 | 去 frontmatter，原樣（review 的 SKILL.md 讀它時 scope 改 `git diff main...HEAD`，見要求檔 §8.4.2） |
| `skills/audit/SKILL.md` | ponytail `skills/ponytail-audit/SKILL.md` | v5.3.3 @ 96608e0 | 改名 audit；§4 Output 改寫：每條 finding 一個 `openspec new change`、inbox.md 寫 type/source/severity/四部分、建殼前去重、Verdict / Lean / Not checked 只回 chat（要求檔 §8.4.3）；description 加「接手 repo」觸發句 |
| `herdr-board/sync/debt.sh` | ponytail `skills/ponytail-debt/SKILL.md` | v5.3.3 @ 96608e0 | grep 指令與 `<ceiling>, <trigger>` 解析變 shell script，掃 `~/code/*/` 有 openspec/ 的 repo，每筆印一行 JSON（repo/file/line/comment/hash/limit/trigger/no_trigger），hash = sha1(註解)[:8]，略過 `.claude/worktrees/`；不寫 PONYTAIL-DEBT.md（要求檔 §8.4.4）。執行位元要自己 `chmod +x` |
| `skills/deepen/SKILL.md` | `~/.claude/skills/improve-codebase-architecture/SKILL.md` | 2026-11-05 當時版本 | 改名 deepen；LANGUAGE.md 連結改 `references/architecture-language.md`；步 3 grill-with-docs 引用改 `grill`、ADR 改成「理由記在候選列」；加步 4 開 kind=refactoring 的殼；INTERFACE-DESIGN 三 subagent 與 architect 單候選的衝突標為未決、暫以一個 subagent 跑 |
| `skills/deepen/references/deepening.md` | 同上 `DEEPENING.md` | 同上 | LANGUAGE.md 連結改 `references/architecture-language.md`；破折號改句號 |
| `skills/deepen/references/interface-design.md` | 同上 `INTERFACE-DESIGN.md` | 同上 | 同上，開頭加未決註記 |
| `references/architecture-language.md` | 同上 `LANGUAGE.md` | 同上 | 開頭改成三個使用者（deepen / architect / refactoring playbook）；破折號改句號；末尾加一段對 design-red-flags 詞彙的對照 |
