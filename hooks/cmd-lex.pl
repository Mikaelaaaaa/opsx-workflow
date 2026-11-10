# cmd-skeleton.pl 與 cmd-containers.pl 共用的掃描函式（require 進來，不單獨執行）。
use strict;
use warnings;

my $SQ = "'";

# 雙引號字串從 $i 開始，回傳結尾引號的位置；字串內的 $(…) 整段跳過（裡面可以有自己的引號）
sub skip_dq {
    my ($s, $i) = @_;
    my $j = $i + 1;
    while ($j < length $s && substr($s, $j, 1) ne '"') {
        my $c = substr $s, $j, 1;
        if ($c eq '\\') { $j += 2 }
        elsif ($c eq '$' && substr($s, $j + 1, 1) eq '(') { my (undef, $close) = paren_body($s, $j); $j = $close + 1 }
        else { $j++ }
    }
    return $j;
}

# 回傳 $s 從 $i（指向 "$("）開始的括號配對內容與結束位置；括號內的引號字串整段跳過
sub paren_body {
    my ($s, $i) = @_;
    my ($depth, $j) = (0, $i + 1);
    while ($j < length $s) {
        my $c = substr $s, $j, 1;
        if ($c eq '\\') { $j += 2; next }
        if ($c eq $SQ) { my $e = index $s, $SQ, $j + 1; $j = ($e < 0 ? length $s : $e) + 1; next }
        if ($c eq '"') { $j = skip_dq($s, $j) + 1; next }
        $depth++ if $c eq '(';
        if ($c eq ')') {
            $depth--;
            return (substr($s, $i + 2, $j - $i - 2), $j) if $depth == 0;
        }
        $j++;
    }
    return (substr($s, $i + 2), length $s);
}

1;
