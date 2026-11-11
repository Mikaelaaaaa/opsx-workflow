# opsx coordinate 測試共用的 fixture：fake opsx / git / openspec / gh / herdr，加上寫 collect JSON 與跑一輪的 helper。
# 由 tests/coordinate-*.test.sh source，不是測試檔本身（run.sh 只跑 *.test.sh）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo demo)"
mkdir -p "$R/openspec/changes"
use_fakes opsx git openspec gh herdr
export OPSX_FAKE_LOG="$FX/fake.log" OPSX_TEST_COLLECT_JSON="$FX/collect.json"
LOG="$OPSX_STATE_DIR/coordinator.log"; MEMO="$OPSX_STATE_DIR/coordinator-memo.json"; DISP="$OPSX_STATE_DIR/dispatch.json"

# cards '<卡的 JSON 陣列，只寫跟預設不同的欄位>'：寫成 opsx collect 的輸出
cards() {
  python3 -I - "$R" "$1" > "$OPSX_TEST_COLLECT_JSON" <<'PY'
import json, sys
top, given = sys.argv[1], json.loads(sys.argv[2])
base = {"repo": "demo", "kind": "dev", "stage": "apply", "section": "待指派", "archived": False,
        "waiting": None, "open_gates": [], "dispatch": None, "agent_status": None, "mr": None}
out = [{**base, **c, "path": "%s/openspec/changes/%s" % (top, c["slug"])} for c in given]
print(json.dumps({"repo_paths": {"demo": top}, "cards": out, "errors": []}, ensure_ascii=False))
PY
}
mkcard() { local s; for s in "$@"; do mkdir -p "$R/openspec/changes/$s"; printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/$s/tasks.md"; done; }
round() { : > "$OPSX_FAKE_LOG"; : > "$LOG"; bash "$OPSX_ROOT/bin/opsx" coordinate "$@" > "$FX/out" 2>&1; }
count() { grep -cE -- "$1" "$OPSX_FAKE_LOG" || true; }
memo_get() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], {}).get(sys.argv[3], ""))' "$MEMO" "$1" "$2"; }
D='{"mode":"autopilot","agent":"claude","pane":"w1:p1","drive_pid":null}'
