"""授權閘門信任的授權資料（合併核准、這張卡的 grants、這次的 once）的唯一讀寫口。

存在 <OPSX_STATE_DIR>-protected/authz.json，不在任何 session 的 additionalDirectories 內，沙盒內寫不進去。
寫入只准從沙盒外來：opsx merge、opsx answer、授權閘門 hook。dispatch.json 裡的同名欄位閘門一律不看。
格式與 dispatch.json 相同：{"<repo>/<slug>": {"merge_approved", "merge_approved_at", "grants": [], "once": []}}。
"""
from __future__ import annotations

import os

import jsonfile


def protected_dir(state_dir: str) -> str:
    return os.path.normpath(state_dir) + "-protected"


def path(state_dir: str) -> str:
    return os.path.join(protected_dir(state_dir), "authz.json")


def load(state_dir: str) -> dict:
    """缺檔、壞檔都回 {}：沒有授權。"""
    return jsonfile.load(path(state_dir))


def update(state_dir: str, mutate) -> dict:
    d = protected_dir(state_dir)
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
        return jsonfile.update(path(state_dir), mutate)
    except PermissionError as e:
        raise SystemExit("opsx: 受保護位置 %s 寫不進去（%s）；這個動作要在沙盒外跑（終端機或看板），不能在 agent 的沙盒裡跑" % (d, e))
