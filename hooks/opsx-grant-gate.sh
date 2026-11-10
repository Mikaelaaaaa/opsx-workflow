#!/usr/bin/env bash
# PreToolUse(Bash / Edit / Write)：autopilot 模式下的授權閘門。要求檔 §3.6 授權三級、§8.5。
#   第三級（永遠要人）一律 deny；第二級查 grants.toml（repo 永遠）與 dispatch.json（這張卡）；
#   互動模式或不在卡上就不管。deny 訊息要 worker 寫 gates.md 然後做能做的。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

top="$(repo_top)"; slug="$(card_slug)"
[ -n "$top" ] && [ -n "$slug" ] || exit 0
repo="$(repo_name)"
# dispatch.json 壞掉時讀不到模式，就退回比對檔案原文：裡面有這張卡的 key 才擋。
# 原文也讀不到時，$(<…) 會是空字串、比對不到，所以要先擋。
if ! mode="$(card_mode "$repo" "$slug")"; then
  [ -r "$OPSX_STATE_DIR/dispatch.json" ] || deny "opsx 授權閘門：讀不到 $OPSX_STATE_DIR/dispatch.json，分不出這張卡的模式，先擋下。檢查這個檔案的權限"
  [[ $(<"$OPSX_STATE_DIR/dispatch.json") == *"\"$repo/$slug\""* ]] || exit 0
  deny "opsx 授權閘門：$OPSX_STATE_DIR/dispatch.json 不是合法 JSON，讀不到這張卡的模式，先擋下。修好這個檔案"
fi
case "$mode" in autopilot|drive) ;; *) exit 0 ;; esac
# 查授權要 python。沒有就明確 deny，因為 hook 非 0 結束 Claude Code 會當成放行。修法那一條指令本身放行。
if [ -z "$OPSX_PY" ]; then
  [ "$(hook_cmd)" = "opsx init --global" ] && exit 0
  deny "opsx 授權閘門：讀不到授權，先擋下。$OPSX_PY_ERR"
fi
PY_FAIL="opsx 授權閘門：python 執行失敗（${OPSX_PY}），讀不到授權，先擋下。跑 opsx init --global"

tool="$(hook_tool)"; cmd="$(hook_cmd)"; file="$(hook_file)"
GATE_MSG="用 Edit 或 Write 寫 gates.md（type、問題、建議、證據、風險、沒回答的預設；不要用 Bash 寫，opened_at 不用寫，hook 會補），然後做能做的；人在板上回了會自動繼續"

level3() { deny "opsx 授權閘門：「$1」是永遠要人的動作（第三級），任何授權蓋不掉。$GATE_MSG"; }

# 合併唯一的例外：看板「合併」按鈕（opsx merge）在受保護位置（bin/lib/authz.py）這張卡寫了 merge_approved = <MR head sha>。
# dispatch.json 的同名欄位沙盒內寫得到，一律不看。herdr-board D5。
# 放行條件：指令整條只有這一個 merge（沒有 && ; | $( ` 夾帶別的）、合併的 MR 號碼等於卡的 report.md
# 那條、現在的 head sha 等於核准的 sha。核准不刪：它綁 sha，合併成功後 MR 變 merged 就自然不成立，又推了 commit 也不成立；
# 不在執行前刪，是因為 glab 可能失敗（405 要 rebase、網路），刪了人就得重按。放行後不 exit，後面的第三級檢查照跑。
merge_gate() { # 回 0 放行；否則 deny（deny 會 exit）
  # shellcheck source=/dev/null
  source "$OPSX_ROOT/bin/lib/mr.sh"
  local d="$top/openspec/changes/$slug" approved head want_iid cmd_iid
  printf '%s' "$c" | grep -qE '(&&|\|\||;|\||\$\(|`)' && deny "opsx 授權閘門：合併指令要單獨一條，不能跟別的指令串在一起（收到：${c}）"
  approved="$(OPSX_KEY="$repo/$slug" OPSX_SD="$OPSX_STATE_DIR" OPSX_LIB="$OPSX_ROOT/bin/lib" "$OPSX_PY" -I - <<'PY'
import os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import authz
print(authz.load(os.environ["OPSX_SD"]).get(os.environ["OPSX_KEY"], {}).get("merge_approved") or "")
PY
)" || deny "$PY_FAIL"
  [ -n "$approved" ] || deny "opsx 授權閘門：merge 是永遠要人的動作（第三級）。要人在看板上按「合併」（opsx merge ${slug}）才會放行；在這之前把 MR 弄到五條件全綠（/babysit），不要自己合"
  want_iid="$(st_mr_url "$d" | grep -oE '[0-9]+$' || true)"
  cmd_iid="$(printf '%s' "$c" | grep -oE '(glab mr merge|gh pr merge)[[:space:]]+[^-[:space:]][^[:space:]]*' | grep -oE '[0-9]+$' || true)"
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
  deny "opsx 授權閘門：「$2」要授權（第二級），$repo 沒有長期授權、這張卡也沒有。$GATE_MSG"
}

if [ "$tool" = "Bash" ]; then
  [ -n "$cmd" ] || exit 0
  c="$(printf '%s' "$cmd" | tr '\n' ' ')"
  # 第三級（merge 放行後不 exit，其餘檢查照跑）
  printf '%s' "$c" | grep -qE '(glab mr merge|gh pr merge)' && merge_gate && GRANTED=1
  printf '%s' "$c" | grep -qE 'git\s+push.*(--force|-f\b|\+[a-zA-Z])' && level3 "force-push"
  printf '%s' "$c" | grep -qE 'git\s+push.*\b(main|master)\b' && level3 "push main"
  printf '%s' "$c" | grep -qiE '(^|\s|/)deploy(\.sh)?(\s|$)' && level3 "deploy"
  printf '%s' "$c" | grep -qiE 'drop\s+(table|database|schema)|truncate\s+table|db:reset' && level3 "刪資料"
  printf '%s' "$c" | grep -qE 'sops\s+(-e|--encrypt|edit)|\.gitlab-ci\.yml|\.github/workflows' && level3 "改 CI / secrets"
  # 第二級
  printf '%s' "$c" | grep -qE '(^|\s|&&|;)git\s+push(\s|$)' && level2 push "git push"
  printf '%s' "$c" | grep -qE '(glab mr (create|update)|gh pr (create|edit))' && level2 mr "開 / 改 MR"
  printf '%s' "$c" | grep -qE 'db:migrate|drizzle-kit (migrate|push)|alembic upgrade' && level2 migrate "本機 migrate"
  printf '%s' "$c" | grep -qE '(^|\s|&&|;)rm\s+-(r|f|rf|fr)\b' && level2 delete "刪檔（rm -r/-f）"
  printf '%s' "$c" | grep -qE '(pnpm (add|install|i)\b|npm (install|i|ci)\b|uv (add|sync)|pip install|yarn add|brew install)' && level2 install "裝套件"
  printf '%s' "$c" | grep -qE '(^|\s|&&|;)git\s+rebase(\s|$)' && level2 rebase "git rebase"
  printf '%s' "$c" | grep -qE '(curl|wget|http)\s+' && ! printf '%s' "$c" | grep -qE 'localhost|127\.0\.0\.1|litellm\.agentory\.cc' && level2 external "呼叫外部 API"
  [ "$GRANTED" = 1 ] && allow
  exit 0
fi

if [ "$tool" = "Edit" ] || [ "$tool" = "Write" ]; then
  [ -n "$file" ] || exit 0
  case "$file" in
    *.gitlab-ci.yml|*/.github/workflows/*|*secrets*|*.sops.*|*/sops/*) level3 "改 CI / secrets（${file}）" ;;
    *.env.example) exit 0 ;;
    *.env|*.env.*) level2 env "寫 $file"; allow ;;
  esac
fi
exit 0
