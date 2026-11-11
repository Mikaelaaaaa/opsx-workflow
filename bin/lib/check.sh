#!/usr/bin/env bash
# opsx check <slug>：檢查 openspec/changes/<slug>/subs/ 底下每個子殼齊不齊（openspec CLI 只管主殼，子殼靠這支），
# 以及 agent 開的卡的事實欄位（本卡是 agent 開的，或本卡開出去的卡）。
# 一個缺項一行「subs/<子>/<檔>: <缺什麼>」，有缺項退出 1。只用 bash 與 awk：Stop hook 直接 source 它，不能依賴 python。
# 驗收：openspec/changes/split-plan/specs/subchange-propose/spec.md「opsx check 檢查子殼」；board-actions「agent 開的卡要帶事實欄位」。

opsx_check() {
  [ $# -eq 1 ] || die "check: 用法 opsx check <slug>"
  local top; top="$(git_toplevel)"
  [ -n "$top" ] || die "check: 不在 git repo 裡"
  local dir="$top/openspec/changes/$1"
  [ -d "$dir" ] || die "check: 沒有這張卡：$dir"
  local out; out="$(check_subs "$dir"; check_facts "$dir"; check_merged "$dir")"
  [ -z "$out" ] && return 0
  printf '%s\n' "$out"
  exit 1
}

# 併進這張卡的項目（inbox.md 的 ## 併入 段）要有去處：tasks.md 提到它的 id，或已經 opsx split-out。
# 有 tasks.md（propose 寫完了）或 outcome: declined（archive 正要捨棄）才檢查；沒有 tasks.md 時一個 id 都不算提到。
# 不給 Stop hook 用：explore 階段的卡本來就還沒處理併入項目。
check_merged() { # <卡目錄>：一個沒去處的 id 印一行
  local d="$1" slug id; slug="$(basename "$1")"
  [ -f "$d/inbox.md" ] || return 0
  [ -f "$d/tasks.md" ] || grep -q '^outcome: declined' "$d/.openspec.yaml" 2>/dev/null || return 0
  while IFS= read -r id; do
    [ -f "$d/tasks.md" ] && grep -qF -- "$id" "$d/tasks.md" && continue
    printf 'inbox.md: 併入 %s 沒有去處：寫成 tasks.md 的 task（帶這個 id），或 opsx split-out %s %s\n' "$id" "$slug" "$id"
  done < <(awk '/^## / { inside = ($0 ~ /^## 併入：/); next } inside && /^- id: [^ ]+ *$/ { sub(/^- id: /, ""); sub(/ +$/, ""); print }' "$d/inbox.md")
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
