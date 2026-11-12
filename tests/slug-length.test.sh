#!/usr/bin/env bash
# 卡名上限：建立與派工的入口對 33 字的 slug 都拒絕、訊息指名 slug 與原文，不改檔；32 字通過；propose 文件寫的上限跟規則一致。
# 驗收：specs/slug-length-guard/spec.md（規則 [a-z][a-z0-9_-]{0,31}，總長 32 字；看板收的長度由 board-long-slug 管，不在這裡）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
mkdir -p "$OPSX_STATE_DIR"
ROOT="$FX/code"; mkdir -p "$ROOT"
cd "$ROOT"
A="$(mk_opsx_repo a)"; mv "$A" "$ROOT/a"; A="$(cd "$ROOT/a" && pwd -P)"
CH="$A/openspec/changes"
snap() { find "$A/openspec" "$OPSX_STATE_DIR" -type f -exec shasum {} + | sort; }

LONG="a$(printf 'b%.0s' $(seq 1 32))"   # 33 字
OK32="a$(printf 'b%.0s' $(seq 1 31))"   # 32 字
assert_eq "${#LONG}" 33; assert_eq "${#OK32}" 32

# 被拒絕：退出非零、輸出含 slug 與原文、沒有檔案變動
rejects() { # <名> <指令…>
  local name="$1"; shift
  local before out; before="$(snap)"
  out="$("$@" 2>&1)" && fail "${name}：33 字的 slug 要退出非零"
  case "$out" in *slug*) ;; *) fail "${name}：訊息要含「slug」：$out" ;; esac
  case "$out" in *"$LONG"*) ;; *) fail "${name}：訊息要含 slug 原文：$out" ;; esac
  assert_eq "$(snap)" "$before" "${name}：不能改檔"
}
OTHER="$(opsx new --repo "$A" -- 另一張卡)"
# 長名字的卡真的存在（手建或別的來源帶進來），拒絕的原因才會是名字不是「沒有這張卡」
mkdir -p "$CH/$LONG"; printf 'schema: opsx\n' > "$CH/$LONG/.openspec.yaml"
printf -- '---\ntype: 功能\nsource: me\n---\n\n## 一句話\n\n長名字\n\n## 證據\n\n' > "$CH/$LONG/inbox.md"
mkdir -p "$OPSX_STATE_DIR/unfiled"; printf -- '---\ntype: 功能\nsource: me\n---\n\n## 一句話\n\n長名字\n' > "$OPSX_STATE_DIR/unfiled/$LONG.md"
rejects dispatch opsx dispatch "$LONG" --agent claude --mode interactive --kind dev --repo "$A"
rejects note opsx note "$LONG" --repo "$A" -- 給你的話
rejects file opsx file "$LONG" --repo "$A"
rejects drop opsx drop "$LONG" --repo "$A" -- 不要了
rejects merge-card-source opsx merge-card "$LONG" --into "$OTHER" --repo "$A"
rejects merge-card-target opsx merge-card "$OTHER" --into "$LONG" --repo "$A"

# chain 與 coordinate 用的 AGENT_NAME 是同一條規則
python3 -I -c 'import sys;sys.path.insert(0, sys.argv[1]);import chain;l,k=sys.argv[2:4];assert not chain.AGENT_NAME.match(l);assert chain.AGENT_NAME.match(k)' "$OPSX_ROOT/bin/lib" "$LONG" "$OK32" || fail "chain.AGENT_NAME 要拒 33 字、收 32 字"

# 32 字通過格式檢查：note 因為卡不存在才失敗，不是因為 slug 格式
out="$(opsx note "$OK32" --repo "$A" -- 給你的話 2>&1)" && fail "卡不存在 note 要失敗"
case "$out" in *"slug 要符合"*) fail "32 字不能被格式檢查拒絕：$out" ;; esac

# propose 文件寫的上限等於規則
RULE='[a-z][a-z0-9_-]{0,31}'
grep -qF "$RULE" "$OPSX_ROOT/skills/propose/SKILL.md" || fail "skills/propose/SKILL.md 要寫 $RULE"
echo ok
