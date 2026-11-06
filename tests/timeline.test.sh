#!/usr/bin/env bash
# opsx timeline：舊列、表頭、時區、archive、--since、last-seen、讀不了的檔（specs/opsx-log「時間軸」）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo Agentory-AI)"; C="$R/openspec/changes"
mkdir -p "$C/x" "$C/archive/2026-11-06-y" "$C/bad"
{
  printf 'ts\tphase\tdecision\twhy\tevidence\tresult\n'
  printf '2026-11-06T05:00:00Z\tapply\t用 sqlite\t快\tbench\tok\n'
  printf '2026-11-06T11:34:07+08:00\t指派給 claude\tdispatched\n'
  printf '2026-11-06T12:30:00+08:00\tclaude\t替你決定\t選 B\t\n'
  printf '亂寫的一行\n'
} > "$C/x/decisions.tsv"
printf '2026-11-05T10:00:00+08:00\t你\t已合併\t合了\tabc\n' > "$C/archive/2026-11-06-y/decisions.tsv"
printf '\xff\xfe\n' > "$C/bad/decisions.tsv"

opsx timeline --root "$FX" > "$FX/tl.json" || fail "timeline rc"
python3 -I - "$FX/tl.json" <<'PY' || fail "timeline shape"
import json, sys
d = json.load(open(sys.argv[1]))
ev = d["events"]
texts = [e["text"] for e in ev]
# 表頭不產生 event；新格式、舊列（含 UTC Z）、沒時間的亂行、archive 都在
assert not any(t.startswith("ts\tphase") for t in texts), texts
assert len(ev) == 5, texts
# 依時間由新到舊；05:00Z 等於 13:00+08:00，是最新的
assert [e["ts"] for e in ev[:4]] == ["2026-11-06T05:00:00Z", "2026-11-06T12:30:00+08:00",
                                     "2026-11-06T11:34:07+08:00", "2026-11-05T10:00:00+08:00"], [e["ts"] for e in ev]
new = ev[1]
assert (new["who"], new["tag"], new["text"], new["source"]) == ("claude", "替你決定", "選 B", "decisions"), new
old = ev[2]
assert (old["who"], old["tag"]) == (None, "其他"), old
assert old["text"] == "2026-11-06T11:34:07+08:00\t指派給 claude\tdispatched", old
utc = ev[0]
assert utc["tag"] == "其他" and utc["text"].startswith("2026-11-06T05:00:00Z\tapply"), utc
arch = ev[3]
assert (arch["slug"], arch["archived"], arch["tag"]) == ("y", True, "已合併"), arch
# 時間解析不了的排最後，ts 為 null
junk = ev[4]
assert (junk["ts"], junk["tag"], junk["text"]) == (None, "其他", "亂寫的一行"), junk
# 讀不了的檔記進 errors，不毀整份
assert len(d["errors"]) == 1 and "bad" in d["errors"][0]["source"], d["errors"]
assert d["last_seen"] is None
PY

# --since：只留比它新的；沒有時間的列不留
opsx timeline --root "$FX" --since 2026-11-06T12:00:00+08:00 > "$FX/since.json" || fail "since rc"
python3 -I -c '
import json,sys
ev=json.load(open(sys.argv[1]))["events"]
assert [e["ts"] for e in ev]==["2026-11-06T05:00:00Z","2026-11-06T12:30:00+08:00"],ev' "$FX/since.json" || fail "since filter"
assert_rc 2 opsx timeline --root "$FX" --since 昨天

# last-seen
mkdir -p "$OPSX_STATE_DIR"; printf '2026-11-06T09:00:00+08:00\n' > "$OPSX_STATE_DIR/last-seen"
assert_eq "$(opsx timeline --root "$FX" | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["last_seen"])')" "2026-11-06T09:00:00+08:00"
echo ok
