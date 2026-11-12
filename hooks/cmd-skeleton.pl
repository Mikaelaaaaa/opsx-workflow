#!/usr/bin/env perl
# 讀 stdin 的 Bash 指令，印出「真的會執行的部分」（指令骨架）。hooks/_lib.sh 的 cmd_skeleton 呼叫它。
#   單、雙引號字串換成空字串，但不含空白的（"main"、'--force'）去掉引號保留內容，
#   因為那是被引號包住的參數，不是一段文字；
#   heredoc 本體移除，但餵給直譯器（bash、sh、psql、ssh 等）的本體會被執行，整段保留；沒加引號的 delimiter 其本體內的 $(…) 也會執行，一併保留；
#   例外（字串裡的內容真的會執行，遞迴處理）：bash|sh|zsh|dash|ksh（可帶任意旗標）-c <字串>、eval <字串>、雙引號內的 $(…) 與反引號；
#   $'…' 原樣保留。
#   遞迴超過 MAX_DEPTH 層就把該段原樣留下：寧可誤擋，不放行。
use strict;
use warnings;
use FindBin;

require "$FindBin::Bin/cmd-lex.pl";    # skip_dq、paren_body

use constant MAX_DEPTH => 3;
my $SQ = "'";
my $RUNS_STRING = qr/(?:\b(?:bash|sh|zsh|dash|ksh)(?:\s+-\S+)*?\s+-\w*c\w*\s+|\beval\s+)$/;
my $EXECUTOR = qr/\b(?:bash|sh|zsh|dash|ksh|eval|source|psql|mysql|sqlite3|ssh|python[0-9]?|node|perl|ruby)\b/;

# 雙引號字串或沒加引號的 heredoc 本體內真的會執行的部分：$(…) 與反引號
sub substitutions {
    my ($body) = @_;
    my @subs;
    my $i = 0;
    while ($i < length $body) {
        my $c = substr $body, $i, 1;
        if ($c eq '\\') { $i += 2; next }
        if ($c eq '$' && substr($body, $i + 1, 1) eq '(') {
            my ($inner, $end) = paren_body($body, $i);
            push @subs, $inner;
            $i = $end + 1;
            next;
        }
        if ($c eq '`') {
            my $end = index $body, '`', $i + 1;
            $end = length $body if $end < 0;
            push @subs, substr($body, $i + 1, $end - $i - 1);
            $i = $end + 1;
            next;
        }
        $i++;
    }
    return @subs;
}

# 一段 heredoc 換成什麼：本體餵給直譯器就整段保留，否則移除；沒加引號的 delimiter 要把本體內的 $(…) 留下
sub heredoc {
    my ($lead, $prefix, $opener, $quote, $body, $depth) = @_;
    my $out = "$lead$prefix$opener\n";
    return $out . "$body\n" if "$prefix$opener" =~ $EXECUTOR;
    $out .= " ; " . skeleton($_, $depth + 1) . " ; " for $quote eq '' ? substitutions($body) : ();
    return $out;
}

# $s 的 $pos 這個位置在 shell 眼中是不是一般的指令文字：不在引號或註解裡，也沒有被反斜線跳脫
sub in_code {
    my ($s, $pos) = @_;
    my $i = 0;
    while ($i < $pos) {
        my $c = substr $s, $i, 1;
        if ($c eq '\\') { $i += 2; next }
        if ($c eq $SQ) {
            my $end = index $s, $SQ, $i + 1;
            return 0 if $end < 0 || $end >= $pos;
            $i = $end + 1;
            next;
        }
        if ($c eq '"') {
            my $end = skip_dq($s, $i);
            return 0 if $end >= $pos;
            $i = $end + 1;
            next;
        }
        if ($c eq '#' && ($i == 0 || substr($s, $i - 1, 1) =~ /[\s;&|()]/)) {
            my $end = index $s, "\n", $i;
            return 0 if $end < 0 || $end >= $pos;
            $i = $end + 1;
            next;
        }
        $i++;
    }
    return $i == $pos;    # 最後一次跳脫把 $pos 吃掉了：這個位置是被跳脫的字元
}

# heredoc 開頭：只認 in_code 的位置；本體到單獨一行的結尾字為止。整段換成 heredoc() 的結果
sub strip_heredocs {
    my ($s, $depth) = @_;
    my ($out, $copied) = ('', 0);
    while ($s =~ /(?<!<)<<-?\s*([\x27"]?)(\w+)\1/g) {
        my ($start, $opener_end, $quote, $tag) = ($-[0], $+[0], $1, $2);
        next unless in_code($s, $start);
        my $nl = index $s, "\n", $opener_end;
        next if $nl < 0;
        next unless substr($s, $nl + 1) =~ /\A(.*?)\n[ \t]*\Q$tag\E[ \t]*(?:\n|\z)/s;
        my ($body, $consumed) = ($1, $+[0]);
        my $line_start = $start;
        $line_start-- while $line_start > 0 && substr($s, $line_start - 1, 1) ne "\n";
        $out .= substr($s, $copied, $line_start - $copied);
        $out .= heredoc('', substr($s, $line_start, $start - $line_start), substr($s, $start, $nl - $start), $quote, $body, $depth);
        $copied = $nl + 1 + $consumed;
        pos($s) = $copied;
    }
    return $out . substr($s, $copied);
}

sub skeleton {
    my ($s, $depth) = @_;
    return $s if $depth > MAX_DEPTH;
    $s = strip_heredocs($s, $depth);
    my ($out, $i, $n) = ('', 0, length $s);
    while ($i < $n) {
        my $c = substr $s, $i, 1;
        if ($c eq '\\') {
            my $next = substr $s, $i + 1, 1;
            # c\ommit：bash 把 \o 當 o。含 / 的字是路徑，保留跳脫，commit 閘門靠它認出讀不出來的目錄
            if ($next =~ /^\w$/ && $out !~ m{[^\s]*/[^\s]*\z}) { $out .= $next }
            elsif ($next eq "\n") { }                     # 行尾續行：bash 把反斜線與換行整個拿掉
            else { $out .= "\\$next" }
            $i += 2;
            next;
        }
        my $prev = $i ? substr($s, $i - 1, 1) : '';
        if ($c eq $SQ && $prev =~ /[\w]/) {
            # g''it、g'i't：緊貼著字的單引號片段是指令字的一部分，沒有空白就去掉引號
            my $end = index $s, $SQ, $i + 1;
            my $body = $end < 0 ? '' : substr($s, $i + 1, $end - $i - 1);
            if ($end >= 0 && $body =~ /^[^\s\\\$`"']*$/) { $out .= $body; $i = $end + 1; next }
        }
        if ($c eq $SQ && $prev !~ /[\w\\]/) {
            my $end = index $s, $SQ, $i + 1;
            if ($end >= 0) {
                my $body = substr $s, $i + 1, $end - $i - 1;
                if ($prev eq '$') { $out .= "$SQ$body$SQ" }
                elsif (substr($out, -80) =~ $RUNS_STRING) { $out .= " ; " . skeleton($body, $depth + 1) . " ; " }
                else { $out .= $body =~ /^\S*$/ ? $body : "''" }
                $i = $end + 1;
                next;
            }
        }
        if ($c eq '"') {
            my $end = skip_dq($s, $i);
            if ($end < $n) {
                my $body = substr $s, $i + 1, $end - $i - 1;
                if (substr($out, -80) =~ $RUNS_STRING) {
                    (my $plain = $body) =~ s/\\(["\\\$`])/$1/g;
                    $out .= " ; " . skeleton($plain, $depth + 1) . " ; ";
                } elsif ($body =~ /^[^\s\\\$`]*$/) {
                    $out .= $body;
                } else {
                    $out .= '""';
                    $out .= " ; " . skeleton($_, $depth + 1) . " ; " for substitutions($body);
                }
                $i = $end + 1;
                next;
            }
        }
        $out .= $c;
        $i++;
    }
    return $out;
}

local $/;
my $cmd = <STDIN> // '';
print skeleton($cmd, 0);
