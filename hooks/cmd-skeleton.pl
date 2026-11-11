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

# heredoc 的分隔字照 bash：整個字去掉引號與反斜線之後的樣子（'E'F、E\OF 都是 EF 與 EOF，EOF-X 就是 EOF-X）
sub unquote_word {
    my ($w) = @_;
    my ($out, $i) = ('', 0);
    while ($i < length $w) {
        my $c = substr $w, $i, 1;
        if ($c eq '\\') { $out .= substr($w, $i + 1, 1); $i += 2; next }
        if ($c eq $SQ || $c eq '"') {
            my $end = index $w, $c, $i + 1;
            $end = length $w if $end < 0;
            $out .= substr $w, $i + 1, $end - $i - 1;
            $i = $end + 1;
            next;
        }
        $out .= $c;
        $i++;
    }
    return $out;
}

my $HEREDOC_WORD = qr/(?>(?:[^\s;&|<>()\\'"]|\\.|'[^']*'|"[^"]*")+)/;

sub heredoc_of {
    my ($lead, $prefix, $opener, $word, $body, $depth) = @_;
    return heredoc($lead, $prefix, $opener, $word =~ /[\x27"\\]/ ? $SQ : '', $body, $depth);
}

sub skeleton {
    my ($s, $depth) = @_;
    return $s if $depth > MAX_DEPTH;
    $s =~ s/(^|\n)([^\n]*?)(?<!<)(<<-?[ \t]*($HEREDOC_WORD)[^\n]*)\n(.*?)\n[ \t]*(??{ quotemeta unquote_word($4) })[ \t]*(?:\n|\z)/heredoc_of($1, $2, $3, $4, $5, $depth)/sge;
    my ($out, $i, $n) = ('', 0, length $s);
    while ($i < $n) {
        my $c = substr $s, $i, 1;
        if ($c eq '\\') { $out .= substr($s, $i, 2); $i += 2; next }
        my $prev = $i ? substr($s, $i - 1, 1) : '';
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
