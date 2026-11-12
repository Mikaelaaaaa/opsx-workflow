#!/usr/bin/env bash
# 子殼 branch（<主>--<子>）的 stage_of 要對到 changes/<主>/subs/<子>/。
# 驗收：openspec/changes/me-20261111-1824/specs/stage-sub-shell/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bash_fn() { ( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; "$@" ); }
R="$(mk_repo stage-sub)"
C="$R/openspec/changes"
mkdir -p "$C/main/subs/child" "$C/solo"
printf 'schema: opsx\nkind: dev\n' > "$C/main/.openspec.yaml"
printf 'schema: opsx\nkind: dev\nparent: main\n' > "$C/main/subs/child/.openspec.yaml"
printf '## 1\n- [ ] 1.1 a\n' > "$C/main/subs/child/tasks.md"
printf 'schema: opsx\nkind: dev\n' > "$C/solo/.openspec.yaml"
printf '## 1\n- [ ] 1.1 a\n' > "$C/solo/tasks.md"

# 子殼 session 有 tasks.md
out="$(bash_fn stage_of "$R" main--child)"
case "$out" in "apply · main--child ·"*) ;; *) fail "子殼要印 apply：$out" ;; esac

# 子殼不存在
out="$(bash_fn stage_of "$R" main--ghost)"
case "$out" in *沒有對到卡*) ;; *) fail "子殼不存在要印沒有對到卡：$out" ;; esac

# 主殼不受影響
out="$(bash_fn stage_of "$R" solo)"
case "$out" in "apply · solo ·"*) ;; *) fail "主殼要印 apply：$out" ;; esac
echo "stage-sub-shell ok"
