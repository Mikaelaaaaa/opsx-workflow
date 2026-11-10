#!/usr/bin/env bash
# stage-cmd-prefix：程式送出、hook 指示、references 與 skills 接續句裡要 agent 執行的節點指令，一律 /opsx-workflow:<stage>。
# 裸短名會被 Claude Code 內建指令蓋掉（/review → /code-review）。驗收：specs/stage-command-name/spec.md「文字契約由測試守住」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STAGES='explore|grill|propose|apply|review|pr|babysit|archive'

# 程式與 hook：略過整行註解與行尾註解（空白 # 空白 之後）；裸的 /<stage>，或 /$stage、/$first 這種拼出來的裸短名
code_hits() { # <file>
  sed -E -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]+#[[:space:]].*$//' "$1" \
    | grep -nE -- "(^|[^A-Za-z0-9:_./-])/($STAGES)([^A-Za-z0-9_-]|\$)|/\\\$\\{?(stage|first)([^A-Za-z0-9_]|\$)" || true
}
# references 與 skills：只看反引號裡的指令，標題（# /review）與說明句不算
md_hits() { # <file>
  grep -nE -- "\`/($STAGES)([^A-Za-z0-9_-]|\$)" "$1" || true
}

# --- 掃描器本身：抓得到裸短名，放過帶前綴的與註解 ---
T="$FX/scan"; mkdir -p "$T"
printf '%s\n' 'herdr agent prompt x "/review slug"' > "$T/bare.sh"
printf '%s\n' 'herdr agent prompt x "/$stage $slug"' > "$T/dyn.sh"
printf '%s\n' 'herdr agent prompt x "/opsx-workflow:review slug"' '# 註解裡提到 /review 不算' > "$T/ok.sh"
printf '%s\n' '接下來跑 `/review <slug>`' > "$T/bare.md"
printf '%s\n' '接下來跑 `/opsx-workflow:review <slug>`' '# /review' > "$T/ok.md"
[ -n "$(code_hits "$T/bare.sh")" ] || fail "掃描器抓不到裸的 /review"
[ -n "$(code_hits "$T/dyn.sh")" ] || fail "掃描器抓不到拼出來的 /\$stage"
[ -z "$(code_hits "$T/ok.sh")" ] || fail "掃描器誤報帶前綴或註解: $(code_hits "$T/ok.sh")"
[ -n "$(md_hits "$T/bare.md")" ] || fail "掃描器抓不到反引號裡的 /review"
[ -z "$(md_hits "$T/ok.md")" ] || fail "掃描器誤報帶前綴或標題: $(md_hits "$T/ok.md")"

# --- 真實檔案 ---
bad=""
for f in bin/lib/drive.sh bin/lib/dispatch.sh bin/lib/merge.sh bin/lib/next.sh bin/lib/chain.sh \
         hooks/openspec-router.sh hooks/openspec-stop-gate.sh hooks/openspec-commit-gate.sh; do
  h="$(code_hits "$OPSX_ROOT/$f")"; [ -z "$h" ] || bad+="$f:
$h
"
done
for f in references/continue.md references/fan-out.md skills/*/SKILL.md; do
  h="$(md_hits "$OPSX_ROOT/$f")"; [ -z "$h" ] || bad+="$f:
$h
"
done
[ -z "$bad" ] || fail "要執行的位置還有裸的節點短名，改成 /opsx-workflow:<stage>：
$bad"
