#!/usr/bin/env bash
# agent 啟動參數：dispatch 與 relaunch 共用，交給 `herdr agent start … -- "${LAUNCH_ARGS[@]}"`。
# 結果放在全域陣列 LAUNCH_ARGS：bash 函式回傳不了陣列，走 stdout 的話含空白的路徑會被拆開。呼叫完要馬上用。

launch_args() { # <agent> <model> <mode> <repo> <herdr 名> <主 repo>
  local agent="$1" model="$2" mode="$3" repo="$4" name="$5" top="$6"
  LAUNCH_ARGS=()
  # claude 兩種模式都帶 --settings；--permission-mode 與 allow / deny 只有 autopilot 才有。
  # settings 檔按模式分名，重派不會蓋掉 pane 還沒關的另一個模式那份
  if [ "$agent" = claude ]; then
    LAUNCH_ARGS+=(--model "$model")
    local settings="$OPSX_STATE_DIR/settings/$repo-$name-$mode.json"; ensure_dir "$(dirname "$settings")"
    write_settings "$settings" "$repo" "$top/openspec" "$mode" "$name"
    if [ "$mode" != interactive ]; then LAUNCH_ARGS+=(--permission-mode dontAsk); fi   # dontAsk：不在 allow 的直接拒絕不跳框；跳框會讓 herdr 判 blocked，drive 送不進下一句
    LAUNCH_ARGS+=(--settings "$settings")
    # Claude Code 的沙盒只准寫 working directories；卡的檔在主 repo 的 openspec/（worktree 裡沒有），hook 消耗 once 與 status 鏡像寫 state dir。
    # 旗標只活在這個行程；重啟後 --settings 有沒有被帶回、additionalDirectories 還在不在，尚未實測（add-dir-lost 1.1）
    LAUNCH_ARGS+=(--add-dir "$top/openspec" --add-dir "$OPSX_STATE_DIR")
  else
    if [ "$mode" = interactive ]; then LAUNCH_ARGS+=(-a on-request -s workspace-write); else LAUNCH_ARGS+=(-a never -s workspace-write); fi
    # 卡的檔在主 repo 的 openspec/，不在 worktree；沒有這兩個，規則叫它寫的 gates.md / status.json 寫不進
    LAUNCH_ARGS+=(--add-dir "$top/openspec" --add-dir "$OPSX_STATE_DIR")
  fi
}

write_settings() { # <file> <repo> <主 repo openspec 目錄> <mode> <herdr 名>：autopilot 直接做那級 allow，永遠要人那級 deny；repo 永遠的授權也進 allow。interactive 只寫可寫目錄。兩種模式都寫 env OPSX_CARD，opsx new 靠它認出 dispatch 的 agent
  OPSX_REPO="$2" OPSX_SD="$OPSX_STATE_DIR" OPSX_MODE="$4" OPSX_NAME="$5" "$OPSX_PY" -I - "$1" "$3" <<'PY'
import json,os,sys,tomllib
sys.path.insert(0, os.path.join(os.environ["OPSX_ROOT"], "bin", "lib")); import safefile
sd=os.environ["OPSX_SD"]; repo=os.environ["OPSX_REPO"]
dirs=[sys.argv[2],sd]
env={"OPSX_CARD":os.environ["OPSX_NAME"]}
if os.environ["OPSX_MODE"]=="interactive":
    safefile.write_atomic(sys.argv[1], json.dumps({"env":env,"permissions":{"additionalDirectories":dirs}},indent=2))
    sys.exit(0)
allow=["Read","Edit","Write","Glob","Grep","Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git add:*)","Bash(git commit:*)","Bash(git checkout:*)","Bash(git worktree:*)",
       "Bash(pnpm test:*)","Bash(pnpm vitest:*)","Bash(TEST_DATABASE_URL=* pnpm vitest:*)","Bash(TEST_DATABASE_URL=* pnpm test:*)","Bash(pnpm build:*)","Bash(pnpm lint:*)","Bash(pnpm typecheck:*)","Bash(npx vitest:*)","Bash(pytest:*)","Bash(uv run:*)","Bash(ruff:*)","Bash(go test:*)",
       "Bash(openspec:*)","Bash(opsx:*)","Bash(ls:*)","Bash(cat:*)","Bash(grep:*)","Bash(rg:*)","Bash(find:*)","Bash(node:*)","Bash(python3:*)",
       "Bash(jq:*)","Bash(head:*)","Bash(tail:*)","Bash(wc:*)","Bash(sed -n:*)","Bash(diff:*)","Bash(sort:*)","Bash(bash tests/:*)","Bash(herdr agent:*)","Bash(herdr pane read:*)","Bash(orca status:*)","Bash(orca repo list:*)","Bash(orca repo add:*)","Bash(orca repo set:*)","Bash(orca worktree list:*)","Bash(orca tab create:*)","Bash(orca terminal read:*)",
       "Bash(git show:*)","Bash(git branch:*)","Bash(git rev-parse:*)","Bash(git fetch:*)","Bash(git merge-base:*)","Bash(git merge:*)","Bash(git remote:*)","Bash(mkdir:*)",
       "Bash(glab mr view:*)","Bash(glab mr list:*)","Bash(glab mr diff:*)","Bash(glab ci:*)","Bash(gh pr view:*)","Bash(gh pr checks:*)","Bash(gh pr list:*)"]
# merge 不在 deny：settings 的 deny 蓋得過 hook 的放行，所以 merge 交給 opsx-grant-gate.sh 的 merge_gate 單獨把關；
# 放進 allow 是為了閘門放行那一次不再跳 Claude Code 自己的權限框。
allow += ["Bash(glab mr merge:*)", "Bash(gh pr merge:*)"]
deny=["Bash(git push --force:*)","Bash(git push -f:*)","Bash(deploy.sh:*)","Bash(sops:*)","Bash(rm -rf /:*)"]
try:
    g=tomllib.load(open(os.path.join(sd,"grants.toml"),"rb")).get("repos",{}).get(repo,{})
    if g.get("push"): allow.append("Bash(git push:*)")
    if g.get("mr"): allow+=["Bash(glab mr create:*)","Bash(glab mr update:*)","Bash(gh pr create:*)","Bash(gh pr edit:*)","Bash(glab issue note:*)","Bash(glab issue comment:*)","Bash(gh issue comment:*)"]   # gh pr comment 與 glab api 不進 allow：規則放行形狀之外的寫法（-R other/repo、merge?x=/notes/1）
    if g.get("migrate"): allow+=["Bash(pnpm db:migrate:*)","Bash(pnpm --filter * run db:migrate:*)","Bash(alembic upgrade:*)"]
except FileNotFoundError: pass
safefile.write_atomic(sys.argv[1], json.dumps({"env":env,"permissions":{"allow":allow,"deny":deny,"additionalDirectories":dirs}},indent=2))
PY
}
