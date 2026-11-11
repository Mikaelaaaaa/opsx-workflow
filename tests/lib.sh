#!/usr/bin/env bash
# 測試共用：fixture repo、斷言。source 它。
set -u
: "${OPSX_ROOT:?OPSX_ROOT 未設}"
FX="$(mktemp -d "${TMPDIR:-/tmp}/opsx-test.XXXXXX")"
export OPSX_STATE_DIR="$FX/state"
export OPSX_BIN_DIR="$FX/bin"
export HERDR_ENV=""          # status.sh 的 pane metadata 鏡像認它；collect 不看它
# 測試裡永遠不碰真 herdr：PATH 最前放一支一定失敗的；要成功的測試自己 use_fakes herdr（放得更前）
mkdir -p "$FX/failbin"; printf '#!/usr/bin/env bash\necho "herdr: test isolation, no real herdr" >&2\nexit 1\n' > "$FX/failbin/herdr"; chmod +x "$FX/failbin/herdr"
# 每個測試的 nohup 都是假的、一律失敗：agent 沙盒 pane 裡的真 nohup 就是這樣，產品程式不能靠它起背景程序
printf '#!/usr/bin/env bash\nexec bash "%s/tests/fakes/nohup" "$@"\n' "$OPSX_ROOT" > "$FX/failbin/nohup"; chmod +x "$FX/failbin/nohup"
export OPSX_NONINTERACTIVE=1 # init 不問問題
export TZ=Asia/Taipei
# init --global 會裝 launchd job：測試永遠不寫真的 ~/Library/LaunchAgents、不叫真的 launchctl。
# 預設當成沒有 launchctl（略過）；要測安裝的檔案自己 use_fakes launchctl 再設 OPSX_LAUNCHCTL=launchctl。
export OPSX_LAUNCH_AGENTS_DIR="$FX/LaunchAgents"
export OPSX_LAUNCHCTL="$FX/no-launchctl"
# init 會改使用者層 Claude Code settings：測試永遠指到 fixture，不碰真的 settings.json。
export CLAUDE_CONFIG_DIR="$FX/claude-config"
trap 'rm -rf "$FX"' EXIT
# opsx init --global 會寫的 python 路徑；opsx 和 hooks 沒有它就不跑
mkdir -p "$OPSX_STATE_DIR"; python3 -I -c 'import sys; print(sys.executable)' > "$OPSX_STATE_DIR/python"
# 測試 helper 自己叫的 python3 也走那一支，不經 pyenv shim（每次多 250 ms 左右，一個檔幾十次）
PATH="$FX/failbin:$(dirname "$(cat "$OPSX_STATE_DIR/python")"):$PATH"; export PATH

fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2] got [$1]${3:+ — $3}"; }
assert_file() { [ -f "$1" ] || fail "missing file $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "should not exist: $1"; }
assert_grep() { grep -q -- "$1" "$2" || fail "'$1' not in $2:
$(cat "$2")"; }
assert_not_grep() { ! grep -q -- "$1" "$2" || fail "'$1' should not be in $2"; }
assert_rc() { local want=$1; shift; "$@" >/dev/null 2>&1; local got=$?; [ $got -eq $want ] || fail "rc $got != $want: $*"; }
# 把 tests/fakes/<name> 放上 PATH（透過可執行的 shim，沙盒不准 chmod plugin 目錄）：use_fakes herdr glab gh
use_fakes() {
  mkdir -p "$FX/fakebin"
  local f; for f in "$@"; do printf '#!/usr/bin/env bash\nexec bash "%s/tests/fakes/%s" "$@"\n' "$OPSX_ROOT" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
  export PATH="$FX/fakebin:$PATH"
}

# 建一個有 .git 的 fixture repo，可選 remote
mk_repo() { # mk_repo <name> [remote-url]
  local d="$FX/$1"; mkdir -p "$d"; git -C "$d" init -q .
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  git -C "$d" commit -q --allow-empty -m init
  [ -n "${2:-}" ] && git -C "$d" remote add origin "$2"
  true
  ( cd "$d" && pwd -P )   # /tmp 在 macOS 是 /private/tmp 的 symlink，統一用實體路徑比
}
assert_dir() { [ -d "$1" ] || fail "missing dir $1"; }
# 建一個 branch 對到卡的 repo：feat/<slug>/mikaela + openspec/changes/<slug>/
mk_change() { # mk_change <repo-dir> <slug>
  mkdir -p "$1/openspec/changes/$2"
  printf 'schema: opsx\ncreated: 2026-11-05\n' > "$1/openspec/changes/$2/.openspec.yaml"
  git -C "$1" checkout -q -b "feat/$2/mikaela" 2>/dev/null || git -C "$1" checkout -q "feat/$2/mikaela"
}
# 跑過 opsx init 的 fixture repo：openspec/ 加 opsx schema，openspec new change --schema opsx 能用
mk_opsx_repo() { # mk_opsx_repo <name>
  local d; d="$(mk_repo "$1")"
  ( cd "$d" && openspec init --tools none "$d" >/dev/null 2>&1 )
  ( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/python.sh"; opsx_python_load; source "$OPSX_ROOT/bin/lib/init.sh"; install_schema "$d" >/dev/null 2>&1 ) || fail "mk_opsx_repo: schema 裝不起來"
  printf '%s' "$d"
}
