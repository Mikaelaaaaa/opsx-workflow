#!/usr/bin/env bash
# opsx note <slug> [--repo <top>] <text…>：把派工指示寫進卡的 inbox.md「## 派工指示」段；卡已派出就再送進負責它的 agent。
# note_append 也給 opsx dispatch --note 用。specs/dispatch-note/spec.md。

# shellcheck source=/dev/null
source "$OPSX_ROOT/bin/lib/route.sh"

# 多行會長出新行，frontmatter() 用 ^key: 搜整份 inbox，一行 `source: …` 就會被讀成卡的 frontmatter，所以壓成一行。
# 用 splitlines 而不是 tr：note_append 讀檔也用 splitlines，它還認 \v \f U+2028 等，漏掉的下次追加會被切成新行
note_oneline() { # <text>：印壓成一行、去頭尾空白的文字
  "$OPSX_PY" -I -c 'import sys; print(" ".join(sys.argv[1].splitlines()).strip())' "$1"
}

note_append() { # <卡目錄> <已壓成一行的文字>：追加一條 `- <時間> <文字>` 到 ## 派工指示 段尾，沒有這段就建在檔尾
  OPSX_N_FILE="$1/inbox.md" OPSX_N_LINE="- $(now_iso) $2" "$OPSX_PY" -I - <<'PY'
import os, re, sys
sys.path.insert(0, os.path.join(os.environ["OPSX_ROOT"], "bin", "lib")); import safefile
path, line = os.environ["OPSX_N_FILE"], os.environ["OPSX_N_LINE"]
with safefile.CardLock(os.path.dirname(path)):
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        lines = []
    head = next((i for i, l in enumerate(lines) if re.fullmatch(r"## 派工指示\s*", l)), None)
    if head is None:
        while lines and not lines[-1].strip():
            lines.pop()
        lines += ([""] if lines else []) + ["## 派工指示", "", line]
    else:
        end = next((i for i in range(head + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
        last = max([i for i in range(head + 1, end) if lines[i].strip()] or [head])
        lines.insert(last + 1, line)
        if last == head:
            lines.insert(last + 1, "")
    safefile.write_atomic(path, "\n".join(lines) + "\n")
PY
}

note_dispatched() { # <repo> <slug>：dispatch.json 有這張卡且 mode 不是 stopped 時回 0，否則 1
  OPSX_KEY="$1/$2" "$OPSX_PY" -I - "$OPSX_STATE_DIR/dispatch.json" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.environ["OPSX_ROOT"], "bin", "lib")); import jsonfile
e = jsonfile.load(sys.argv[1]).get(os.environ["OPSX_KEY"])
sys.exit(0 if e and e.get("mode") != "stopped" else 1)
PY
}

opsx_note() {
  local slug="" top="" text=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) top="$2"; shift 2 ;;
      --) shift; text+=("$@"); break ;;
      --*) die "note: 不認得的選項 $1（指示以 -- 開頭請先放一個 --）" ;;
      *) if [ -z "$slug" ]; then slug="$1"; else text+=("$1"); fi; shift ;;
    esac
  done
  [ -n "$slug" ] && [ ${#text[@]} -gt 0 ] || die "note: 用法 opsx note <slug> [--repo <path>] <文字…>"
  printf '%s' "$slug" | grep -qE '^[a-z][a-z0-9_-]{0,31}$' || die "note: slug 要符合 [a-z][a-z0-9_-]{0,31}：$slug"
  [ -n "$top" ] || top="$(git_toplevel)"
  [ -n "$top" ] || die "note: 不在 git repo 裡，或給 --repo"
  top="$(cd "$top" && pwd -P)"
  local repo d note; repo="$(basename "$top")"; d="$top/openspec/changes/$slug"
  [ -d "$d" ] || die "note: 沒有這張卡：$d"
  note="$(note_oneline "${text[*]}")"
  [ -n "$note" ] || die "note: 指示壓成一行後是空的"
  refuse_if_handed "$repo" "$slug" note
  note_append "$d" "$note" || die "note: 寫不進 $d/inbox.md"

  if note_dispatched "$repo" "$slug"; then
    local route via; route="$(card_route "$repo" "$slug")" || die "讀不懂 dispatch.json，不知道話要送給誰"; via="${route#*$'\t'}"
    # 不帶原文：router 會在 prompt 裡比對 tdd、audit、/pause 這類關鍵詞，指示原文會把這一句導到別的流程
    runtime_prompt "$repo/$slug" "${via:+[$slug] }有新的派工指示，Read inbox.md 的 ## 派工指示" nowait >/dev/null \
      || die "note: inbox.md 已寫，但 herdr agent prompt 失敗；agent 下一句 prompt 會從 router 看到有指示"
    say "note: $slug 的派工指示已寫進 inbox.md，已送進 agent"
  else
    say "note: $slug 的派工指示已寫進 inbox.md；這張卡沒派出，派出時 router 會提醒 agent 讀"
  fi
}
