#!/usr/bin/env bash
# apply / review evals fixture 的 change spec 用 Gherkin 寫法，且 fixture 內引用自洽。
# 驗收：openspec/changes/propose-gherkin/subs/fixture-specs-gherkin/specs/eval-fixture-specs/spec.md 的每個 Scenario
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PRICE="$OPSX_ROOT/skills/apply/evals/fixtures/price-cents-padding"
RETRY="$OPSX_ROOT/skills/review/evals/fixtures/retry-backoff"

# 印出 fixture change 的每個問題，有問題就回非 0
fixture_check() { # <repo> <change>
  local c="$1/openspec/changes/$2" bad=0 out n
  out="$(cd "$1" && openspec validate "$2" --strict 2>&1)" || { echo "validate $2 失敗：$out"; bad=1; }
  awk '
    function done_req() {
      if (req == "") return
      if (!pos) { print "Requirement 沒有正例：" req; bad = 1 }
      if (!neg) { print "Requirement 沒有反例：" req; bad = 1 }
    }
    FNR == 1 { done_req(); req = "" }
    /^### Requirement: / { done_req(); req = substr($0, 18); pos = 0; neg = 0; next }
    /^#### Scenario: / {
      name = substr($0, 16)
      if (name !~ /（(正例|反例|Scenario Outline，(正例|反例|正例＋反例))）$/) { print "Scenario 沒標正反例：" name; bad = 1 }
      if (name ~ /正例）$/ || name ~ /正例＋反例）$/) pos = 1
      if (name ~ /反例）$/) neg = 1
    }
    END { done_req(); exit bad }' "$c"/specs/*/spec.md || bad=1
  sed -n 's/^#### Scenario: //p' "$c"/specs/*/spec.md > "$FX/titles"
  grep -ho '「[^」]*」' "$c/tasks.md" "$c/proposal.md" | sed 's/^「//; s/」$//' > "$FX/refs"
  [ -s "$FX/refs" ] || { echo "tasks.md / proposal.md 沒有引用任何 Scenario 名"; bad=1; }
  while IFS= read -r n; do
    grep -qxF -- "$n" "$FX/titles" || { echo "引用的 Scenario 不在 spec 標題裡：$n"; bad=1; }
  done < "$FX/refs"
  return $bad
}

# Examples 表每一列的第一欄（跳過 Examples: 之後的表頭與分隔列）
examples_first_col() { # <spec>
  awk '/^Examples:/{on=1; r=0; next} on && /^\|/{r++; if (r > 2) { split($0, f, "|"); gsub(/ /, "", f[2]); print f[2] } next} {on=0}' "$1"
}

# --- Scenario：fixture spec 合格（Scenario Outline，正例）---
# --- Scenario：引用名全部對得到（正例）---
cp -R "$PRICE/repo" "$FX/price"
cp -R "$RETRY/repo" "$FX/retry"
out="$(fixture_check "$FX/price" price-cents-padding)" || fail "price-cents-padding fixture 不合格：
$out"
out="$(fixture_check "$FX/retry" retry-backoff)" || fail "retry-backoff fixture 不合格：
$out"

# --- Scenario：金額 fixture 的測資不變（正例）---
P_SPEC="$PRICE/repo/openspec/changes/price-cents-padding/specs/pricing/spec.md"
grep -q '^Examples:' "$P_SPEC" || fail "price-cents-padding spec 沒有 Examples 表"
assert_eq "$(examples_first_col "$P_SPEC" | sort | tr '\n' ' ')" "0 1005 " "price-cents-padding 的 Examples 金額只能是 1005 與 0"
grep -q '^#### Scenario: .*（反例）$' "$P_SPEC" || fail "price-cents-padding 少反例"
grep -qF '$10.5' "$P_SPEC" || fail "price-cents-padding 的反例要寫 1005 分不顯示 \$10.5"

# --- Scenario：重試 fixture 的預埋缺陷不變（反例）---
grep -qF 'D2 只對 503 與網路錯誤重試，4xx 一律不重試' "$RETRY/repo/openspec/changes/retry-backoff/design.md" || fail "retry-backoff design.md 的 D2 被改了"
bash "$RETRY/setup.sh" "$FX/rb" || fail "retry-backoff setup.sh 失敗"
calls="$(cd "$FX/rb" && node --experimental-strip-types --no-warnings --input-type=module -e '
import { getJson } from "./src/client.ts";
let n = 0;
const fetchImpl = async () => { n++; return new Response("{}", { status: 404 }); };
await getJson("http://upstream/x", { retries: 2, fetchImpl, sleep: async () => {} }).catch(() => {});
console.log(n);' 2>&1)"
assert_eq "$calls" 3 "retry-backoff 的 getJson 對 404 要照樣重試（預埋的 D2 缺陷），呼叫次數"

# --- Scenario：Scenario 沒標正反例（反例）---
cp -R "$PRICE/repo" "$FX/bad-label"
S="$FX/bad-label/openspec/changes/price-cents-padding/specs/pricing/spec.md"
first="$(sed -n 's/^#### Scenario: //p' "$S" | head -1)"
bare="${first%（*}"
python3 -I -c 'import sys; p,a,b=sys.argv[1:]; t=open(p).read(); open(p,"w").write(t.replace("#### Scenario: "+a+"\n","#### Scenario: "+b+"\n",1))' "$S" "$first" "$bare"
grep -qx "#### Scenario: $bare" "$S" || fail "反例副本沒改到標題：$bare"
out="$(fixture_check "$FX/bad-label" price-cents-padding)" && fail "拿掉正反例標記的 spec 檢查卻通過"
case "$out" in *"Scenario 沒標正反例：$bare"*) ;; *) fail "檢查沒印出沒標記的 Scenario 名 '$bare'：$out" ;; esac

# --- Scenario：改名後留著舊名（反例）---
cp -R "$RETRY/repo" "$FX/bad-ref"
printf '\n- [ ] 9.1 舊名引用\n  - 驗收：specs/upstream-retry/spec.md「4xx 不重試」\n' >> "$FX/bad-ref/openspec/changes/retry-backoff/tasks.md"
out="$(fixture_check "$FX/bad-ref" retry-backoff)" && fail "留著舊名的 tasks.md 檢查卻通過"
case "$out" in *"引用的 Scenario 不在 spec 標題裡：4xx 不重試"*) ;; *) fail "檢查沒印出舊名 '4xx 不重試'：$out" ;; esac
echo ok
