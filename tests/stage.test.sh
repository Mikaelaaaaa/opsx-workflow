#!/usr/bin/env bash
# stage_of / stage_name 與它們的 helper 的 characterization test：期望值是 dc086e8 舊 code 跑出來的輸出，逐字比對。
# 驗收：openspec/changes/collect-background/subs/stage-fewer-forks/specs/board-collect/spec.md「stage 判斷結果不因效能改動而變」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bash_fn() { ( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; "$@" ); }
R="$(mk_repo stage)"
C="$R/openspec/changes"
card() { # card <slug> [kind]：kind 空就不寫 kind 行
  mkdir -p "$C/$1"
  if [ -n "${2:-}" ]; then printf 'schema: opsx\nkind: %s\n' "$2" > "$C/$1/.openspec.yaml"; else printf 'schema: opsx\n' > "$C/$1/.openspec.yaml"; fi
}
pending() { printf '## 已知\n- x\n\n## 待決\n- 要不要 A？\n\n## 不做\n' > "$C/$1/explore.md"; }
nopending() { printf '## 已知\n- x\n\n## 待決\n<!-- 無 -->\n- \n（沒有）\n\n## 不做\n- y\n' > "$C/$1/explore.md"; }
tasks_open() { printf '## 1\n- [x] 1.1 a\n- [ ] 1.2 b\n' > "$C/$1/tasks.md"; }
tasks_done() { printf '## 1\n- [x] 1.1 a\n  - [x] 1.2 b\n' > "$C/$1/tasks.md"; }
tests_is() { printf '{"phase":"apply","step":2,"total":2,"tests":"%s"}\n' "$2" > "$C/$1/status.json"; }

# 每種站點一張
mkdir -p "$C/only-inbox"; printf -- '---\nsource: me\n---\n想做 X\n' > "$C/only-inbox/inbox.md"
card ex-empty perf
card grill-dev dev; pending grill-dev
card grill-ops ops; pending grill-ops
card prop-empty dev; nopending prop-empty
card prop-chore chore; pending prop-chore
card prop-bugfix bug-fix; pending prop-bugfix
card prop-grilled dev; pending prop-grilled; printf '# grill\n' > "$C/prop-grilled/grill.md"
card apply-open dev; tasks_open apply-open
card apply-red refactoring; tasks_done apply-red; tests_is apply-red red
card apply-nostatus dev; tasks_done apply-nostatus
card review-green perf; tasks_done review-green; tests_is review-green green
card pr-ready dev; tasks_done pr-ready; printf '# report\n沒有 MR\n' > "$C/pr-ready/report.md"
card pr-notasks dev; printf '# report\n' > "$C/pr-notasks/report.md"
card apply-back dev; tasks_open apply-back; printf '# report\n' > "$C/apply-back/report.md"
card babysit-gl dev; tasks_open babysit-gl; printf '# report\n\nMR: https://gitlab.example.com/g/p/-/merge_requests/42 (draft)\n' > "$C/babysit-gl/report.md"
card babysit-gh chore; printf 'see (https://github.com/o/r/pull/7) and https://github.com/o/r/pull/8\nhttps://github.com/o/r/pull/9\n' > "$C/babysit-gh/report.md"
card archive-pr dev; tasks_open archive-pr
card archive-child dev
card notmerged dev; tasks_open notmerged
card split-list dev; printf -- '---\nsource: me\nsplit_into: [a, b] # 拆好了\n---\n' > "$C/split-list/inbox.md"; tasks_open split-list
card split-plain ops; printf -- '---\nsplit_into: a b  \n---\n' > "$C/split-plain/inbox.md"
cat > "$R/openspec/workplan.yaml" <<'EOF'
features:
  - name: f
    prs:
      - name: archive-pr
        branch: feat/archive-pr/mikaela
        status: merged   # 已合
        depends-on: []
        changes:
          - name: archive-child
            status: done
      - name: notmerged
        branch: feat/notmerged/mikaela
        status: in-progress
        changes:
          - name: x
EOF

# kind 讀不到時用 dev；kind 照原樣（含尾端空白、第一個 kind 行、CRLF 的 \r）
mkdir -p "$C/no-yaml"
card no-kind
card kind-trailing; printf 'schema: opsx\nkind:   perf  \nkind: dev\n' > "$C/kind-trailing/.openspec.yaml"
card kind-noeol; printf 'schema: opsx\nkind: chore' > "$C/kind-noeol/.openspec.yaml"
card kind-indented; printf 'schema: opsx\n  kind: chore\n' > "$C/kind-indented/.openspec.yaml"
card kind-crlf; printf 'schema: opsx\r\nkind: ops\r\n' > "$C/kind-crlf/.openspec.yaml"

# split_into 為空的各種寫法不算已拆；frontmatter 外、沒有 frontmatter 的 split_into 不算
n=0
for v in '[]' '[ ]' '""' "''" '~' 'null' '' '[] # 沒拆'; do
  n=$((n+1)); card "split-empty-$n" dev; tasks_open "split-empty-$n"
  printf -- '---\nsplit_into: %s\n---\n' "$v" > "$C/split-empty-$n/inbox.md"
done
card split-after-fm dev; printf -- '---\nsource: me\n---\nsplit_into: [a]\n' > "$C/split-after-fm/inbox.md"
card split-no-fm dev; printf -- 'split_into: [a]\n---\n' > "$C/split-no-fm/inbox.md"
card split-crlf dev; printf -- '---\r\nsource: me\r\nsplit_into: [a, b]\r\n---\r\n' > "$C/split-crlf/inbox.md"
card split-crlf-empty dev; tasks_open split-crlf-empty; printf -- '---\r\nsplit_into: []\r\n---\r\n' > "$C/split-crlf-empty/inbox.md"
card split-noeol dev; printf -- '---\nsplit_into: [z]' > "$C/split-noeol/inbox.md"
card split-hash dev; printf -- '---\nsplit_into: a#b # c # d\n---\n' > "$C/split-hash/inbox.md"
card split-onlyhash dev; printf -- '---\nsplit_into: # 沒填\n---\n' > "$C/split-onlyhash/inbox.md"
card split-twice dev; printf -- '---\nsplit_into: []\nsplit_into: [b]\n---\n' > "$C/split-twice/inbox.md"

# 期望值：dc086e8 的 stage_of 輸出。stage_name 是第一個欄位
n=0
while IFS='|' read -r slug want; do
  n=$((n+1))
  assert_eq "$(bash_fn stage_of "$R" "$slug")" "$want" "stage_of [$slug]"
  assert_eq "$(bash_fn stage_name "$R" "$slug")" "${want%% *}" "stage_name [$slug]"
done <<'TABLE'
|explore · （沒有對到卡，先建殼）· — · skills/explore/SKILL.md
nope|explore · （沒有對到卡，先建殼）· — · skills/explore/SKILL.md
only-inbox|explore · only-inbox · dev · skills/explore/SKILL.md
ex-empty|explore · ex-empty · perf · skills/explore/SKILL.md
grill-dev|grill · grill-dev · dev · skills/grill/SKILL.md
grill-ops|grill · grill-ops · ops · skills/grill/SKILL.md
prop-empty|propose · prop-empty · dev · skills/propose/SKILL.md
prop-chore|propose · prop-chore · chore · skills/propose/SKILL.md
prop-bugfix|propose · prop-bugfix · bug-fix · skills/propose/SKILL.md
prop-grilled|propose · prop-grilled · dev · skills/propose/SKILL.md
apply-open|apply · apply-open · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
apply-red|apply · apply-red · refactoring · skills/apply/SKILL.md · skills/apply/references/playbooks/refactoring.md · skills/tdd/SKILL.md（tasks 全勾但 tests 不是 green：先把測試補到綠）
apply-nostatus|apply · apply-nostatus · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md（tasks 全勾但 tests 不是 green：先把測試補到綠）
review-green|review · review-green · perf · skills/review/SKILL.md · skills/review/references/ponytail-review.md
pr-ready|pr · pr-ready · dev · skills/pr/SKILL.md · skills/pr/references/mr-note.md
pr-notasks|pr · pr-notasks · dev · skills/pr/SKILL.md · skills/pr/references/mr-note.md
apply-back|apply · apply-back · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md（review 退回了 task，先做完）
babysit-gl|babysit · babysit-gl · dev · skills/babysit/SKILL.md（MR 已開，等合併；有留言用 babysit）
babysit-gh|babysit · babysit-gh · chore · skills/babysit/SKILL.md（MR 已開，等合併；有留言用 babysit）
archive-pr|archive · archive-pr · dev · skills/archive/SKILL.md
archive-child|archive · archive-child · dev · skills/archive/SKILL.md
notmerged|apply · notmerged · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-list|split · split-list · dev · 已拆成 [a, b]，這張不再往下做
split-plain|split · split-plain · ops · 已拆成 a b  ，這張不再往下做
no-yaml|explore · no-yaml · dev · skills/explore/SKILL.md
no-kind|explore · no-kind · dev · skills/explore/SKILL.md
kind-trailing|explore · kind-trailing · perf   · skills/explore/SKILL.md
kind-noeol|explore · kind-noeol · chore · skills/explore/SKILL.md
kind-indented|explore · kind-indented · dev · skills/explore/SKILL.md
split-empty-1|apply · split-empty-1 · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-empty-2|apply · split-empty-2 · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-empty-3|apply · split-empty-3 · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-empty-4|apply · split-empty-4 · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-empty-5|apply · split-empty-5 · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-empty-6|apply · split-empty-6 · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-empty-7|apply · split-empty-7 · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-empty-8|apply · split-empty-8 · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-after-fm|explore · split-after-fm · dev · skills/explore/SKILL.md
split-no-fm|explore · split-no-fm · dev · skills/explore/SKILL.md
split-crlf|split · split-crlf · dev · 已拆成 [a, b]，這張不再往下做
split-crlf-empty|apply · split-crlf-empty · dev · skills/apply/SKILL.md · skills/apply/references/playbooks/dev.md · skills/tdd/SKILL.md
split-noeol|split · split-noeol · dev · 已拆成 [z]，這張不再往下做
split-hash|split · split-hash · dev · 已拆成 a#b，這張不再往下做
split-onlyhash|split · split-onlyhash · dev · 已拆成 # 沒填，這張不再往下做
split-twice|explore · split-twice · dev · skills/explore/SKILL.md
TABLE
# kind 欄位帶著 CRLF 的 \r，寫不進上面的表
assert_eq "$(bash_fn stage_of "$R" kind-crlf)" "$(printf 'explore · kind-crlf · ops\r · skills/explore/SKILL.md')" "stage_of [kind-crlf]"
assert_eq "$(bash_fn stage_name "$R" kind-crlf)" explore "stage_name [kind-crlf]"
# 表裡除了空 slug 和 nope 都是 fixture 卡，加上 kind-crlf 要等於 fixture 卡數：加卡忘了加期望值會在這裡抓到
assert_eq "$(( n - 1 ))" "$(ls "$C" | wc -l | tr -d ' ')" "表的卡數 + kind-crlf = fixture 卡數"

# helper 的原始輸出（含結尾換行與否），dispatch、hooks、merge、mr 直接用它們
assert_bytes() { # assert_bytes <printf 格式的期望值> <cmd…>
  local want="$1"; shift
  printf "$want" > "$FX/want"; bash_fn "$@" > "$FX/got"
  cmp -s "$FX/want" "$FX/got" || fail "$* bytes: want [$(od -c "$FX/want")] got [$(od -c "$FX/got")]"
}
assert_bytes 'perf  \n' st_card_kind "$C/kind-trailing"
assert_bytes 'chore' st_card_kind "$C/kind-noeol"
assert_bytes 'ops\r\n' st_card_kind "$C/kind-crlf"
assert_bytes '' st_card_kind "$C/no-kind"
assert_bytes '' st_card_kind "$C/no-yaml"
assert_bytes 'https://gitlab.example.com/g/p/-/merge_requests/42\n' st_mr_url "$C/babysit-gl"
assert_bytes 'https://github.com/o/r/pull/7\n' st_mr_url "$C/babysit-gh"
assert_bytes '' st_mr_url "$C/pr-ready"
assert_bytes '' st_mr_url "$C/no-yaml"
M="$FX/mr"; mkdir -p "$M"
printf 'x https://h/merge_requests/1/pull/2 y\n' > "$M/report.md"
assert_bytes 'https://h/merge_requests/1/pull/2\n' st_mr_url "$M"
printf 'no\r\nhttp://a.b/c/pull/33\r\n' > "$M/report.md"
assert_bytes 'http://a.b/c/pull/33\n' st_mr_url "$M"
printf 'https://a/pull/x\nhttps://b/pull/4' > "$M/report.md"
assert_bytes 'https://b/pull/4\n' st_mr_url "$M"
# bin/opsx 是 set -e：helper 直接呼叫（不在 $() 或條件裡）也不能讓呼叫端結束
for f in st_mr_url st_card_kind st_split_into; do
  assert_eq "$(set -e; source "$OPSX_ROOT/bin/lib/stage.sh"; "$f" "$C/babysit-gl" >/dev/null; "$f" "$C/no-yaml" >/dev/null; echo after)" after "$f 在 set -e 下"
done
assert_bytes '[a, b]\n' st_split_into "$C/split-list"
assert_bytes '[a, b]\n' st_split_into "$C/split-crlf"
assert_bytes '[z]\n' st_split_into "$C/split-noeol"
assert_bytes '' st_split_into "$C/split-empty-8"
assert_bytes '' st_split_into "$C/no-yaml"
assert_bytes 'feat/archive-pr/mikaela\n' wp_pr_field "$R" archive-child branch
assert_bytes 'merged\n' wp_pr_field "$R" archive-pr status
assert_bytes 'in-progress\n' wp_pr_field "$R" x status
assert_bytes '' wp_pr_field "$R" nope branch
# 序列不縮排（PyYAML `sort_keys=False` 的輸出，`name` 是每個項目的第一個 key；`prs:` 與 `- name:` 同縮排，`changes:` 亦同）
FLAT="$FX/flat"; mkdir -p "$FLAT/openspec"
cat > "$FLAT/openspec/workplan.yaml" <<'EOF'
features:
- name: f
  prs:
  - name: p1
    branch: feat/p1/u
    status: merged
    depends-on: []
    changes:
    - name: c1
      status: done
      depends-on: []
  - name: p2
    branch: feat/p2/u
    status: pending
    depends-on:
    - p1
    changes:
    - name: c2
      status: pending
      depends-on: []
EOF
assert_bytes 'feat/p1/u\n' wp_pr_field "$FLAT" p1 branch
assert_bytes 'merged\n' wp_pr_field "$FLAT" c1 status
assert_bytes 'feat/p2/u\n' wp_pr_field "$FLAT" p2 branch
assert_bytes 'pending\n' wp_pr_field "$FLAT" c2 status
assert_bytes 'feat/p1/u\n' wp_pr_field "$FLAT" c1 branch
assert_bytes '' wp_pr_field "$FLAT" nope branch
# change 底下有更深的 `- name:` 清單，後面還有 change 與 PR；空 `changes: []`；第二個 feature（兩種縮排）
DEEP="$FX/deep"; mkdir -p "$DEEP/openspec"
cat > "$DEEP/openspec/workplan.yaml" <<'EOF'
features:
  - name: f
    prs:
      - name: p1
        branch: b1
        status: merged
        changes:
          - name: c1
            status: done
            steps:
              - name: s
          - name: c2
            status: done
      - name: p2
        branch: b2
        status: pending
        changes: []
      - name: p3
        branch: b3
        status: done
  - name: g
    prs:
      - name: p4
        branch: b4
        status: pending
EOF
assert_bytes 'b1\n' wp_pr_field "$DEEP" c2 branch
assert_bytes 'merged\n' wp_pr_field "$DEEP" c2 status
assert_bytes 'b2\n' wp_pr_field "$DEEP" p2 branch
assert_bytes 'done\n' wp_pr_field "$DEEP" p3 status
assert_bytes 'b4\n' wp_pr_field "$DEEP" p4 branch
DEEPF="$FX/deepflat"; mkdir -p "$DEEPF/openspec"
cat > "$DEEPF/openspec/workplan.yaml" <<'EOF'
features:
- name: f
  prs:
  - name: p1
    branch: b1
    status: merged
    changes:
    - name: c1
      status: done
      steps:
      - name: s
    - name: c2
      status: done
  - name: p2
    branch: b2
    status: pending
    changes: []
  - name: p3
    branch: b3
    status: done
- name: g
  prs:
  - name: p4
    branch: b4
    status: pending
EOF
assert_bytes 'b1\n' wp_pr_field "$DEEPF" c2 branch
assert_bytes 'merged\n' wp_pr_field "$DEEPF" c2 status
assert_bytes 'b2\n' wp_pr_field "$DEEPF" p2 branch
assert_bytes 'done\n' wp_pr_field "$DEEPF" p3 status
assert_bytes 'b4\n' wp_pr_field "$DEEPF" p4 branch
echo "ok stage"
