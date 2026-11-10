#!/usr/bin/env perl
# 讀 stdin 的 Bash 指令，印出「真的會執行的部分」（指令骨架）。hooks/_lib.sh 的 cmd_skeleton 呼叫它。
#   heredoc 本體移除；單、雙引號字串換成空字串，但不含空白的（"main"、'--force'）去掉引號保留內容，
#   因為那是被引號包住的參數，不是一段文字；
#   例外（字串裡的內容真的會執行，遞迴處理）：bash|sh|zsh -c <字串>、eval <字串>、雙引號內的 $(…) 與反引號。
#   遞迴超過 MAX_DEPTH 層就把該段原樣留下：寧可誤擋，不放行。
use strict;
use warnings;

use constant MAX_DEPTH => 3;
my $SQ = "'";
my $RUNS_STRING = qr/(?:\b(?:bash|sh|zsh)\s+-\w*c\w*\s+|\beval\s+)$/;

# 回傳 $s 從 $i（指向 "$("）開始的括號配對內容與結束位置
sub paren_body {
    my ($s, $i) = @_;
    my $depth = 0;
    for (my $j = $i + 1 ; $j < length $s ; $j++) {
        my $c = substr $s, $j, 1;
        $depth++ if $c eq '(';
        if ($c eq ')') {
            $depth--;
            return (substr($s, $i + 2, $j - $i - 2), $j) if $depth == 0;
        }
    }
    return (substr($s, $i + 2), length $s);
}

# 雙引號字串內真的會執行的部分：$(…) 與反引號
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

sub skeleton {
    my ($s, $depth) = @_;
    return $s if $depth > MAX_DEPTH;
    $s =~ s/(?<!<)(<<-?\s*([\x27"]?)(\w+)\2[^\n]*)\n.*?\n[ \t]*\3[ \t]*(?:\n|\z)/$1\n/sg;
    my ($out, $i, $n) = ('', 0, length $s);
    while ($i < $n) {
        my $c = substr $s, $i, 1;
        if ($c eq '\\') { $out .= substr($s, $i, 2); $i += 2; next }
        my $prev = $i ? substr($s, $i - 1, 1) : '';
        if ($c eq $SQ && $prev !~ /[\w\\]/) {
            my $end = index $s, $SQ, $i + 1;
            if ($end >= 0) {
                my $body = substr $s, $i + 1, $end - $i - 1;
                $out .= $out =~ $RUNS_STRING ? " ; " . skeleton($body, $depth + 1) . " ; " : $body =~ /^\S*$/ ? $body : "''";
                $i = $end + 1;
                next;
            }
        }
        if ($c eq '"') {
            my $end = $i + 1;
            while ($end < $n && substr($s, $end, 1) ne '"') { $end += substr($s, $end, 1) eq '\\' ? 2 : 1 }
            if ($end < $n) {
                my $body = substr $s, $i + 1, $end - $i - 1;
                if ($out =~ $RUNS_STRING) {
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
