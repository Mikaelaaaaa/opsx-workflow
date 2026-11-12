#!/usr/bin/env bash
# workplan 三層依賴、slug 查 branch 與合併狀態、已拆大卡的 split 階段。
# 驗收：openspec/changes/split-plan/specs/workplan-deps/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
H="$OPSX_ROOT/hooks"; export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI)"; mkdir -p "$R/openspec/changes"
cat > "$R/openspec/workplan.yaml" <<'EOF'
created: 2026-11-10

features:
  - name: a
    status: active
    prs:
      - name: p1
        branch: feat/p1/mikaela   # 註解
        status: merged
        depends-on: []
        changes:
          - name: c1
            status: pending
          - name: c2
            status: pending
            depends-on: [c1]
      - name: p2
        branch: feat/p2/mikaela
        status: pending
        depends-on: [p1]
        changes:
          - name: c3
            status: done

  - name: b
    status: active
    depends-on: [p1]
    prs:
      - name: c4
        branch: feat/c4/mikaela
        status: pending
        changes:
          - name: c4
            status: pending
EOF

# --- Scenario：feature depends-on 讀得到（缺欄位就沒有這個 key，讀的人當空清單） ---
python3 -I - "$OPSX_ROOT/bin/lib" "$R/openspec/workplan.yaml" <<'PY' || fail "load_workplan 三層 depends-on"
import sys; sys.path.insert(0, sys.argv[1]); import chain
f = chain.load_workplan(sys.argv[2])["features"]
assert f[1]["depends-on"] == ["p1"], f[1]
assert (f[0].get("depends-on") or []) == [], f[0]
ch = f[0]["prs"][0]["changes"]
assert ch[1]["depends-on"] == ["c1"], ch
assert (ch[0].get("depends-on") or []) == [], ch
PY

# --- Scenario：序列與父 key 同縮排（PyYAML sort_keys=False 的輸出）讀得到，且與多縮排讀出相同結構 ---
cat > "$FX/flat.yaml" <<'EOF'
created: 2026-11-10
description:
features:
- name: a
  status: active
  description: 折行的純量
    第二行 含冒號: 照樣接上
  prs:
  - name: p1
    branch: feat/p1/mikaela
    status: merged
    depends-on: []
    changes:
    - name: c1
      status: pending
    - name: c2
      status: pending
      depends-on:
      - c1
  - name: p2
    branch: feat/p2/mikaela
    status: pending
    depends-on:
    - p1
- name: b
  status: active
  depends-on:
  - p1
  prs:
  - name: c4
    branch: feat/c4/mikaela
    status: pending
EOF
cat > "$FX/deep.yaml" <<'EOF'
created: 2026-11-10
description:
features:
  - name: a
    status: active
    description: 折行的純量
      第二行 含冒號: 照樣接上
    prs:
      - name: p1
        branch: feat/p1/mikaela
        status: merged
        depends-on: []
        changes:
          - name: c1
            status: pending
          - name: c2
            status: pending
            depends-on:
              - c1
      - name: p2
        branch: feat/p2/mikaela
        status: pending
        depends-on:
          - p1
  - name: b
    status: active
    depends-on:
      - p1
    prs:
      - name: c4
        branch: feat/c4/mikaela
        status: pending
EOF
python3 -I - "$OPSX_ROOT/bin/lib" "$FX/flat.yaml" "$FX/deep.yaml" <<'PY' || fail "load_workplan 序列與父 key 同縮排"
import sys; sys.path.insert(0, sys.argv[1]); import chain
flat, deep = chain.load_workplan(sys.argv[2]), chain.load_workplan(sys.argv[3])
assert len(flat["features"]) == 2, flat
assert flat["features"][0]["prs"][0]["changes"][1]["depends-on"] == ["c1"], flat
assert flat["features"][0]["prs"][1]["depends-on"] == ["p1"], flat
assert flat["features"][0]["prs"][0]["depends-on"] == [], flat
assert flat["features"][1]["depends-on"] == ["p1"], flat
assert flat["description"] is None and flat["created"] == "2026-11-10", flat
assert flat["features"][0]["description"] == "折行的純量 第二行 含冒號: 照樣接上", flat
assert flat["features"][0]["prs"][0]["name"] == "p1", flat
assert flat == deep, (flat, deep)
PY

bash_fn() { ( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; source "$OPSX_ROOT/bin/lib/dispatch.sh"; "$@" ); }

# --- Scenario：PR 名查到 PR 的 branch；子 change 名查到所屬 PR 的 branch ---
assert_eq "$(bash_fn workplan_branch "$R" p1)" "feat/p1/mikaela" "PR 名（行尾註解不算 branch）"
assert_eq "$(bash_fn workplan_branch "$R" c2)" "feat/p1/mikaela" "子 change 名回所屬 PR 的 branch"
assert_eq "$(bash_fn workplan_branch "$R" c3)" "feat/p2/mikaela" "第二個 PR 底下的 change"
assert_eq "$(bash_fn workplan_branch "$R" c4)" "feat/c4/mikaela" "PR 名與 change 名相同"
assert_eq "$(bash_fn workplan_branch "$R" a)" "" "feature 名不是卡"
assert_eq "$(bash_fn workplan_branch "$R" nope)" "" "找不到印空"

# --- Scenario：子 change 的合併狀態看所屬 PR ---
for s in p1 c1 c2; do bash_fn st_workplan_merged "$R" "$s" || fail "$s 所屬 PR p1 merged，要判已合併"; done
for s in p2 c3 c4 nope; do ! bash_fn st_workplan_merged "$R" "$s" || fail "$s 所屬 PR 沒 merged，不能判已合併（c3 自己是 done 也一樣）"; done
mkdir -p "$R/openspec/changes/c1"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/c1/.openspec.yaml"
assert_eq "$(bash_fn stage_name "$R" c1)" archive "所屬 PR merged 的子 change → archive"

# --- PR 的 branch / status 寫在 changes 區塊後面也讀得到 ---
R3="$(mk_repo late)"; mkdir -p "$R3/openspec"
printf 'features:\n  - name: f\n    prs:\n      - name: p9\n        changes:\n          - name: c9\n            status: pending\n        branch: feat/p9/mikaela\n        status: merged\n' > "$R3/openspec/workplan.yaml"
assert_eq "$(bash_fn workplan_branch "$R3" c9)" "feat/p9/mikaela" "changes 之後的 branch"
bash_fn st_workplan_merged "$R3" c9 || fail "changes 之後的 status: merged 要讀到"

# --- Scenario：舊格式照讀（只有 PR 層） ---
R2="$(mk_repo old)"; mkdir -p "$R2/openspec"
printf 'features:\n  - name: eval\n    prs:\n      - name: eval-core\n        branch: feat/eval-core-v2/mikaela\n        status: merged\n        changes:\n          - name: eval-core\n            status: pending\n' > "$R2/openspec/workplan.yaml"
assert_eq "$(bash_fn workplan_branch "$R2" eval-core)" "feat/eval-core-v2/mikaela" "舊格式 branch"
bash_fn st_workplan_merged "$R2" eval-core || fail "舊格式 merged"
rm "$R2/openspec/workplan.yaml"
assert_eq "$(bash_fn workplan_branch "$R2" eval-core)" "" "沒有 workplan 印空"
! bash_fn st_workplan_merged "$R2" eval-core || fail "沒有 workplan 不是 merged"

# --- Scenario：split_into 的卡回 split ---
S="$R/openspec/changes/big"; mkdir -p "$S"; git -C "$R" checkout -q -b feat/big/mikaela
printf 'schema: opsx\nkind: dev\n' > "$S/.openspec.yaml"
printf -- '---\ntype: 功能\nsplit_into: p1, p2\n---\n\n## 一句話\n\n大卡\n' > "$S/inbox.md"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$S/explore.md"
assert_eq "$(bash_fn stage_name "$R" big)" split "有 explore.md、沒 tasks.md，但已拆 → split 不是 propose"
printf -- '---\ntype: 功能\nsplit_into:\n---\n' > "$FX/empty-inbox.md"; cp "$FX/empty-inbox.md" "$S/inbox.md"
assert_eq "$(bash_fn stage_name "$R" big)" propose "split_into 空的不算已拆"
printf -- '---\ntype: 功能\n---\n\nsplit_into: p1\n' > "$S/inbox.md"
assert_eq "$(bash_fn stage_name "$R" big)" propose "frontmatter 外的 split_into 不算"
printf -- '---\ntype: 功能\nsplit_into: p1, p2\n---\n' > "$S/inbox.md"

# --- Scenario：router 不推已拆的卡 ---
j() { python3 -I -c 'import json,sys;print(json.dumps(dict(cwd=sys.argv[1],prompt="繼續",hook_event_name="UserPromptSubmit")))' "$1"; }
out="$(j "$R" | bash "$H/openspec-router.sh" 2>/dev/null)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')"
printf '%s' "$ctx" | grep -q '^opsx：split · big' || fail "router 要說 split: $ctx"
! printf '%s' "$ctx" | grep -q 'SKILL.md' || fail "router 對 split 不注入 skill: $ctx"

# --- 看板：split 歸已完成 ---
ROOT="$FX/code"; mkdir -p "$ROOT/r/.git"; cp -R "$R/openspec" "$ROOT/r/openspec"
J="$(opsx collect --root "$ROOT")" || fail "collect"
sec="$(printf '%s' "$J" | python3 -I -c 'import json,sys;print([c["section"] for c in json.load(sys.stdin)["cards"] if c["slug"]=="big"][0])')"
assert_eq "$sec" 已完成 "split 的卡在看板歸已完成"

echo ok
