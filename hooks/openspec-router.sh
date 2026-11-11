#!/usr/bin/env bash
# SessionStart / UserPromptSubmit：看 changes/<slug>/ 的狀態，注入一行「階段 · slug · kind · Read 清單」，
# 卡派出去過的話後面再接這張卡模式的行為規則。沒對到卡時那一行改列進行中 change 與各自的 `/<stage> <slug>`。
# 平行流程關鍵詞優先；prompt 說 tdd → apply 3b 只寫測試。要求檔 §8.3 Router 表、§8.5、§3.6 自主程度表。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/rules.sh"

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
    autopilot|drive) rule=" · $(rule_autopilot)" ;;
    interactive) rule=" · $(rule_interactive)" ;;
  esac
fi

# 第二站之後由 drive 送、重派由 coordinate 送，都不帶指示；只有這裡每句都跑，所以由這裡提醒。每句都跑，只用 awk 不起 python
card="$(card_dir)"
if [ -n "$card" ] && [ -f "$card/inbox.md" ]; then
  notes="$(awk '/^## 派工指示[[:space:]]*$/ { f = 1; next } /^## / { f = 0 } f && /^- / { n++ } END { print n + 0 }' "$card/inbox.md")"
  if [ "$notes" -gt 0 ]; then rule=" · 派工指示 $notes 條 · Read $card/inbox.md ## 派工指示 · 跟 D 衝突開 gate$rule"; fi
fi

pkw=""
for kw in babysit pickup pause forensics correct reflect audit deepen dispatch; do
  case " $lower " in *"/$kw "*|*" $kw "*|*"/$kw"*|*"/opsx-workflow:$kw"*) pkw="$kw"; break ;; esac
done
case "$prompt" in
  *反思*) pkw="${pkw:-reflect}" ;;
  *糾正*) pkw="${pkw:-correct}" ;;
esac
if [ -n "$pkw" ]; then
  ctx "$ev" "opsx 平行流程：$pkw · Read $OPSX_ROOT/skills/$pkw/SKILL.md；做完下一次 prompt 重讀主流程狀態$rule"; exit 0
fi

if [ -n "$card" ]; then stage="$(card_stage)"
else
  stage="$(active_changes "$top" | awk '{ s = s (NR == 1 ? "：" : " · ") $0 } END { printf "explore · 沒有對到卡 · 進行中 %d 張%s · 新工作先建殼 · skills/explore/SKILL.md", NR, s }')"
fi
case " $lower " in *" tdd "*|*"/tdd"*|*"tdd "*)
  ctx "$ev" "opsx：tdd · ${slug:-?} · 只做 apply 骨架 3b（照 tasks.md 的 驗收 / 測試 兩行寫測試含邊界，跑一次確認紅，不單獨 commit，測試留在工作區，之後跟實作同進該 change 的一個 commit），寫完停，不實作 · Read skills/apply/SKILL.md · skills/tdd/SKILL.md$rule"; exit 0 ;;
esac
ctx "$ev" "opsx：$stage$rule"
