#!/usr/bin/env bash
# 六個 skill 的 workplan health check：依主機查 glab / gh、帶 merged 旗標、不認得的主機略過。只證明文字寫了；agent 守不守由 eval 驗。
# 驗收：openspec/changes/forge-health-check/specs/workplan-health-check/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
has() { grep -qF -- "$1" "$2" || fail "'$1' not in $2"; }

for name in explore propose archive status sync apply; do
  SK="$OPSX_ROOT/skills/$name/SKILL.md"
  assert_file "$SK"
  has 'glab mr list --source-branch <branch> --merged' "$SK"
  has 'gh pr list --head <branch> --state merged' "$SK"
  has 'skip this check and say so' "$SK"
  assert_not_grep 'gh pr list --head <branch> --json state' "$SK"
done
echo ok
