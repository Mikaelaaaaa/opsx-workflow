#!/usr/bin/env bash
# SessionStart / UserPromptSubmit：看 changes/<slug>/ 的狀態，注入一行「階段 · slug · kind · Read 清單」，
# 卡派出去過的話後面再接這張卡模式的行為規則。
# 平行流程關鍵詞優先；prompt 說 tdd → apply 3b 只寫測試。要求檔 §8.3 Router 表、§8.5、§3.6 自主程度表。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

top="$(repo_top)"
[ -n "$top" ] && [ -d "$top/openspec" ] || exit 0   # 不是 opsx repo，什麼都不印

ev="$(hook_event)"; ev="${ev:-UserPromptSubmit}"
prompt="$(hook_prompt)"
lower="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"

# autopilot 的 agent 一在 pane 裡問，herdr 就判 blocked，drive 送不進下一句，所以每一句 prompt 都提醒
rule=""
slug="$(card_slug)"
if [ -n "$slug" ] && [ -n "${OPSX_PY:-}" ]; then
  case "$(card_mode "$(basename "$top")" "$slug" 2>/dev/null || true)" in
    autopilot|drive) rule=" · autopilot：要問人的事寫 gates.md（type: approval | decision；要使用者在終端機跑指令的另加 needs: run），不用 AskUserQuestion、不在 pane 問；不是產品取捨、也可逆的題採 Recommended，記「自動採用」 · Bash 會被 dontAsk 拒的寫法：for / while（不寫迴圈）、把命令替換的結果賦值給變數再展開、命令替換裡放 pipe、{ } 群組、source 或 .、bash -c 跑多段、印 \$?；一個 Bash 呼叫做一件事，讀多個檔用 Read 或 cat a b c，記決定用 opsx log，路徑寫字面絕對路徑" ;;
    interactive) rule=" · interactive：要授權就直接問，不寫 gate" ;;
  esac
fi

for kw in babysit pickup pause forensics correct reflect audit deepen dispatch; do
  case " $lower " in *"/$kw "*|*" $kw "*|*"/$kw"*)
    ctx "$ev" "opsx 平行流程：$kw · Read skills/$kw/SKILL.md；做完下一次 prompt 重讀主流程狀態$rule"; exit 0 ;;
  esac
done

stage="$(card_stage)"
case " $lower " in *" tdd "*|*"/tdd"*|*"tdd "*)
  ctx "$ev" "opsx：tdd · ${slug:-?} · 只做 apply 骨架 3b（照 tasks.md 的 驗收 / 測試 兩行寫測試含邊界，跑一次確認紅，不單獨 commit，測試留在工作區，之後跟實作同進該 change 的一個 commit），寫完停，不實作 · Read skills/apply/SKILL.md · skills/tdd/SKILL.md$rule"; exit 0 ;;
esac
ctx "$ev" "opsx：$stage$rule"
