#!/usr/bin/env bash
# 情境題組：skills/*/evals/fixtures/*/setup.sh 每支都建得出乾淨的 git repo，分支名合規，路徑與 change slug 不洩題。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

banned='eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena'
# 題目 repo 自己的單元測試檔可以帶 test
own_tests='(\.test\.|_test\.|(^|/)tests?/)'

# npm test 要真的跑到測試：Node 沒剝 TS 型別時 node --test 找到 0 個也是 rc 0
green_tests() { # green_tests <repo> <label>
  (cd "$1" && npm test --silent >"$FX/$2-test.log" 2>&1) || fail "$2 repo tests not green: $(cat "$FX/$2-test.log")"
  [ "$(sed -n 's/^# tests \([0-9]*\)$/\1/p' "$FX/$2-test.log")" -ge 1 ] 2>/dev/null || fail "$2 repo ran no tests: $(cat "$FX/$2-test.log")"
}
assertion_has() { # assertion_has <evals.json> <text>：只看 assertions 陣列，不看 prompt / expected_output
  python3 -I -c 'import json,sys; sys.exit(0 if any(sys.argv[2] in a for e in json.load(open(sys.argv[1]))["evals"] for a in e["assertions"]) else 1)' "$1" "$2" \
    || fail "no assertion in $1 contains: $2"
}

n=0
for s in "$OPSX_ROOT"/skills/*/evals/fixtures/*/setup.sh; do
  [ -f "$s" ] || continue
  fx="$(dirname "$s")"
  name="$(basename "$(dirname "$(dirname "$(dirname "$fx")")")")-$(basename "$fx")"
  d="$FX/built/$name"
  bash "$s" "$d" >"$FX/$name.log" 2>&1 || fail "setup.sh failed for $name: $(cat "$FX/$name.log")"
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || fail "$name is not a git repo"
  assert_eq "$(git -C "$d" status --short)" "" "$name working tree not clean"
  branch="$(git -C "$d" branch --show-current)"
  echo "$branch" | grep -Eq '^(feat|fix|chore|refactor|docs|sec)/[a-z0-9-]+/[a-z0-9_-]+$' \
    || fail "$name branch [$branch] does not match {action}/<slug>/<user>"
  leaks="$( { git -C "$d" ls-files; ls "$d/openspec/changes" 2>/dev/null; } | grep -Ev "$own_tests" | grep -Ei "$banned" || true)"
  [ -z "$leaks" ] || fail "$name leaks a banned word in: $leaks"
  # 卡寫 schema: opsx，repo 就要帶 schema，不然 candidate 會跑出 repo 外找模板
  [ ! -d "$d/openspec/changes" ] || assert_file "$d/openspec/schemas/opsx/schema.yaml"
  n=$((n+1))
done
[ "$n" -ge 2 ] || fail "expected at least 2 fixtures, found $n"

# 情境 2：小 fix，卡上只有 inbox.md，沒有要問人的題；repo 自己的測試建置後是綠的
d="$FX/built/explore-slug-trailing-dash"
[ -d "$d" ] || fail "scenario 2 fixture explore/slug-trailing-dash missing"
c="$d/openspec/changes/slug-trailing-dash"
assert_file "$c/inbox.md"
assert_no_file "$c/explore.md"
assert_no_file "$c/grill.md"
green_tests "$d" s2

# 情境 1 grill 段：至少三個原始檔，待決恰好三題，有 answers.md 代替人回答
d="$FX/built/grill-retry-backoff"
assert_eq "$(sed -n '/^## 待決/,/^## /p' "$d/openspec/changes/retry-backoff/explore.md" | grep -c '^- ')" "3" "grill segment needs exactly three 待決 items"
[ "$(git -C "$d" ls-files 'src/*' | wc -l | tr -d ' ')" -ge 3 ] || fail "grill segment needs at least three source files"
assert_file "$d/answers.md"

# 情境 1 propose 段：寫好的 grill.md 至少 D1、D2，各帶 理由、否決；explore 待決為空
d="$FX/built/propose-retry-backoff"
[ -d "$d" ] || fail "propose segment fixture propose/retry-backoff missing"
g="$d/openspec/changes/retry-backoff/grill.md"
assert_file "$g"
for id in D1 D2; do assert_grep "^- $id " "$g"; done
assert_eq "$(grep -c '理由：' "$g")" "$(grep -c '^- D[0-9]' "$g")" "every D needs a 理由 line"
assert_eq "$(grep -c '否決：' "$g")" "$(grep -c '^- D[0-9]' "$g")" "every D needs a 否決 line"
assert_eq "$(sed -n '/^## 待決/,/^## /p' "$d/openspec/changes/retry-backoff/explore.md" | grep -c '^- ')" "0" "propose segment 待決 must be empty"

# 情境 1 review 段：分支多一個 commit（違反恰好一條 D），tasks 全勾，測試綠；evals.json 指名被違反的 D
d="$FX/built/review-retry-backoff"
[ -d "$d" ] || fail "review segment fixture review/retry-backoff missing"
c="$d/openspec/changes/retry-backoff"
for f in proposal.md design.md tasks.md; do assert_file "$c/$f"; done
assert_eq "$(git -C "$d" rev-list --count main..HEAD)" "1" "review segment branch needs exactly one commit beyond main"
assert_eq "$(grep -c -- '- \[ \]' "$c/tasks.md")" "0" "review segment tasks must all be checked"
green_tests "$d" s1r
assert_eq "$(cd "$d" && node --input-type=module -e '
const { getJson } = await import("./src/client.ts");
let n = 0;
await getJson("http://u/x", { fetchImpl: async () => { n++; return new Response("{}", { status: 404 }); }, sleep: async () => {} }).catch(() => {});
console.log(n);' 2>/dev/null)" "6" "review segment commit must violate D2: a 404 is retried 5 times"
assertion_has "$OPSX_ROOT/skills/review/evals/evals.json" "violates D2"
# 走完 apply 的卡會有 status.json tests=green，少了它新版 review 開工前就擋下，題目測不到 D-id
assert_file "$c/status.json"
assert_grep '"tests": "green"' "$c/status.json"

# 情境 1 三段的 sync job：單次 request timeout 不能等於整頁 60 秒預算，否則題目自己的風險估算是錯的
for s in grill propose review; do
  assert_not_grep "timeoutMs: PAGE_BUDGET_MS" "$FX/built/$s-retry-backoff/src/sync.ts"
done

# 情境 3：bug-fix 卡已 propose 好；現有測試全綠，但 inbox.md 寫的輸入會重現錯誤
d="$FX/built/apply-price-cents-padding"
[ -d "$d" ] || fail "scenario 3 fixture apply/price-cents-padding missing"
c="$d/openspec/changes/price-cents-padding"
for f in inbox.md proposal.md design.md tasks.md; do assert_file "$c/$f"; done
assert_grep "kind: bug-fix" "$c/.openspec.yaml"
assert_file "$d/openspec/schemas/opsx/schema.yaml"
green_tests "$d" s3
assert_eq "$(cd "$d" && node -e 'import("./src/money.mjs").then(m=>console.log(m.formatPrice(1005)))')" '$10.5' "bug must reproduce"
assertion_has "$OPSX_ROOT/skills/apply/evals/evals.json" "git rev-list --count main..HEAD prints 1"

# 兩組工作 repo：同一題、新舊兩版 skill，.claude/ 以外逐檔相同
mkdir -p "$FX/old/skills/explore" "$FX/old/grill-me"
echo "old explore" > "$FX/old/skills/explore/SKILL.md"
echo "old grill-me" > "$FX/old/grill-me/SKILL.md"
export OPSX_OLD_SKILLS="$FX/old/skills" OPSX_OLD_GRILL="$FX/old/grill-me"
a="$FX/run/a"; b="$FX/run/b"
bash "$OPSX_ROOT/evals/prepare-run.sh" explore slug-trailing-dash new "$a" >/dev/null 2>&1 || fail "prepare-run new failed"
bash "$OPSX_ROOT/evals/prepare-run.sh" explore slug-trailing-dash old "$b" >/dev/null 2>&1 || fail "prepare-run old failed"
diff -r -x .claude -x .git "$a" "$b" >/dev/null || fail "variants differ outside .claude/"
assert_file "$a/.claude/skills/explore/SKILL.md"
assert_file "$a/.claude/references/writing-the-reply.md"
assert_grep "old explore" "$b/.claude/skills/explore/SKILL.md"
assert_file "$b/.claude/skills/grill-me/SKILL.md"
assert_eq "$(find "$a/.claude" "$b/.claude" -name evals)" "" "skill copies must not carry evals/ fixtures"
assert_eq "$(git -C "$a" status --short)" "" "new variant repo not clean"
assert_eq "$(git -C "$b" status --short)" "" "old variant repo not clean"

# 成績表：五題各一列（新、舊、差值都是數字），有逐情境結論與這輪開的卡
r="$OPSX_ROOT/docs/verify-scenarios.md"
assert_file "$r"
for e in small-fix-skips-grill bug-fix-reproduce-first three-bucket-pending decisions-carried-verbatim finding-cites-violated-decision; do
  grep -E "^\| *$e *\|" "$r" | grep -Eq '\| *[0-9]+% *\| *[0-9]+% *\| *[+-]?[0-9]+ *\| *[0-9]+ / [0-9]+ *\|' || fail "results row for $e missing or lacks pass rates, delta, runs per group"
done
assert_grep "^## 結論" "$r"
assert_grep "^## 開的卡" "$r"
assert_not_grep "TBD" "$r"

echo "ok: $n fixtures"
