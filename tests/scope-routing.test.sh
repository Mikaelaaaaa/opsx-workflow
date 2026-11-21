#!/usr/bin/env bash
# skill 的範圍規則：卡範圍內同一張修，範圍外開卡帶「做到 propose 就停」派工指示，範圍題不開 gate。
# 只證明規則寫在對的段落；agent 守不守由 eval 驗。對應 openspec/changes/scope-routing-skills/specs/scope-routing。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
hasnt() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }

APPLY="$OPSX_ROOT/skills/apply/SKILL.md"
REVIEW="$OPSX_ROOT/skills/review/SKILL.md"
GRILL="$OPSX_ROOT/skills/grill/SKILL.md"
EXPLORE="$OPSX_ROOT/skills/explore/SKILL.md"
LMAP="$OPSX_ROOT/skills/logic-map/SKILL.md"
LEAD="$OPSX_ROOT/skills/lead/SKILL.md"
PROPOSE="$OPSX_ROOT/skills/propose/SKILL.md"
CONTINUE="$OPSX_ROOT/references/continue.md"
NOTE='做到 propose 完成就停（留在待指派），不要 apply'
# Stop hook 不把這種問法算成擋住的 gate（bin/lib/stage.sh st_gates_file_blocking）
HOOK_ASK='要不要(接|派|繼續)([ ]*/|[ ]*下一|\?|？|：|$)'

grep -F '| 6 |' "$APPLY" > "$FX/apply6"
grep -F -- '- **範圍外.**' "$REVIEW" > "$FX/review-oos"
grep -F -- '- **Logic map, undecided.**' "$REVIEW" > "$FX/review-lm"
grep -F 'Then scope every BUG and MUST_FIX' "$REVIEW" > "$FX/review-scope"
grep -F "Then read the map's" "$REVIEW" > "$FX/review-1b"
grep -F "outside this card's scope" "$GRILL" > "$FX/grill-oos"
grep -F "outside this card's scope" "$EXPLORE" > "$FX/explore-oos"
awk '/^## Answering questions about a map/{on=1} /^## Output template/{on=0} on' "$LMAP" > "$FX/lmap-qa"
grep -F '2. **Forward gates' "$LEAD" > "$FX/lead2"
awk '/^## 怎麼問 gate/{on=1;next} /^## /{on=0} on' "$LEAD" > "$FX/lead-ask"
awk '/^### 6b\./{on=1;next} /^##/{on=0} on' "$PROPOSE" > "$FX/propose-6b"
grep -F 'binds only the work before propose' "$CONTINUE" > "$FX/expiry"
grep -F '| 5 |' "$APPLY" > "$FX/apply5"
grep -F '5c. **Logic map.**' "$OPSX_ROOT/skills/pr/SKILL.md" > "$FX/pr5c"
for f in apply6 review-oos review-lm review-scope review-1b grill-oos explore-oos lmap-qa lead2 lead-ask propose-6b expiry apply5 pr5c; do
  [ -s "$FX/$f" ] || fail "段落找不到：$f"
done
[ "$(wc -l < "$FX/grill-oos" | tr -d ' ')" = 1 ] || fail "grill 的範圍出口要剛好一段"
[ "$(wc -l < "$FX/explore-oos" | tr -d ' ')" = 1 ] || fail "explore 的範圍出口要剛好一段"

# --- apply 以卡範圍判開卡（正例／反例）---
has "this card's scope" "$FX/apply6"
has 'add a task' "$FX/apply6"
hasnt "outside this task's scope" "$FX/apply6"

# --- 開卡的 skill 都寫派工指示（Scenario Outline：review、apply、grill、explore）---
for f in "$FX/apply6" "$FX/review-oos" "$FX/grill-oos" "$FX/explore-oos"; do
  has 'opsx note' "$f"
  has "$NOTE" "$f"
done

# --- 併進別張卡時不寫指示（反例）---
for f in "$FX/apply6" "$FX/review-oos"; do
  has 'only when the printed slug is a fresh card' "$f"
  has 'skip `opsx note` when it merged' "$f"
done

# --- skill 明寫範圍不問人（Scenario Outline：review、apply、grill、explore）---
for f in "$FX/apply6" "$FX/review-scope" "$FX/grill-oos" "$FX/explore-oos"; do
  has 'never a gate option' "$f"
  has '範圍內的產品取捨' "$f"
done

# --- 範圍內的產品取捨仍開 gate（反例）---
has 'is still bucket 3' "$FX/grill-oos"

# --- 改程式前以卡打算改的東西判範圍（正例／反例）---
has 'inbox.md, explore.md or proposal.md sets out to change' "$FX/review-scope"
has 'only to findings against the implemented diff' "$FX/review-scope"

# --- review 先判 ⚠ 的範圍；Step 1b 不再說全部進 gate ---
has '（既有）' "$FX/review-lm"
has 'happens on main too, is 範圍外' "$FX/review-lm"
has 'opens a card instead of entering the gate' "$FX/review-lm"
has 'unclassified items are scoped the same way' "$FX/review-lm"
has 'unclassified items are scoped the same way' "$FX/lmap-qa"
has 'Logic map, undecided' "$FX/pr5c"
has '範圍外' "$FX/pr5c"
has 'which scopes them first' "$FX/review-1b"
hasnt 'go to the gate in Step 4' "$FX/review-1b"

# --- logic-map 問答標範圍外／不開卡 ---
has '範圍外，review 會開卡' "$FX/lmap-qa"
hasnt 'opsx new' "$FX/lmap-qa"
has 'Do not write or change any file' "$FX/lmap-qa"

# --- 協調者判範圍題（正例）／其他 gate 仍不代答（反例）／帶 waits-on 的先等 ---
has '協調者判定：範圍內' "$FX/lead2"
has '協調者判定：範圍外' "$FX/lead2"
has '④' "$FX/lead2"
has 'answer only the scope half' "$FX/lead2"
has 'answer none yourself' "$FX/lead2"
has 'waits for that card to merge before you judge its scope' "$FX/lead2"
has 'Every other gate is unchanged' "$FX/lead2"
has 'every other gate (each `approval`, and every gate in other repos) waits for the user' "$FX/apply5"
has '要不要另開卡／併進這張' "$FX/apply5"
has '協調者判定：範圍外' "$FX/apply5"
has 'open the card by row 6' "$FX/apply5"
has '不代答' "$FX/lead-ask"

# --- P2 討論卡 propose 完開派工 gate；P0／P1 照常接 apply；沒帶指示不開 ---
has 'dispatch-<name>' "$FX/propose-6b"
has '做到 propose 完成就停' "$FX/propose-6b"
has 'prints P2, write a' "$FX/propose-6b"
has 'stop instead of continuing to apply' "$FX/propose-6b"
has 'status: open' "$FX/propose-6b"
has 'treat the card as P2' "$FX/propose-6b"
has 'has no `## dispatch-<name>` yet' "$FX/propose-6b"
has '在這個 pane 接著 apply (Recommended)' "$FX/propose-6b"
has '先不派：跑 opsx stop <name> 停 pane，卡留在待指派' "$FX/propose-6b"
hasnt '從看板派' "$FX/propose-6b"
has 'A P0 or P1 card with that note continues to apply as usual and opens no gate' "$FX/propose-6b"
has 'A card without that note gets no such gate' "$FX/propose-6b"
ASK='<name> 已 propose 完，要派 apply 嗎？'
has "問題: $ASK" "$FX/propose-6b"
! printf '%s\n' "$ASK" | grep -qE "$HOOK_ASK" || fail "dispatch gate 的問題會被 Stop hook 當成不擋：$ASK"

# --- propose-stop 指示在有 tasks.md 時失效（寫在 continue.md，apply 不再自己寫）---
has '做到 propose 完成就停' "$FX/expiry"
has 'only once the card has tasks.md' "$FX/expiry"
has 'whoever invokes apply' "$FX/expiry"
has 'open no gate' "$FX/expiry"
has 'except that propose step 6b still opens its gate for a P2 card and stops' "$FX/expiry"
hasnt 'binds only the work before propose' "$APPLY"

echo "scope-routing OK"
