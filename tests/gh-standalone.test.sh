#!/usr/bin/env bash
# pr / babysit skill 呼叫 gh 必須是單獨一個指令：串接的指令對不上沙盒的 excludedCommands「gh pr *」，
# 會留在沙盒裡、遇到 x509 OSStatus -26276。對應 init-sandbox-perms 的 specs/opsx-init「gh 要單獨呼叫」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for f in skills/pr/SKILL.md skills/babysit/SKILL.md; do
  assert_file "$OPSX_ROOT/$f"
  assert_grep "its own Bash command" "$OPSX_ROOT/$f"      # 規則本身寫在 skill 裡
  assert_grep "gh pr \*" "$OPSX_ROOT/$f"                  # 並說明為什麼（對不上排除規則）
  # skill 範例裡的 `gh pr …` / `gh issue …` 反引號片段不帶串接符號
  python3 -I - "$OPSX_ROOT/$f" <<'PY' || fail "$f 的 gh 範例有串接"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
bad = [s for s in re.findall(r"`(gh (?:pr|issue) [^`]*)`", text) if re.search(r"[;|]|&&|\$\(", s)]
if bad:
    sys.exit("串接的 gh 範例：%r" % bad)
PY
done
# 掃描要真的掃到 gh issue 範例，不是空集合
assert_grep "\`gh issue comment " "$OPSX_ROOT/skills/pr/SKILL.md"
assert_grep "\`gh pr view " "$OPSX_ROOT/skills/pr/SKILL.md"
