#!/usr/bin/env bash
# /pr 第一次開 MR 後回原 issue 留 MR 連結；更新 MR、非 issue 來源不回寫；回寫失敗不擋 /pr。
# 對應 issue-backlink 的 specs/issue-backlink。skill 是文字，只能檢查 skill 寫了什麼。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

f="$OPSX_ROOT/skills/pr/SKILL.md"
assert_file "$f"

# 兩種 forge 的指令與定位方式
assert_grep "glab issue note <n> -R " "$f"
assert_grep 'gh issue comment <upstream_url> --body "<mr url>"' "$f"
assert_grep "upstream_url" "$f"

# 只在開新 MR、只對 gitlab: / github: 來源
assert_grep "Back-link" "$f"
assert_grep "only when this run opened a new MR" "$f"
assert_grep '`source:` starts with `gitlab:` or `github:`' "$f"
assert_grep "any other source" "$f"

# 更新路徑寫明不回寫
assert_grep "update path never comments on the issue" "$f"

# 不回寫狀態
assert_grep "never close the issue or change its labels" "$f"

# 回寫失敗（含缺 upstream_url）記進 report.md、不擋 /pr
assert_grep "issue 回寫失敗：<" "$f"
assert_grep "missing \`upstream_url\`" "$f"
assert_grep "does not stop /pr" "$f"

# 授權閘門擋下回寫（一次性 mr 授權已被開 MR 用掉）也是回寫失敗：記一行、不開 gate
assert_grep "issue 回寫失敗：無 mr 授權" "$f"
assert_grep "do not write a gate" "$f"
# 只有 deny 訊息帶 action: mr 才記「無 mr 授權」，其他 deny 記訊息第一行
assert_grep 'deny message carries `action: mr`' "$f"
assert_grep "first line of the deny message" "$f"

# Back-link 在步驟 5（寫 report.md）之後、步驟 6（Reply）之前
python3 -I - "$f" <<'PY' || fail "Back-link 不在步驟 5 與 6 之間"
import sys
text = open(sys.argv[1], encoding="utf-8").read()
verify = text.index("**Verify.**")
backlink = text.index("**Back-link.**")
reply = text.index("**Reply.**")
if not verify < backlink < reply:
    sys.exit("順序：verify=%d backlink=%d reply=%d" % (verify, backlink, reply))
PY
