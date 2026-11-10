#!/usr/bin/env bash
# opsx check <主 change>：檢查 openspec/changes/<主>/subs/ 底下每個子殼齊不齊（openspec CLI 只管主殼，子殼靠這支），
# 以及 explore.md 的 ## 步驟 九行齊不齊。
# 一個缺項一行「subs/<子>/<檔>: <缺什麼>」或「explore.md 步驟 <號> <名>: <缺什麼>」，有缺項退出 1。只用 bash 與 awk：Stop hook 直接 source 它，不能依賴 python。
# 驗收：openspec/changes/split-plan/specs/subchange-propose/spec.md「opsx check 檢查子殼」。

opsx_check() {
  [ $# -eq 1 ] || die "check: 用法 opsx check <主 change>"
  local top; top="$(git_toplevel)"
  [ -n "$top" ] || die "check: 不在 git repo 裡"
  local dir="$top/openspec/changes/$1"
  [ -d "$dir" ] || die "check: 沒有這張卡：$dir"
  local out; out="$(check_explore "$dir"; check_subs "$dir")"
  [ -z "$out" ] && return 0
  printf '%s\n' "$out"
  exit 1
}

# 步驟名與順序要跟 skills/explore/SKILL.md 的 Steps 表、schemas/opsx/templates/explore.md 一致
check_explore() { # <卡目錄>：explore.md 不存在什麼都不印；存在就逐步檢查 ## 步驟，缺行、留白、skip 沒原因各印一行
  [ -f "$1/explore.md" ] || return 0
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
