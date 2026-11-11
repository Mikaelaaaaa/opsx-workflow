#!/usr/bin/env bash
# skills/propose/evals/evals.json 的 spec 寫法題：四類判分齊全，候選者看得到的 prompt 與 files 不洩漏比較意圖。
# 驗收：openspec/changes/propose-gherkin/subs/propose-evals/specs/propose-gherkin-evals/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
EV="$OPSX_ROOT/skills/propose/evals/evals.json"
SPECS="$OPSX_ROOT/schemas/opsx/artifacts-specs.yaml"
assert_file "$EV"
assert_file "$SPECS"
case_field() { # case_field <prompt|files|assertions>：spec-gherkin-rules 那一題的欄位，assertions 與 files 一行一筆
  python3 -I -c '
import json, sys
es = [e for e in json.load(open(sys.argv[1]))["evals"] if e.get("name") == "spec-gherkin-rules"]
assert len(es) == 1, "expected one eval named spec-gherkin-rules, found %d" % len(es)
v = es[0][sys.argv[2]]
print("\n".join(v) if isinstance(v, list) else v)' "$EV" "$1"
}
case_field prompt > "$FX/prompt" || fail "no spec-gherkin-rules case in evals.json"
case_field files > "$FX/files" || fail "spec-gherkin-rules has no files"
case_field assertions > "$FX/assertions" || fail "spec-gherkin-rules has no assertions"
has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
hasnt() { ! grep -qiF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }

python3 -I -c '
import json, sys
ids = [e["id"] for e in json.load(open(sys.argv[1]))["evals"]]
assert len(ids) == len(set(ids)), ids' "$EV" || fail "eval ids in $EV are not unique"

# --- Scenario：eval case 帶齊四類判分（正例） ---
assert_eq "$(cat "$FX/files")" "fixtures/retry-backoff" "the case reuses the retry-backoff fixture"
assert_file "$OPSX_ROOT/skills/propose/evals/fixtures/retry-backoff/setup.sh"
grep '正例' "$FX/assertions" | grep -qF '反例' || fail "no assertion checks every Requirement has a 正例 and a 反例 Scenario"
grep -F 'Examples' "$FX/assertions" | grep -qF '30' || fail "no assertion checks the 30-second cap sits in an Examples table"
grep -F 'openspec validate' "$FX/assertions" | grep -qF -- '--strict' || fail "no assertion runs openspec validate --strict"
grep -F '禁用模糊詞' "$FX/assertions" > "$FX/vague" || fail "no assertion checks the 禁用模糊詞 list"
has 'openspec/schemas/opsx/schema.yaml' "$FX/vague"

# 模糊詞清單只有 specs instruction 一份：判分指向工作 repo 的 schema 快照，快照的那一行要與插件的相同，判分本身不抄清單
grep -F '禁用模糊詞：' "$SPECS" > "$FX/banned-line"
assert_eq "$(wc -l < "$FX/banned-line" | tr -d ' ')" "1" "specs instruction has one 禁用模糊詞 line"
grep -qxF -f "$FX/banned-line" "$OPSX_ROOT/skills/propose/evals/fixtures/retry-backoff/repo/openspec/schemas/opsx/schema.yaml" \
  || fail "fixture schema snapshot's 禁用模糊詞 line differs from schemas/opsx/artifacts-specs.yaml"
python3 -I -c '
import sys
words = open(sys.argv[1]).read().split("禁用模糊詞：", 1)[1].split("、")
print("\n".join(w.strip() for w in words if w.strip()))' "$FX/banned-line" > "$FX/words"
[ "$(wc -l < "$FX/words" | tr -d ' ')" -ge 5 ] || fail "could not parse the 禁用模糊詞 list: $(cat "$FX/banned-line")"
! grep -qF -f "$FX/words" "$FX/vague" || fail "the 禁用模糊詞 assertion copies words from the list instead of pointing at it"

# --- Scenario：候選者看得到的字不洩漏比較意圖（反例） ---
for w in eval compare benchmark baseline candidate judge experiment rubric score arena test; do
  hasnt "$w" "$FX/prompt"
  hasnt "$w" "$FX/files"
done
echo ok
