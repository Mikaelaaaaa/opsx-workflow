#!/usr/bin/env perl
# 讀 stdin 的指令文字（hooks/cmd-containers.pl 的輸出），印出 shell 解析完參數之後的樣子，給 push 的 force / main 檢查比對用：
#   引號與反斜線去掉（"main"、\main、'+feat/x' 跟 main、+feat/x 一樣）；$'…'、$"…" 的 $ 去掉；
#   行尾反斜線續行併成同一行；引號外的換行當 ;；引號內的 ; & | 換行改成 _（它們不是段落分隔）。
# 不展開 ANSI-C 跳脫，也不處理變數：認不得的寫法留在文字裡，比對不到就是放行這一層，交給後面的檢查。
use strict;
use warnings;

local $/;
my $s = <STDIN> // '';
my ($out, $quote, $i, $n) = ('', '', 0, length $s);
while ($i < $n) {
    my $c = substr $s, $i, 1;
    $i++;
    if ($quote ne '') {
        if ($c eq $quote) { $quote = ''; next }
        if ($quote eq '"' && $c eq '\\' && $i < $n) { $c = substr $s, $i++, 1 }
        $out .= $c =~ /[;&|\n]/ ? '_' : $c;
        next;
    }
    if ($c eq "'" || $c eq '"') { $quote = $c; next }
    if ($c eq '\\') {
        my $next = $i < $n ? substr($s, $i++, 1) : '';
        $out .= $next unless $next eq "\n";
        next;
    }
    if ($c eq '$' && $i < $n && substr($s, $i, 1) =~ /^["']$/) { next }
    $out .= $c eq "\n" ? ';' : $c;
}
print $out;
