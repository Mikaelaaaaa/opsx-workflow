#!/usr/bin/env bash
# opsx check <slug>：檢查 openspec/changes/<slug>/subs/ 底下每個子殼齊不齊（openspec CLI 只管主殼，子殼靠這支），
# explore.md 的 ## 步驟 九行齊不齊，以及 agent 開的卡的事實欄位（本卡是 agent 開的，或本卡開出去的卡）。
# 一個缺項一行「subs/<子>/<檔>: <缺什麼>」或「explore.md 步驟 <號> <名>: <缺什麼>」，有缺項退出 1。只用 bash 與 awk：Stop hook 直接 source 它，不能依賴 python。
# 驗收：openspec/changes/split-plan/specs/subchange-propose/spec.md「opsx check 檢查子殼」；board-actions「agent 開的卡要帶事實欄位」。

opsx_check() {
  [ $# -eq 1 ] || die "check: 用法 opsx check <slug>"
  local top; top="$(git_toplevel)"
  [ -n "$top" ] || die "check: 不在 git repo 裡"
  local dir="$top/openspec/changes/$1"
  [ -d "$dir" ] || die "check: 沒有這張卡：$dir"
  local out cand; out="$(check_explore "$dir"; check_subs "$dir"; check_facts "$dir")"; cand="$(check_blast "$top" "$dir")"
  [ -z "$cand" ] || printf '%s\n' "$cand"
  [ -z "$out" ] && return 0
  printf '%s\n' "$out"
  exit 1
}

# 步驟名與順序要跟 skills/explore/SKILL.md 的 Steps 表、schemas/opsx/templates/explore.md 一致
# 新卡（created: 晚於 2026-11-10）才查；舊卡與沒有 created: 的卡不印。stage、Stop hook、opsx check 都走這裡。
# shortcut: 日期門檻，進行中的舊卡都歸檔後拿掉
check_explore() { # <卡目錄>：explore.md 不存在什麼都不印；存在就逐步檢查 ## 步驟，缺行、留白、skip 沒原因各印一行
  [ -f "$1/explore.md" ] && [ -f "$1/.openspec.yaml" ] || return 0
  local line created=""
  while IFS= read -r line; do
    case "$line" in created:*) created="${line#created:}"; created="${created# }"; break ;; esac
  done < "$1/.openspec.yaml"
  [[ "$created" > "2026-11-10" ]] || return 0
  awk '
    BEGIN { n = split("讀卡|how|影響範圍|why|prototype|查資料|對照 code|待決|unslop", names, "|") }
    /^## / { on = ($0 == "## 步驟"); next }
    on && /^- [0-9] / {
      num = substr($0, 3, 1); prefix = "- " num " " names[num]
      if (index($0, prefix) != 1) next
      rest = substr($0, length(prefix) + 1)
      if (!sub(/^：/, "", rest) && !sub(/^:/, "", rest)) next
      gsub(/^[ \t]+|[ \t]+$/, "", rest)
      seen[num] = (rest == "") ? "blank" : (rest ~ /^skip[：:][ \t]*$/ ? "noreason" : "ok")
    }
    END {
      for (i = 1; i <= n; i++) {
        if (seen[i] == "ok") continue
        why = (seen[i] == "blank") ? "該行沒有內容" : (seen[i] == "noreason") ? "skip 沒有原因" : "缺紀錄"
        printf "explore.md 步驟 %d %s: %s\n", i, names[i], why
      }
    }
  ' "$1/explore.md"
}

# 步驟 3 寫 skip，而 main...HEAD 動到的檔案被別的檔案引用時，印 Must-fix 候選。grep 檔名只是線索：漏 shell 變數與 config key，
# 也會對只被自己測試引用的檔誤報，成不成立由 review 判斷。只在 opsx check 跑，stage 與 hook 不跑。
check_blast() { # <top> <卡目錄>
  grep -qE '^- 3 影響範圍[：:][ 	]*skip[：:]' "$2/explore.md" 2>/dev/null || return 0
  local changed f hits
  changed="$(git -C "$1" diff --name-only main...HEAD)" || die "check: git diff main...HEAD 失敗，無法對照影響範圍"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$1/$f" ] || continue
    hits="$(git -C "$1" grep -lF -- "$(basename "$f")" -- . ":!$f" ":!openspec" | paste -sd, -)"
    [ -z "$hits" ] || printf 'explore.md 步驟 3 影響範圍: skip 但 %s 被 %s 引用（Must-fix 候選，由 review 判斷）\n' "$f" "$hits"
  done <<< "$changed"
}

check_subs() { # <主殼目錄>：印缺項，一行一個；沒有 subs/ 或全齊什麼都不印
  local main="$1" name; name="$(basename "$1")"
  local s rel f spec parent d
  for s in "$main"/subs/*/; do
    [ -d "$s" ] || continue
    s="${s%/}"; rel="subs/$(basename "$s")"
    for f in proposal.md design.md tasks.md; do
      [ -f "$s/$f" ] || printf '%s/%s: 缺檔\n' "$rel" "$f"
    done
    if ! ls "$s"/specs/*/spec.md >/dev/null 2>&1; then
      printf '%s/specs: 沒有 specs/<capability>/spec.md\n' "$rel"
    fi
    for spec in "$s"/specs/*/spec.md; do
      [ -f "$spec" ] || continue
      awk -v p="$rel/${spec#"$s"/}" '
        function flush() { if (req != "" && !scen) printf "%s: Requirement「%s」沒有 #### Scenario:\n", p, req }
        /^### Requirement:/ { flush(); req = $0; sub(/^### Requirement: */, "", req); scen = 0; next }
        /^#### Scenario:/ { scen = 1 }
        END { flush() }
      ' "$spec"
    done
    if [ -f "$s/tasks.md" ]; then
      awk -v p="$rel/tasks.md" '
        function flush() {
          if (id == "") return
          if (!acc) printf "%s: task %s 缺 驗收：\n", p, id
          if (!tst) printf "%s: task %s 缺 測試：\n", p, id
        }
        /^[[:space:]]*- \[[ x]\] / { flush(); id = $0; sub(/^[[:space:]]*- \[[ x]\] */, "", id); sub(/ .*/, "", id); acc = 0; tst = 0; next }
        /^[[:space:]]*- 驗收：/ { acc = 1 }
        /^[[:space:]]*- 測試：/ { tst = 1 }
        END { flush() }
      ' "$s/tasks.md"
    fi
    if [ -f "$s/design.md" ]; then
      # LC_ALL=C：UTF-8 下中文字算 word 字元，「主殼D12」的 D12 會被 -w 漏掉
      for d in $(LC_ALL=C grep -owE 'D[0-9]+' "$s/design.md" | sort -u); do
        if [ ! -f "$main/design.md" ]; then printf '%s/design.md: 引用 %s，但主殼沒有 design.md\n' "$rel" "$d"
        elif ! LC_ALL=C grep -qwF "$d" "$main/design.md"; then printf '%s/design.md: 引用 %s，主殼 design.md 沒有\n' "$rel" "$d"; fi
      done
    fi
    parent=""; [ -f "$s/.openspec.yaml" ] && parent="$(sed -n 's/^parent: *//p' "$s/.openspec.yaml" | head -1)"
    [ "$parent" = "$name" ] || printf '%s/.openspec.yaml: parent 是「%s」，應該是「%s」\n' "$rel" "$parent" "$name"
  done
}

# 事實欄位（references/priority.md）：source 是 agent:* 的卡一定要有 kind_of_work；incident 要有 impact 與 evidence。
# 其他來源（me、paste、gitlab…）不強制，沒寫當 planned。impact 與 evidence 兩種寫法都認：同一行，或 impact: 底下縮排。
check_facts() { # <卡目錄>：印本卡與它開出去的卡（source: agent:<本卡> 或 agent:<本卡>--<子>）缺的欄位，一行一個
  local d="$1" slug c; slug="$(basename "$1")"
  facts_of_inbox "$d/inbox.md" inbox.md ""
  for c in "$(dirname "$d")"/*/; do
    c="${c%/}"
    [ "$c" != "$d" ] && [ -f "$c/inbox.md" ] || continue
    facts_of_inbox "$c/inbox.md" "$(basename "$c")/inbox.md" "agent:$slug"
  done
}

facts_of_inbox() { # <inbox.md> <顯示名> <只看這個 source，空字串是任何 agent:*>
  [ -f "$1" ] || return 0
  awk -v label="$2" -v only="$3" '
    function val(line) { sub(/^[^:]*:[ \t]*/, "", line); gsub(/<!--.*-->/, "", line); sub(/[ \t\r]+$/, "", line); gsub(/^["\047]|["\047]$/, "", line); return line }
    NR == 1 && $0 ~ /^---[ \t\r]*$/ { fm = 1; next }
    fm && $0 ~ /^---[ \t\r]*$/ { exit }
    !fm { next }
    /^source:/ { source = val($0); nested = 0; next }
    /^kind_of_work:/ { kind = val($0); nested = 0; next }
    /^impact:/ { v = val($0); nested = (v == ""); if (v != "") impact = 1; next }
    /^evidence:/ { if (val($0) != "") evidence = 1; nested = 0; next }
    nested && /^[ \t]+[A-Za-z_]+:/ {
      k = $0; sub(/^[ \t]+/, "", k); sub(/:.*/, "", k)
      if (k == "evidence") { if (val($0) != "") evidence = 1 } else if (val($0) == "true") impact = 1
      next
    }
    /^[^ \t]/ { nested = 0 }
    END {
      if (source !~ /^agent:/ || (only != "" && source != only && index(source, only "--") != 1)) exit   # 子殼 subagent 開的卡是 agent:<主>--<子>
      if (kind == "") { printf "%s: kind_of_work 沒填（要 incident 或 planned）\n", label; exit }
      if (kind != "incident" && kind != "planned") { printf "%s: kind_of_work 要是 incident 或 planned，拿到「%s」\n", label, kind; exit }
      if (kind == "incident" && !impact) printf "%s: incident 缺 impact\n", label
      if (kind == "incident" && !evidence) printf "%s: incident 缺 evidence\n", label
    }
  ' "$1"
}
