#!/usr/bin/env bash
# PreToolUse(Bash / Edit / Write)：autopilot 模式下的授權閘門。要求檔 §3.6 授權三級、§8.5。
#   第三級（永遠要人）一律 deny；第二級查 grants.toml（repo 永遠）與 dispatch.json（這張卡）；
#   互動模式或不在卡上就不管。deny 訊息要 worker 寫 gates.md 然後做能做的。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

top="$(repo_top)"; slug="$(card_slug)"
slug="${slug%%--*}"   # 子殼分支 <主>--<子> 沒有自己的 dispatch.json 條目，照主 change 的模式與授權
wt="$(wt_name)"; wt="${wt%%--*}"
[ -n "$top" ] || exit 0
repo="$(repo_name)"
# 對不到卡（分支不是三段，或 key 不在 dispatch.json，例如 subagent 的 worktree-agent-<id>、fanout 子分支）：
# repo 有 autopilot / drive 的卡在跑時只管第三級；第二級沒有卡可查授權，放行。
UNMAPPED=0
mode=""
# dispatch.json 壞掉時讀不到模式，就退回比對檔案原文：有 slug 的分支，裡面有這張卡的 key 才擋；
# 沒有 slug 的分支（對不到任何卡），裡面有這個 repo 的卡（key 前綴）才擋。沒有就不管。
# 讀不到檔時，$(<…) 會是空字串、比對不到，所以要先擋。
dispatch_broken() {
  local needle="\"$repo/$slug"; [ -n "$slug" ] && needle="$needle\""
  [ -r "$OPSX_STATE_DIR/dispatch.json" ] || deny "opsx 授權閘門：讀不到 $OPSX_STATE_DIR/dispatch.json，分不出 $repo 的卡的模式，先擋下。檢查這個檔案的權限"
  [[ $(<"$OPSX_STATE_DIR/dispatch.json") == *"$needle"* ]] || exit 0
  deny "opsx 授權閘門：$OPSX_STATE_DIR/dispatch.json 不是合法 JSON，讀不到 $repo 的卡的模式，先擋下。修好這個檔案"
}
if [ -n "$slug" ]; then
  mode="$(card_mode "$repo" "$slug")" || dispatch_broken
fi
# dispatch.json 的 key 是派工時的名字，也就是 worktree 名（feature session 是 feature 名），可以跟 branch 的卡不同：兩個有一個受管就照受管的那個
case "$mode" in autopilot|drive) ;; *)
  if [ -n "$wt" ] && [ "$wt" != "$slug" ]; then
    wmode="$(card_mode "$repo" "$wt" || true)"
    case "$wmode" in autopilot|drive) slug="$wt"; mode="$wmode" ;; esac
  fi ;;
esac
if [ -z "$mode" ]; then
  rc=0; repo_has_live_card "$repo" || rc=$?
  case "$rc" in 0) UNMAPPED=1 ;; 1) exit 0 ;; *) dispatch_broken ;; esac
else
  case "$mode" in autopilot|drive) ;; *) exit 0 ;; esac
fi
# 查授權要 python。沒有就明確 deny，因為 hook 非 0 結束 Claude Code 會當成放行。修法那一條指令本身放行。
# 對不到卡時第三級不用查授權，不需要 python。
if [ -z "$OPSX_PY" ] && [ "$UNMAPPED" = 0 ]; then
  [ "$(hook_cmd)" = "opsx init --global" ] && exit 0
  deny "opsx 授權閘門：讀不到授權，先擋下。$OPSX_PY_ERR"
fi
PY_FAIL="opsx 授權閘門：python 執行失敗（${OPSX_PY}），讀不到授權，先擋下。跑 opsx init --global"

tool="$(hook_tool)"; cmd="$(hook_cmd)"; file="$(hook_file)"
GATE_MSG="用 Edit 或 Write 寫 gates.md（type: approval | decision，要使用者在終端機跑指令的另加 needs: run，decision 要等別張卡合進 main 才能做的另加 waits-on: <卡名>；問題、建議、證據、風險、沒回答的預設；不要用 Bash 寫，opened_at 不用寫，hook 會補），然後做能做的；人在板上回了會自動繼續"

level3() { deny "opsx 授權閘門：「$1」是永遠要人的動作（第三級），任何授權蓋不掉。$GATE_MSG"; }

# 合併唯一的例外：看板「合併」按鈕（opsx merge）在受保護位置（bin/lib/authz.py）這張卡寫了 merge_approved = <MR head sha>。
# dispatch.json 的同名欄位沙盒內寫得到，一律不看。herdr-board D5。
# 放行條件：指令整條就是 merge [--squash] [<MR 號碼>]（旗標與號碼的位置不拘，其他旗標與任何串接都不行）、合併的 MR 號碼等於卡的 report.md
# 那條、現在的 head sha 等於核准的 sha。核准不刪：它綁 sha，合併成功後 MR 變 merged 就自然不成立，又推了 commit 也不成立；
# 不在執行前刪，是因為 glab 可能失敗（405 要 rebase、網路），刪了人就得重按。放行後不 exit，後面的第三級檢查照跑。
merge_gate() { # 回 0 放行；否則 deny（deny 會 exit）
  # shellcheck source=/dev/null
  source "$OPSX_ROOT/bin/lib/mr.sh"
  local d="$top/openspec/changes/$slug" approved head want_iid cmd_iid
  # 整條原文（含換行）只准是 merge [--squash] [<iid>]：別的旗標（-R）、單一 &、換行、重導向都不是核准的那條指令
  local re='^(glab mr merge|gh pr merge)( +--squash)*( +([0-9]+))?( +--squash)* *$'
  [[ $cmd =~ $re ]] || deny "opsx 授權閘門：合併指令要單獨一條，只准 merge [--squash] [<MR 號碼>]，不能跟別的指令或旗標串在一起（收到：${c}）"
  cmd_iid="${BASH_REMATCH[4]}"
  approved="$(OPSX_KEY="$repo/$slug" OPSX_SD="$OPSX_STATE_DIR" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import authz
print(authz.load(os.environ["OPSX_SD"]).get(os.environ["OPSX_KEY"], {}).get("merge_approved") or "")
PY
)" || deny "$PY_FAIL"
  [ -n "$approved" ] || deny "opsx 授權閘門：merge 是永遠要人的動作（第三級）。要人在看板上按「合併」（opsx merge ${slug}）才會放行；在這之前把 MR 弄到五條件全綠（/opsx-workflow:babysit），不要自己合"
  want_iid="$(st_mr_url "$d" | grep -oE '[0-9]+$' || true)"
  if [ -n "$cmd_iid" ] && [ "$cmd_iid" != "$want_iid" ]; then
    deny "opsx 授權閘門：核准的是這張卡的 MR ${want_iid:-（report.md 沒有）}，指令要合併的是 ${cmd_iid}"
  fi
  head="$(OPSX_MR_CACHE_TTL=0 mr_json "$d" | "$OPSX_PY" -I -c 'import json,sys; print(json.load(sys.stdin).get("head_sha") or "")')" || deny "$PY_FAIL"
  if [ "$head" != "$approved" ]; then
    deny "opsx 授權閘門：看板核准的是 ${approved}，MR 現在的 head 是 ${head:-讀不到}（又推了 commit？）。寫 gates.md 請人在看板重新按「合併」"
  fi
  return 0
}
# autopilot 用 dontAsk 起，不在 settings allow 的指令 Claude 直接拒；所以有授權的動作要由這裡明說 allow，
# 板上事後給的「這次 / 這張卡」授權才生效。等整條指令所有檢查都過了才 allow，一段有授權不能替後面那段放行。
GRANTED=0
allow() { jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:"opsx 授權閘門：有授權"}}'; exit 0; }

level2() { # <action> <label>
  local rc=0
  has_grant "$repo" "$slug" "$1" || rc=$?
  case "$rc" in 0) GRANTED=1; return 0 ;; 3) ;; *) deny "$PY_FAIL" ;; esac
  deny "opsx 授權閘門：「$2」要授權（第二級），$repo 沒有長期授權、這張卡也沒有。gate 寫 action: $1。$GATE_MSG"
}

# 第二級的樣式：整串逐條查授權與逐段查涵蓋共用同一組
RE_PUSH='(^|\s|&&|;)git\s+push(\s|;|&|\||$)'
RE_MR='(glab mr (create|update)|gh pr (create|edit)|glab issue (note|comment)|gh issue comment)'
RE_MIGRATE='db:migrate|drizzle-kit (migrate|push)|alembic upgrade'
RE_DELETE='(^|\s|&&|;)rm\s+-(r|f|rf|fr)\b'
RE_INSTALL='(pnpm (add|install|i)\b|npm (install|i|ci)\b|uv (add|sync)|pip install|yarn add|brew install)'
RE_REBASE='(^|\s|&&|;)git\s+rebase(\s|;|&|\||$)'
RE_EXTERNAL='(curl|wget|http)\s+'
RE_LOCAL='localhost|127\.0\.0\.1|litellm\.agentory\.cc'

# 這段文字落在任何第二級類別（授權在整串逐條查過了，走到這裡的都有）
l2_text_matches() { # <段>
  printf '%s' "$1" | grep -qE "$RE_PUSH|$RE_MR|$RE_MIGRATE|$RE_DELETE|$RE_INSTALL|$RE_REBASE" && return 0
  printf '%s' "$1" | grep -qE "$RE_EXTERNAL" && ! printf '%s' "$1" | grep -qE "$RE_LOCAL" && return 0
  return 1
}

# dispatch 給這個 agent 的 settings 的 Bash allow 樣式（bin/lib/launch.sh write_settings 寫的），要用到才讀
ALLOW_LOADED=0; ALLOW_PATTERNS=()
load_allow() {
  [ "$ALLOW_LOADED" = 1 ] && return 0
  local f="$OPSX_STATE_DIR/settings/$repo-$slug-$mode.json" raw line
  [ -r "$f" ] || deny "opsx 授權閘門：串起來的指令有幾段要查這個 agent 的 settings allow，讀不到 ${f}，先擋下。把指令拆開，每條單獨送"
  raw="$(jq -r '.permissions.allow[]? | select(startswith("Bash(")) | .[5:-1]' "$f")" || deny "opsx 授權閘門：${f} 不是合法 JSON，讀不到 allow，先擋下"
  while IFS= read -r line; do [ -z "$line" ] || ALLOW_PATTERNS+=("$line"); done <<< "$raw"
  ALLOW_LOADED=1
}
in_allow() { # <段>：Bash(<前綴>:*) 看前綴，Bash(<整句>) 看相等
  local p prefix
  for p in ${ALLOW_PATTERNS[@]+"${ALLOW_PATTERNS[@]}"}; do
    case "$p" in
      *:\*) prefix="${p%:\*}"; case "$1" in "$prefix"|"$prefix "*) return 0 ;; esac ;;
      *) [ "$1" = "$p" ] && return 0 ;;
    esac
  done
  return 1
}
# 把指令拆成段，第一個沒涵蓋的存進 UNCOVERED、回 0；都涵蓋（或只有一段）回 1
UNCOVERED=""
first_uncovered_segment() {
  local segs seg n
  segs="$(cmd_skeleton "$cmd" | "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/cmdsegments.py" split)" || deny "opsx 授權閘門：拆不開指令的段（${OPSX_PY} cmdsegments.py split 失敗），先擋下"
  n="$(printf '%s\n' "$segs" | grep -c . || true)"
  [ "$n" -gt 1 ] || return 1
  while IFS= read -r seg; do
    case "$seg" in cd|"cd "*|echo|"echo "*|pwd|true|false) continue ;; esac   # 不碰檔案也不碰網路的小指令
    l2_text_matches "$seg" && continue
    load_allow
    in_allow "$seg" && continue
    UNCOVERED="$seg"; return 0
  done <<< "$segs"
  return 1
}

# 測試檔放非慣例位置：所在那一層（不含子目錄）在 cwd 所在 worktree 的追蹤檔裡沒有測試檔。要授權回 0，不用回 1。
# 檔名要先確認像測試、而且是 mapped 的卡（呼叫者做），git 才不會對每個檔都跑。
testpath_needs_grant() { # <絕對路徑>
  local file="$1" wtop base missing real tracked
  wtop="$(git -C "$(hook_cwd)" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$wtop" ] || return 1
  case "$file" in /*) ;; *) deny "opsx 授權閘門：file_path 不是絕對路徑（${file}），分不出它在哪個 worktree，先擋下。用絕對路徑" ;; esac
  # 下面往上找目錄是逐段剪字串，`..` 會讓它爬到跟檔案實際位置不同的地方
  case "$file" in */../*|*/..) deny "opsx 授權閘門：file_path 含 ..（${file}），分不出它實際在哪個 worktree，先擋下。用不含 .. 的絕對路徑" ;; esac
  # 目錄還不存在時往上找最近存在的那層，用它判斷屬於哪個 worktree；進不去就擋，不讓 git 默默失敗後放行
  base="${file%/*}"; missing=0
  while [ -n "$base" ] && [ ! -d "$base" ]; do base="${base%/*}"; missing=1; done
  real="$(cd "${base:-/}" && pwd -P)" || deny "opsx 授權閘門：進不了 ${base:-/}，分不出 ${file} 屬於哪個 worktree，先擋下"
  base="$real"
  [ "$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || true)" = "$wtop" ] || return 1
  if [ "$missing" = 0 ]; then
    # :(glob) 的 * 不跨 /，所以只列這一層；樣式跟檔名 case 同一組
    tracked="$(git -C "$base" ls-files -- ':(glob)*.test.*' ':(glob)*.spec.*' ':(glob)test_*.py' ':(glob)*_test.*')" || deny "opsx 授權閘門：git ls-files 失敗（${base}），分不出這一層有沒有既有測試，先擋下"
    [ -n "$tracked" ] && return 1
  fi
  return 0
}

# Bash 指令的寫檔目標（cmdsegments.py writes）套用 Edit / Write 同一套 env 與 test-path 判斷。
# 目錄讀不出來（含變數、命令替換、萬用字元、~、..）而檔名是 env 或測試檔時 deny；檔名本身讀不出來的不管。
# shortcut: 只看檔名像 env 或測試的目標，其餘寫檔不查；cwd 之後的 cd 不追蹤（相對路徑照 session cwd 解），等有人靠 cd 繞過再補
bash_write_checks() {
  local targets t name dir abs
  targets="$(cmd_skeleton "$cmd" | "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/cmdsegments.py" writes)" || deny "opsx 授權閘門：讀不懂指令的寫檔目標（cmdsegments.py writes 失敗），先擋下"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    case "$t" in /dev/*) continue ;; esac
    name="${t##*/}"; dir="${t%/*}"; [ "$dir" = "$t" ] && dir=""
    case "$name" in
      *.env.example) continue ;;
      *.env|*.env.*) ;;
      *.test.*|*.spec.*|test_*.py|*_test.*) ;;
      *) continue ;;
    esac
    case "$dir" in
      *[\$\`\*\?\[\{~\\\"\']*|..|../*|*/..|*/../*) deny "opsx 授權閘門：Bash 寫「${t}」，目錄讀不到（含變數、命令替換、萬用字元、~ 或 ..），分不出它是不是 env 或沒有測試的目錄，先擋下。改用不含這些的字面路徑" ;;
    esac
    case "$t" in /*) abs="$t" ;; *) abs="$(hook_cwd)/$t" ;; esac
    case "$name" in
      *.env|*.env.*) level2 env "Bash 寫 ${t}" ;;
      *) if testpath_needs_grant "$abs"; then level2 test-path "Bash 把測試檔寫進沒有既有測試的目錄（${t}）"; fi ;;
    esac
  done <<< "$targets"
}

if [ "$tool" = "Bash" ]; then
  [ -n "$cmd" ] || exit 0
  c="$(printf '%s' "$cmd" | tr '\n' ' ')"
  # 第三級比對原文，只扣掉三種容器（commit 訊息、opsx answer 答案、寫檔 heredoc）的資料部分，認不得的寫法都留著（grill D1）；
  # 第二級比對指令骨架（引號與 heredoc 內的字樣不算）。merge_gate 與訊息仍讀原文。
  l3="$(cmd_l3text "$cmd" | tr '\n' ' ')" || deny "opsx 授權閘門：perl 執行失敗，讀不到指令內容，先擋下。確認 perl 可用"
  sk="$(cmd_skeleton "$cmd" | tr '\n' ' ')" || deny "opsx 授權閘門：perl 執行失敗，讀不到指令骨架，先擋下。確認 perl 可用"
  # 第三級（merge 放行後不 exit，其餘檢查照跑）
  if printf '%s' "$l3" | grep -qE '(glab mr merge|gh pr merge)'; then
    [ "$UNMAPPED" = 1 ] && level3 "merge"
    merge_gate && GRANTED=1
  fi
  printf '%s' "$l3" | grep -qE 'git\s+push.*(--force|-f\b|\+[a-zA-Z])' && level3 "force-push"
  # 同一段 push 內，refspec 目標是 main / master 才算；分支名只含 main 片段、push 以外的 main 字樣不算（hooks/security-guard.sh 同一條）
  push_main='git\s+push\b[^;&|]*[[:space:]:+"'"'"'](refs/heads/)?(main|master)([^A-Za-z0-9._/:-]|$)'
  printf '%s' "$l3" | grep -qE "$push_main" && level3 "push main"
  printf '%s' "$l3" | grep -qiE '(^|\s|/)deploy(\.sh)?(\s|$)' && level3 "deploy"
  printf '%s' "$l3" | grep -qiE 'drop\s+(table|database|schema)|truncate\s+table|db:reset' && level3 "刪資料"
  printf '%s' "$l3" | grep -qE 'sops\s+(-e|--encrypt|edit)|\.gitlab-ci\.yml|\.github/workflows' && level3 "改 CI / secrets"
  [ "$UNMAPPED" = 1 ] && exit 0
  # 第二級
  printf '%s' "$sk" | grep -qE "$RE_PUSH" && level2 push "git push"
  printf '%s' "$sk" | grep -qE "$RE_MR" && level2 mr "開 / 改 MR"
  printf '%s' "$sk" | grep -qE "$RE_MIGRATE" && level2 migrate "本機 migrate"
  printf '%s' "$sk" | grep -qE "$RE_DELETE" && level2 delete "刪檔（rm -r/-f）"
  printf '%s' "$sk" | grep -qE "$RE_INSTALL" && level2 install "裝套件"
  printf '%s' "$sk" | grep -qE "$RE_REBASE" && level2 rebase "git rebase"
  printf '%s' "$sk" | grep -qE "$RE_EXTERNAL" && ! printf '%s' "$sk" | grep -qE "$RE_LOCAL" && level2 external "呼叫外部 API"
  # 寫檔目標：Edit / Write 查的 env 與 test-path，改用 Bash 寫（重導向、tee、cp、mv、git mv）也一樣要查。先用骨架裡有沒有這些字眼擋掉大多數指令，不白起 python
  case "$sk" in *">"*|*tee*|*"cp "*|*"mv "*) bash_write_checks ;; esac
  # 一段有授權不能替整串放行：串起來的指令每一段都要有授權、屬於不用授權的小指令、或在 dispatch 給這個 agent 的 settings allow 裡
  if [ "$GRANTED" = 1 ]; then
    first_uncovered_segment && deny "opsx 授權閘門：這條串起來的指令有一段沒有授權、也不在這個 agent 的 settings allow 裡：「${UNCOVERED}」。把它拆成單獨一條指令；它需要授權的話，$GATE_MSG"
    allow
  fi
  exit 0
fi

if [ "$tool" = "Edit" ] || [ "$tool" = "Write" ]; then
  [ -n "$file" ] || exit 0
  case "$file" in
    *.gitlab-ci.yml|*/.github/workflows/*|*secrets*|*.sops.*|*/sops/*) level3 "改 CI / secrets（${file}）" ;;
    *.env.example) exit 0 ;;
    *.env|*.env.*) [ "$UNMAPPED" = 1 ] && exit 0; level2 env "寫 $file"; allow ;;
  esac
  # 先看檔名，git 只在像測試時才跑
  case "${file##*/}" in *.test.*|*.spec.*|test_*.py|*_test.*) ;; *) exit 0 ;; esac
  [ "$UNMAPPED" = 1 ] && exit 0
  testpath_needs_grant "$file" || exit 0
  level2 test-path "測試檔寫進沒有既有測試的目錄（${file}）"
  allow
fi
exit 0
