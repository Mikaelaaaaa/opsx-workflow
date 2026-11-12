#!/usr/bin/env bash
# docs/orca-spike.md 驗證紀錄的形狀：八項都有判定、過與不過附指令和輸出、未驗附原因、結論對得回紀錄。
# 驗收：openspec/changes/me-20261112-1015-2/specs/orca-spike/spec.md「每項都有判定」「未驗沒有原因就不算寫完」
#   「過或不過要附證據」「socket 不過就停」「結論對得回紀錄」「有項目沒過就不能結論為換」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DOC="$OPSX_ROOT/docs/orca-spike.md"
ITEMS='socket 連線、socket 重開後、自訂啟動參數、啟動參數重開後、worker_done 叫醒、escalation 叫醒、授權閘門、orca serve 常駐'

# 一個問題印一行，有問題退出 1。表格列：| 項目 | 指令 | 輸出 | 判定 | 原因 |
check_record() { # <紀錄檔>
  awk -v items="$ITEMS" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    BEGIN { n = split(items, it, "、"); for (i = 1; i <= n; i++) want[it[i]] = 1 }
    /^\|/ {
      split($0, c, "|"); name = trim(c[2])
      if (!(name in want)) next
      seen[name] = 1; cmd = trim(c[3]); out = trim(c[4]); v = trim(c[5]); why = trim(c[6]); verdict[name] = v
      if (v != "過" && v != "不過" && v != "未驗") { print name ": 判定「" v "」不是過、不過、未驗"; bad = 1 }
      else if (v == "未驗" && why == "") { print name ": 未驗沒有原因"; bad = 1 }
      else if (v != "未驗" && (cmd == "" || out == "")) { print name ": 判定" v "但沒附指令或輸出"; bad = 1 }
      next
    }
    /^結論：/ { concl = trim(substr($0, length("結論：") + 1)) }
    /^依據：/ { basis = trim(substr($0, length("依據：") + 1)) }
    END {
      for (i = 1; i <= n; i++) if (!(it[i] in seen)) { print it[i] ": 紀錄裡沒有這一列"; bad = 1 }
      if (concl != "換" && concl != "不換" && concl != "補條件再驗") { print "結論「" concl "」不是換、不換、補條件再驗"; bad = 1 }
      if (basis == "") { print "結論沒有依據"; bad = 1 }
      m = split(basis, b, "、")
      for (i = 1; i <= m; i++) if (!(trim(b[i]) in seen)) { print "依據「" trim(b[i]) "」在紀錄裡找不到"; bad = 1 }
      if (concl == "換") for (k in verdict) if (verdict[k] != "過") { print "結論是換，但" k "是" verdict[k]; bad = 1 }
      exit bad
    }' "$1"
}

# 造一份紀錄：八項，第 <項> 列換成 <判定>/<證據欄>，其餘都過；<結論> <依據>
mk_record() { # <檔> <項> <判定> <證據欄> <結論> <依據>
  local f="$1" i cmd out why
  printf '| 項目 | 指令 | 輸出 | 判定 | 原因 |\n|---|---|---|---|---|\n' > "$f"
  printf '%s\n' "${ITEMS//、/$'\n'}" > "$FX/items"
  while IFS= read -r i; do
    if [ "$i" = "$2" ]; then
      cmd=''; out=''; why=''
      case "$4" in 指令與輸出) cmd='`orca status`'; out='runtimeReachable: true';; 原因) why='socket 不過，依派工指示停下';; esac
      printf '| %s | %s | %s | %s | %s |\n' "$i" "$cmd" "$out" "$3" "$why" >> "$f"
    else
      printf '| %s | `orca status` | runtimeReachable: true | 過 | |\n' "$i" >> "$f"
    fi
  done < "$FX/items"
  printf '\n結論：%s\n依據：%s\n' "$5" "$6" >> "$f"
}

# --- Scenario Outline「過或不過要附證據」：一般場景與邊界場景各列 ---
r="$FX/r.md"
mk_record "$r" 授權閘門 過 指令與輸出 換 授權閘門;            check_record "$r" >/dev/null || fail "過+指令與輸出 要 PASS: $(check_record "$r")"
mk_record "$r" 授權閘門 不過 指令與輸出 不換 授權閘門;        check_record "$r" >/dev/null || fail "不過+指令與輸出 要 PASS: $(check_record "$r")"
mk_record "$r" 授權閘門 未驗 原因 補條件再驗 授權閘門;        check_record "$r" >/dev/null || fail "未驗+原因 要 PASS: $(check_record "$r")"
mk_record "$r" 授權閘門 過 空 不換 授權閘門;                  check_record "$r" >/dev/null && fail "過但沒附輸出 要 FAIL"
mk_record "$r" 授權閘門 未驗 空 不換 授權閘門
out="$(check_record "$r")" && fail "未驗沒原因 要 FAIL"
case "$out" in *"授權閘門: 未驗沒有原因"*) ;; *) fail "要指出是哪一項: $out";; esac
mk_record "$r" 授權閘門 待確認 指令與輸出 不換 授權閘門;      check_record "$r" >/dev/null && fail "判定不在三種值 要 FAIL"

# --- 少一列、結論對不回紀錄、有項目沒過卻結論為換 ---
mk_record "$r" 授權閘門 過 指令與輸出 不換 授權閘門
grep -v '^| orca serve 常駐 ' "$r" > "$FX/missing.md"; check_record "$FX/missing.md" >/dev/null && fail "少一列 要 FAIL"
mk_record "$r" 授權閘門 過 指令與輸出 不換 不存在的項目;      check_record "$r" >/dev/null && fail "依據找不到 要 FAIL"
mk_record "$r" 授權閘門 不過 指令與輸出 換 授權閘門;          check_record "$r" >/dev/null && fail "有不過卻結論換 要 FAIL"
mk_record "$r" 授權閘門 過 指令與輸出 也許 授權閘門;          check_record "$r" >/dev/null && fail "結論不在三種值 要 FAIL"

# --- 真的紀錄 ---
assert_file "$DOC"
out="$(check_record "$DOC")" || fail "docs/orca-spike.md 形狀不對:
$out"
echo ok
