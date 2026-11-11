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
  printf '%s' "$sk" | grep -qE '(^|\s|&&|;)git\s+push(\s|$)' && level2 push "git push"
  printf '%s' "$sk" | grep -qE '(glab mr (create|update)|gh pr (create|edit|comment)|glab issue (note|comment)|gh issue comment)' && level2 mr "開 / 改 MR"
  # GitLab 沒有 gh pr comment 這種子命令，留言走 api：只認 MR notes 的 POST / PUT 這一種形狀，且整條指令只能是它。
  # 路徑在引號裡，骨架看不到，所以比對原文；其他 glab api（例如打 /merge）不分類，交給 settings 拒。
  glab_note='^glab api --method (POST|PUT) "projects/:id/merge_requests/[0-9]+/notes(/[0-9]+)?" --field body=@[A-Za-z0-9_./-]+ *$'
  [[ $cmd =~ $glab_note ]] && level2 mr "留言到 MR"
  printf '%s' "$sk" | grep -qE 'db:migrate|drizzle-kit (migrate|push)|alembic upgrade' && level2 migrate "本機 migrate"
  printf '%s' "$sk" | grep -qE '(^|\s|&&|;)rm\s+-(r|f|rf|fr)\b' && level2 delete "刪檔（rm -r/-f）"
  printf '%s' "$sk" | grep -qE '(pnpm (add|install|i)\b|npm (install|i|ci)\b|uv (add|sync)|pip install|yarn add|brew install)' && level2 install "裝套件"
  printf '%s' "$sk" | grep -qE '(^|\s|&&|;)git\s+rebase(\s|$)' && level2 rebase "git rebase"
  printf '%s' "$sk" | grep -qE '(curl|wget|http)\s+' && ! printf '%s' "$sk" | grep -qE 'localhost|127\.0\.0\.1|litellm\.agentory\.cc' && level2 external "呼叫外部 API"
  [ "$GRANTED" = 1 ] && allow
  exit 0
fi

if [ "$tool" = "Edit" ] || [ "$tool" = "Write" ]; then
  [ -n "$file" ] || exit 0
  case "$file" in
    *.gitlab-ci.yml|*/.github/workflows/*|*secrets*|*.sops.*|*/sops/*) level3 "改 CI / secrets（${file}）" ;;
    *.env.example) exit 0 ;;
    *.env|*.env.*) [ "$UNMAPPED" = 1 ] && exit 0; level2 env "寫 $file"; allow ;;
  esac
  # 測試檔放非慣例位置：所在那一層（不含子目錄）在 cwd 所在 worktree 的追蹤檔裡沒有測試檔。
  # 先看檔名，git 只在像測試時才跑。
  case "${file##*/}" in *.test.*|*.spec.*|test_*.py|*_test.*) ;; *) exit 0 ;; esac
  [ "$UNMAPPED" = 1 ] && exit 0
  wtop="$(git -C "$(hook_cwd)" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$wtop" ] || exit 0
  case "$file" in /*) ;; *) deny "opsx 授權閘門：file_path 不是絕對路徑（${file}），分不出它在哪個 worktree，先擋下。用絕對路徑" ;; esac
  # 下面往上找目錄是逐段剪字串，`..` 會讓它爬到跟檔案實際位置不同的地方
  case "$file" in */../*|*/..) deny "opsx 授權閘門：file_path 含 ..（${file}），分不出它實際在哪個 worktree，先擋下。用不含 .. 的絕對路徑" ;; esac
  # 目錄還不存在時往上找最近存在的那層，用它判斷屬於哪個 worktree；進不去就擋，不讓 git 默默失敗後放行
  base="${file%/*}"; missing=0
  while [ -n "$base" ] && [ ! -d "$base" ]; do base="${base%/*}"; missing=1; done
  real="$(cd "${base:-/}" && pwd -P)" || deny "opsx 授權閘門：進不了 ${base:-/}，分不出 ${file} 屬於哪個 worktree，先擋下"
  base="$real"
  [ "$(git -C "$base" rev-parse --show-toplevel 2>/dev/null || true)" = "$wtop" ] || exit 0
  if [ "$missing" = 0 ]; then
    # :(glob) 的 * 不跨 /，所以只列這一層；樣式跟上面的檔名 case 同一組
    tracked="$(git -C "$base" ls-files -- ':(glob)*.test.*' ':(glob)*.spec.*' ':(glob)test_*.py' ':(glob)*_test.*')" || deny "opsx 授權閘門：git ls-files 失敗（${base}），分不出這一層有沒有既有測試，先擋下"
    [ -n "$tracked" ] && exit 0
  fi
  level2 test-path "測試檔寫進沒有既有測試的目錄（${file}）"
  allow
fi
exit 0
