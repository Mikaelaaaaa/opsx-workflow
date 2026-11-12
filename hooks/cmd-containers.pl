#!/usr/bin/env perl
# 讀 stdin 的 Bash 指令原文，印出「第三級比對用的文字」：只把三種容器的資料部分換成空字串，其餘一字不動。
# hooks/_lib.sh 的 cmd_l3text 呼叫它。三種容器（grill D1）：
#   1. git commit 的 -m / --message 字串
#   2. opsx answer 的引號字串引數（答案文字）
#   3. cat 或 tee 的寫檔 heredoc 本體
# 由左到右掃描，只在「引號、註解、命令替換之外的指令開頭」認容器：開頭是文字起點，或 ; & | ( { 換行之後。
# 其餘一律原樣複製（引號字串整段複製，不往裡面找），認不得的寫法留在文字裡，所以第三級會比對到它（fail-closed）。
# 字串只有在不會被 shell 展開時才算資料：單引號內一律是資料；雙引號內含 $ 或反引號就不扣，
# 唯一例外是 git commit 標準寫法 "$(cat <<'DELIM' … DELIM)"（帶引號的 delimiter，結尾行之後緊接 )"）。
# shortcut: [已評估] 指令超過 MAX_BYTES 就整段原樣輸出（不扣任何容器）；heredoc 開頭的結尾行搜尋對沒有結尾的重複 opener 是 O(N²)，hook 逾時等同放行，所以用長度上限擋；真的要在第三級字樣旁寫超過 32KB 的檔，改成分次寫或請人放行
use strict;
use warnings;
use FindBin;

require "$FindBin::Bin/cmd-lex.pl";    # skip_dq

use constant MAX_BYTES => 32768;
my $PLAIN = qr/[^\s"'`\$;&|<>()\\]/;
my $DQ_DATA = qr/"(?:[^"\\\$`]|\\.)*"/s;
my $SQ_DATA = qr/'[^']*'/;
my $CAT_HEREDOC_STRING = qr/"\$\(cat\s*<<-?'(\w+)'[ \t]*\n(?:(?![ \t]*\1[ \t]*\n)[^\n]*\n)*[ \t]*\1[ \t]*\n[ \t]*\)"/;
# cat / tee 可能被換掉（函式、alias、PATH）：有這些寫法就不認 heredoc 容器
my $SHADOW = qr/\b(?:cat|tee)\s*\(\)|\bfunction\s+(?:cat|tee)\b|\balias\s+(?:cat|tee)\b|\bunalias\b|\bPATH=/;

# 從目前位置取一個資料字串，回傳 '""'；不是資料就回 undef 且位置不動
sub take_string {
    my ($sref, $allow_cat_heredoc) = @_;
    return '""' if $$sref =~ /\G(?:$SQ_DATA|$DQ_DATA)/gc;
    return '""' if $allow_cat_heredoc && $$sref =~ /\G$CAT_HEREDOC_STRING/gc;
    return undef;
}

# git commit … -m "<data>" -m '<data>'：旗標之間只吃沒有引號與展開的字，遇到別的就停
sub commit_container {
    my ($sref) = @_;
    return unless $$sref =~ /\G(git\s+(?:-C\s+\S+\s+)?commit\b)/gc;
    my $out = $1;
    while (1) {
        if ($$sref =~ /\G(\s+(?:-m|--message)(?:\s+|=))/gc) {
            $out .= $1;
            my $data = take_string($sref, 1);
            $out .= $data if defined $data;
        }
        elsif ($$sref =~ /\G(\s+(?:--?[\w-]+(?:=$PLAIN*)?|[^\s"'`\$;&|<>()\\-]$PLAIN*))/gc) {
            $out .= $1;
        }
        else { last }
    }
    return ($out, pos($$sref));
}

# opsx answer <slug> [--gate <id>] [--grant …] ['<text>' …]：不帶展開的引號字串引數是答案文字
sub answer_container {
    my ($sref) = @_;
    return unless $$sref =~ /\G(opsx\s+answer\b)/gc;
    my $out = $1;
    while (1) {
        if ($$sref =~ /\G(\s+$PLAIN+)/gc) { $out .= $1 }
        elsif ($$sref =~ /\G(\s+)(?=["'])/gc) {
            $out .= $1;
            my $data = take_string($sref, 0);
            last unless defined $data;
            $out .= $data;
        }
        else { last }
    }
    return ($out, pos($$sref));
}

# cat / tee 單獨一個 opener 行的 heredoc：本體是資料。opener 行不能有 pipe、串接、展開、反斜線續行、第二個 heredoc；
# delimiter 要是完整的一個字（'W'、"W"、W），沒加引號時本體不能有 $( 或反引號（shell 會展開）；
# 結尾行照 bash：整行等於 delimiter（<<- 可有前導 tab），取第一個
sub heredoc_container {
    my ($sref) = @_;
    return unless $$sref =~ /\G((?:cat|tee)\b[^\n<|;&`\$()\\]*<<(-?)[ \t]*(?:'(\w+)'|"(\w+)"|(\w+))(?=[ \t>\n])[^\n<|;&`\$()\\]*\n)/gc;
    my ($opener, $dash, $word, $quoted) = ($1, $2, $3 // $4 // $5, defined $3 || defined $4);
    my $tab = $dash ? '\t*' : '';
    my $body_start = pos($$sref);
    return unless $$sref =~ /\G(?:(?=$tab\Q$word\E(?:\n|\z))|.*?\n(?=$tab\Q$word\E(?:\n|\z)))/gcs;
    my $body = substr $$sref, $body_start, pos($$sref) - $body_start;
    return unless $$sref =~ /\G($tab\Q$word\E)(?:\n|\z)/gc;
    return if !$quoted && $body =~ /\$\(|`/;
    return ($opener . $1 . "\n", pos($$sref));
}

sub container_at {
    my ($sref, $i, $heredocs_ok) = @_;
    for my $recognise (\&commit_container, \&answer_container, ($heredocs_ok ? \&heredoc_container : ())) {
        pos($$sref) = $i;
        my ($text, $end) = $recognise->($sref);
        return ($text, $end) if defined $text;
    }
    return;
}

# 從 $i 的引號開始，複製整段（含結尾引號；沒結尾就複製到底），回傳複製的文字與下一個位置
sub copy_quoted {
    my ($s, $i, $end) = @_;
    $end = length($s) - 1 if $end < 0 || $end >= length $s;
    return (substr($s, $i, $end - $i + 1), $end + 1);
}

sub scan {
    my ($s) = @_;
    my ($out, $i, $n, $at_cmd) = ('', 0, length $s, 1);
    my $heredocs_ok = $s !~ $SHADOW;
    while ($i < $n) {
        my $c = substr $s, $i, 1;
        if ($at_cmd && $c !~ /\s/) {
            my ($text, $end) = container_at(\$s, $i, $heredocs_ok);
            if (defined $text) { $out .= $text; $i = $end; $at_cmd = 0; next }
        }
        my ($copied, $next);
        if ($c eq '\\') { ($copied, $next) = (substr($s, $i, 2), $i + 2) }
        elsif ($c eq "'") { ($copied, $next) = copy_quoted($s, $i, index($s, "'", $i + 1)) }
        elsif ($c eq '`') { ($copied, $next) = copy_quoted($s, $i, index($s, '`', $i + 1)) }
        elsif ($c eq '"') { ($copied, $next) = copy_quoted($s, $i, skip_dq($s, $i)) }
        if (defined $copied) { $out .= $copied; $i = $next; $at_cmd = 0; next }
        $at_cmd = $c =~ /[;&|\n({]/ ? 1 : $c =~ /\s/ ? $at_cmd : 0;
        $out .= $c;
        $i++;
    }
    return $out;
}

local $/;
my $cmd = <STDIN> // '';
print length($cmd) > MAX_BYTES ? $cmd : scan($cmd);
