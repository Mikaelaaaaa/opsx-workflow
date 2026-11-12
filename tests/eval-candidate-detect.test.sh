#!/usr/bin/env bash
# 每個 skill 的每個 eval 都要有「候選者碰到工作 repo 以外就判不過」的 assertion。
# 驗收：openspec/changes/me-20261111-1824/specs/eval-candidate-detect/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

python3 -I - "$OPSX_ROOT" <<'PY' || fail "eval 缺候選者偵測 assertion"
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
missing = []
for name in ["apply", "explore", "grill", "logic-map", "propose", "review"]:
    data = json.loads((root / "skills" / name / "evals" / "evals.json").read_text(encoding="utf-8"))
    for ev in data["evals"]:
        if not any("outside the work repo" in a for a in ev["assertions"]):
            missing.append("%s eval %s" % (name, ev["id"]))
assert not missing, "缺：" + "、".join(missing)
print("eval-candidate-detect ok")
PY
