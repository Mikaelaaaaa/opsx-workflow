#!/usr/bin/env bash
# SessionStart / UserPromptSubmit：看 changes/<slug>/ 的狀態，注入一行「階段 · slug · kind · Read 清單」。
# 平行流程關鍵詞優先；prompt 說 tdd → apply 3b 只寫測試。要求檔 §8.3 Router 表、§8.5。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

top="$(repo_top)"
[ -n "$top" ] && [ -d "$top/openspec" ] || exit 0   # 不是 opsx repo，什麼都不印

ev="$(hook_event)"; ev="${ev:-UserPromptSubmit}"
prompt="$(hook_prompt)"
lower="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"

for kw in babysit pickup pause forensics correct reflect audit deepen dispatch; do
  case " $lower " in *"/$kw "*|*" $kw "*|*"/$kw"*)
    ctx "$ev" "opsx 平行流程：$kw · Read skills/$kw/SKILL.md；做完下一次 prompt 重讀主流程狀態"; exit 0 ;;
  esac
done

stage="$(card_stage)"
case " $lower " in *" tdd "*|*"/tdd"*|*"tdd "*)
  slug="$(card_slug)"
  ctx "$ev" "opsx：tdd · ${slug:-?} · 只做 apply 骨架 3b（照 tasks.md 的 驗收 / 測試 兩行寫測試含邊界，跑一次確認紅，commit test:），寫完停，不實作 · Read skills/apply/SKILL.md · skills/tdd/SKILL.md"; exit 0 ;;
esac
ctx "$ev" "opsx：$stage"
