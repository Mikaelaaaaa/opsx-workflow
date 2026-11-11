#!/usr/bin/env bash
# logic-map 的 eval fixture 與 without 對照組：fixture 只有 base、head 兩個 commit、沒有 remote，樹跟原 commit 一致；
# evals.json 每題指到 fixture、範圍是 HEAD^...HEAD；prepare-run 的 without 少 logic-map、不認得的 variant 被拒。
# 對應 openspec/changes/logic-map-skill/subs/eval-fixtures/specs/logic-map「fixture 隔離」「eval 有沒 skill 的對照組」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
EV="$OPSX_ROOT/skills/logic-map/evals"
FIXTURES="$EV/fixtures"
assert_file "$FIXTURES/_lib.sh"

# --- evals.json：每題的 fixture、commit、範圍 ---
python3 -I -c '
import json, sys
for e in json.load(open(sys.argv[1]))["evals"]:
    print(e["id"], e["files"][0] if e["files"] else "-", e["prompt"].replace("\n", " "))' "$EV/evals.json" > "$FX/evals" || fail "evals.json 讀不了"
assert_eq "$(awk '{print $1, $2}' "$FX/evals")" "1 fixtures/stop-gate-subagent
2 fixtures/gate-title-slug
3 fixtures/coordinate-usage-limit"
assert_eq "$(grep -c 'HEAD^...HEAD' "$FX/evals")" 3 "每題的範圍都是 HEAD^...HEAD"
assert_not_grep '7b30eef\|24b2c40\|6312881\|8389924' "$FX/evals"
assert_not_grep '絕對路徑' "$FX/evals"

# 對照用：一個只做過 init 與兩次 commit 的 repo，.git 底下該有的東西
mkdir -p "$FX/plain"; git -C "$FX/plain" init -q -b x
echo a > "$FX/plain/a"; git -C "$FX/plain" add a
git -C "$FX/plain" -c user.name=a -c user.email=a@a commit -q -m a
git -C "$FX/plain" -c user.name=a -c user.email=a@a commit -q --allow-empty -m b

check_fixture() { # check_fixture <name> <commit>
  local name="$1" commit="$2" dest="$FX/fx-$1"
  assert_file "$FIXTURES/$name/setup.sh"
  bash "$FIXTURES/$name/setup.sh" "$dest" >/dev/null 2>&1 || fail "$name setup.sh 失敗"
  assert_eq "$(git -C "$dest" remote)" "" "$name 不該有 remote"
  assert_eq "$(git -C "$dest" log --format=%s)" "head
base" "$name 只有 head、base 兩個 commit"
  assert_eq "$(git -C "$dest" status --short)" "" "$name 工作樹要乾淨"
  git -C "$dest" diff HEAD^ HEAD > "$FX/$name.fixture.diff"
  git -C "$OPSX_ROOT" diff "$commit^" "$commit" > "$FX/$name.orig.diff"
  cmp -s "$FX/$name.fixture.diff" "$FX/$name.orig.diff" || fail "$name 的 head 對 base diff 要等於 $commit 的 diff"
  [ -s "$FX/$name.orig.diff" ] || fail "$name 的 diff 是空的"
  # 跟 tests/scenarios.test.sh 同一條規則：路徑含評測字眼的檔（題目自己的測試檔除外）不能留在題目 repo
  git -C "$dest" ls-files > "$FX/$name.files"
  ! grep -Ev '(\.test\.|_test\.|(^|/)tests?/)' "$FX/$name.files" | grep -Eiq 'eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena' || fail "$name 留著含評測字眼的路徑"
  git -C "$dest" ls-tree -r --name-only HEAD^ > "$FX/$name.base-files"
  ! grep -Ev '(\.test\.|_test\.|(^|/)tests?/)' "$FX/$name.base-files" | grep -Eiq 'eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena' || fail "$name 的 base 留著含評測字眼的路徑"
  assert_file "$dest/bin/opsx"
  # tests/ 底下描述評測工具的檔不算題目自己的測試；只有這個 commit 改到的測試檔留著
  assert_no_file "$dest/tests/run-candidate.test.sh"
  assert_no_file "$dest/tests/scenarios.test.sh"
  assert_no_file "$dest/tests/eval-playbook.test.sh"
  # 題目自己的測試要跑得起來：共用的 lib.sh 與 fakes 留著
  assert_file "$dest/tests/lib.sh"
  assert_dir "$dest/tests/fakes"
  # 被刪的檔不能留在 .git/objects：git fsck 挖得回來
  assert_eq "$(git -C "$dest" fsck --unreachable --no-reflogs 2>&1)" "" "$name 有 unreachable 物件"
  assert_eq "$(ls "$dest/.git")" "$(ls "$FX/plain/.git")" "$name 的 .git 不該多出檔案（例如刪掉的路徑清單）"
  assert_eq "$(git -C "$dest" rev-parse --abbrev-ref HEAD)" "fix/$name/dev" "$name 停在卡的分支上"
}
check_fixture stop-gate-subagent 8389924
check_fixture gate-title-slug 24b2c40
check_fixture coordinate-usage-limit 6312881

# --- eval 1 改成 #88：答案講 Stop 閘門與 stage.sh，不再是 commit 閘門 ---
python3 -I -c '
import json, sys
e = next(x for x in json.load(open(sys.argv[1]))["evals"] if x["id"] == 1)
print(e["eval_name"]); print(e["expected_output"]); print("\n".join(e["assertions"]))' "$EV/evals.json" > "$FX/eval1"
assert_grep 'openspec-stop-gate.sh' "$FX/eval1"
assert_grep 'bin/lib/stage.sh' "$FX/eval1"
assert_not_grep 'openspec-commit-gate.sh' "$FX/eval1"
assert_not_grep 'commit-gate' "$FX/eval1"

# --- without 少 logic-map（正例）---
new="$FX/v-new"; without="$FX/v-without"
bash "$OPSX_ROOT/evals/prepare-run.sh" logic-map gate-title-slug new "$new" >/dev/null 2>&1 || fail "prepare-run new 失敗"
bash "$OPSX_ROOT/evals/prepare-run.sh" logic-map gate-title-slug without "$without" >/dev/null 2>&1 || fail "prepare-run without 失敗"
assert_dir "$new/.claude/skills/logic-map"
assert_no_file "$without/.claude/skills/logic-map"
ls "$new/.claude/skills" | grep -vx logic-map > "$FX/new-skills"
ls "$without/.claude/skills" > "$FX/without-skills"
assert_eq "$(cat "$FX/without-skills")" "$(cat "$FX/new-skills")" "without 的其他 skill 要跟 new 一樣"
diff -r "$new/.claude/references" "$without/.claude/references" >/dev/null || fail "without 的 references 要跟 new 一樣"
assert_eq "$(git -C "$without" status --short)" "" "without 的工作 repo 要乾淨"
assert_no_file "$new/.claude/skills/logic-map/evals"

# --- 不認得的 variant 被拒（反例）---
bash "$OPSX_ROOT/evals/prepare-run.sh" logic-map gate-title-slug nope "$FX/v-nope" >/dev/null 2> "$FX/nope.err"
assert_eq "$?" 2 "nope 要退出 2"
assert_grep 'without' "$FX/nope.err"
assert_grep 'new' "$FX/nope.err"
assert_grep 'old' "$FX/nope.err"
