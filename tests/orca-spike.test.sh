#!/usr/bin/env bash
# docs/orca-spike.md 驗證紀錄的形狀：八項都有判定、過與不過附指令和輸出、未驗附原因、結論對得回紀錄。
# 驗收：openspec/changes/me-20261112-1015-2/specs/orca-spike/spec.md「每項都有判定」「未驗沒有原因就不算寫完」
#   「過或不過要附證據」「socket 不過就停」「socket 過了不能跳項」「結論對得回紀錄」「有項目沒過就不能結論為換」
# 儲存格裡不能有 |：awk 用 | 切欄。
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
      if (name in seen) { print name ": 紀錄裡有兩列"; bad = 1 }
      seen[name] = 1; cmd = trim(c[3]); out = trim(c[4]); v = trim(c[5]); why = trim(c[6]); verdict[name] = v; reason[name] = why
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
      stopped = (verdict["socket 連線"] == "不過")
      for (k in verdict) {
        if (k == "socket 連線") continue
        if (stopped && (verdict[k] != "未驗" || index(reason[k], "socket 不過") == 0)) { print k ": socket 不過就要停，這項應是未驗、原因 socket 不過"; bad = 1 }
        if (!stopped && index(reason[k], "socket 不過") > 0) { print k ": socket 沒有不過，不能用 socket 不過當原因跳項"; bad = 1 }
      }
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
      case "$4" in
        指令與輸出) cmd='`orca status`'; out='runtimeReachable: true';;
        只有指令) cmd='`orca status`';;
        只有輸出) out='runtimeReachable: true';;
        原因) why='不需要（不換引擎）';;
      esac
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
mk_record "$r" 授權閘門 過 只有輸出 不換 授權閘門;            check_record "$r" >/dev/null && fail "過但沒附指令 要 FAIL"
mk_record "$r" 授權閘門 過 只有指令 不換 授權閘門;            check_record "$r" >/dev/null && fail "過但沒附輸出 要 FAIL"
mk_record "$r" 授權閘門 不過 空 不換 授權閘門;                check_record "$r" >/dev/null && fail "不過但沒附證據 要 FAIL"

# --- Requirement「socket 不過就停」：socket 不過時其餘七項都未驗、原因是 socket 不過；socket 過時不能拿這個原因跳項 ---
SOCKET_STOP='socket 不過，依派工指示停下'
printf '| 項目 | 指令 | 輸出 | 判定 | 原因 |\n|---|---|---|---|---|\n| socket 連線 | `orca status` | EPERM | 不過 | |\n' > "$FX/stop.md"
printf '%s\n' "${ITEMS#socket 連線、}" | tr '、' '\n' | sed "s/.*/| & | | | 未驗 | $SOCKET_STOP |/" >> "$FX/stop.md"
printf '\n結論：不換\n依據：socket 連線\n' >> "$FX/stop.md"
check_record "$FX/stop.md" >/dev/null || fail "socket 不過、其餘未驗 要 PASS: $(check_record "$FX/stop.md")"
sed 's/^| 授權閘門 | | | 未驗 | .*/| 授權閘門 | `echo x` | x | 過 | |/' "$FX/stop.md" > "$FX/stop-ran.md"
out="$(check_record "$FX/stop-ran.md")" && fail "socket 不過後還驗了別項 要 FAIL"
case "$out" in *"授權閘門"*) ;; *) fail "要指出是哪一項: $out";; esac
sed 's/^| socket 連線 | `orca status` | EPERM | 不過 |/| socket 連線 | `orca status` | runtimeReachable: true | 過 |/' "$FX/stop.md" > "$FX/skip.md"
check_record "$FX/skip.md" >/dev/null && fail "socket 過卻用 socket 不過當原因跳項 要 FAIL"

# --- 少一列、結論對不回紀錄、有項目沒過卻結論為換 ---
mk_record "$r" 授權閘門 過 指令與輸出 不換 授權閘門
grep -v '^| orca serve 常駐 ' "$r" > "$FX/missing.md"; check_record "$FX/missing.md" >/dev/null && fail "少一列 要 FAIL"
mk_record "$r" 授權閘門 過 指令與輸出 不換 不存在的項目;      check_record "$r" >/dev/null && fail "依據找不到 要 FAIL"
mk_record "$r" 授權閘門 不過 指令與輸出 換 授權閘門;          check_record "$r" >/dev/null && fail "有不過卻結論換 要 FAIL"
mk_record "$r" 授權閘門 未驗 原因 換 授權閘門;                check_record "$r" >/dev/null && fail "有未驗卻結論換 要 FAIL"
mk_record "$r" 授權閘門 未驗 原因 換 授權閘門
awk '/^結論：換$/ { print "| 授權閘門 | `echo x` | x | 過 | |" } { print }' "$r" > "$FX/dup.md"
grep -c '^| 授權閘門 ' "$FX/dup.md" > "$FX/dup.count"; assert_eq "$(cat "$FX/dup.count")" 2 "dup fixture 要有兩列"
out="$(check_record "$FX/dup.md")" && fail "重複的列蓋掉未驗再結論換 要 FAIL"
case "$out" in *"授權閘門: 紀錄裡有兩列"*) ;; *) fail "要指出重複的項目: $out";; esac
mk_record "$r" 授權閘門 過 指令與輸出 也許 授權閘門;          check_record "$r" >/dev/null && fail "結論不在三種值 要 FAIL"

# --- 真的紀錄 ---
assert_file "$DOC"
out="$(check_record "$DOC")" || fail "docs/orca-spike.md 形狀不對:
$out"
echo ok
