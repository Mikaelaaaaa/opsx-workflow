#!/usr/bin/env bash
# hooks/cmd-skeleton.pl：切開指令字的引號與跳脫要還原；引號、註解、跳脫內的 heredoc 記號不吞後續行。
# 驗收：openspec/changes/agent-20261111-2326/specs/command-gate-bypass/spec.md「指令骨架去掉切開指令字的引號與跳脫」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/hooks/cmd-skeleton.pl"
skel() { printf '%s' "$1" | perl "$SK"; }
has_commit() { case "$(skel "$1")" in *"git commit"*) return 0 ;; *) return 1 ;; esac; }

# --- 切開指令字：還原成 git commit ---
has_commit "g''it commit -m x" || fail "g''it：$(skel "g''it commit -m x")"
has_commit "git commi''t -m x" || fail "git commi''t：$(skel "git commi''t -m x")"
has_commit 'git c\ommit -m x' || fail 'git c\ommit：'"$(skel 'git c\ommit -m x')"
has_commit '"git" commit -m x' || fail '"git" commit'
has_commit "g'i't commit -m x" || fail "g'i't：$(skel "g'i't commit -m x")"
has_commit "$(printf 'git \\\ncommit -m x')" || fail "行尾續行的 git commit：$(skel "$(printf 'git \\\ncommit -m x')")"

# --- 反例：不是 git commit 的字不能被湊成 git commit ---
has_commit "echo 'git commit' x" && fail "單引號字串內的 git commit 不是指令：$(skel "echo 'git commit' x")"
has_commit "echo don't commit it's" && fail "撇號不是引號：$(skel "echo don't commit it's")"

# --- heredoc 記號在引號、註解、跳脫內：後一行的 commit 仍在骨架裡 ---
has_commit "$(printf 'echo "<<EOF"\ngit commit -m x\nEOF')" || fail "雙引號內的 <<EOF 吞掉了 commit"
has_commit "$(printf "echo '<<EOF'\ngit commit -m x\nEOF")" || fail "單引號內的 <<EOF 吞掉了 commit"
has_commit "$(printf 'true # cat <<EOF\ngit commit -m x\nEOF')" || fail "註解內的 <<EOF 吞掉了 commit"
has_commit "$(printf 'echo \\<<EOF\ngit commit -m x\nEOF')" || fail '跳脫的 \<<EOF 吞掉了 commit'

# --- 正例：真的 heredoc，本體仍被去掉 ---
has_commit "$(printf 'cat <<EOF\ngit commit -m x\nEOF')" && fail "真 heredoc 的本體要去掉：$(skel "$(printf 'cat <<EOF\ngit commit -m x\nEOF')")"
has_commit "$(printf 'cat <<-EOF\n\tgit commit -m x\n\tEOF')" && fail "<<- 的 heredoc 本體要去掉"
# 餵給直譯器的 heredoc 本體會被執行，整段保留
has_commit "$(printf 'bash <<EOF\ngit commit -m x\nEOF')" || fail "餵給 bash 的 heredoc 本體要保留"
# 同一行有真 heredoc、前面還有被引號包住的 <<
has_commit "$(printf 'echo "a <<b" ; cat <<EOF\ngit commit -m x\nEOF')" && fail "引號內的 << 之後的真 heredoc 本體要去掉"
# --- R1.1：$'…\'…' 裡的 \' 是字面引號，<<EOF 還在字串裡，後一行的 commit 仍在骨架 ---
has_commit $'echo $\'\\\'<<EOF\'\ngit commit -m x\nEOF' || fail "ANSI-C 引號內的 <<EOF 吞掉了 commit：$(skel $'echo $\'\\\'<<EOF\'\ngit commit -m x\nEOF')"
# --- R1.1：一串沒有結尾的 <<a 不能讓骨架變慢（hook 逾時等於放行）---
big="$(perl -e 'print "git commit -m x; :\n", "<<a\n" x 8000')"   # 換行讓每個開頭都走到 code_mask 查表
t0=$SECONDS; skel "$big" >/dev/null; elapsed=$((SECONDS - t0))
[ "$elapsed" -le 3 ] || fail "32KB 的一串 <<a 骨架花了 ${elapsed} 秒（要線性）"
has_commit "$big" || fail "那串 <<a 之前的 git commit 不能不見"

# --- R1.2：指令位置的 \<字母> 還原，含 ; && 之後與絕對路徑的 git；參數位置的路徑字保留跳脫 ---
has_commit 'cd /tmp;g\it commit -m x' || fail '; 之後的 g\it：'"$(skel 'cd /tmp;g\it commit -m x')"
has_commit 'cd /tmp&&g\it commit -m x' || fail '&& 之後的 g\it：'"$(skel 'cd /tmp&&g\it commit -m x')"
has_commit '/usr/bin/g\it commit -m x' || fail '絕對路徑的 g\it：'"$(skel '/usr/bin/g\it commit -m x')"
case "$(skel 'git -C /tmp/a\b commit -m x')" in *'/tmp/a\b'*) ;; *) fail "參數位置的路徑字要保留跳脫：$(skel 'git -C /tmp/a\b commit -m x')" ;; esac
echo "cmd-skeleton ok"
