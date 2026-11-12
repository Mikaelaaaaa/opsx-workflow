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
use constant MAX_BYTES => 32768;
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

# 一次走過整串，回傳等長的字串：第 i 個字元是 '1' 表示 $s 的第 i 個位置在 shell 眼中是一般的指令文字，
# '0' 表示在引號（含 $'…'，裡面的 \' 是字面引號）或註解裡，或是被反斜線跳脫的字元。線性，heredoc 開頭一個一個查表
sub code_mask {
    my ($s) = @_;
    my $n = length $s;
    my $mask = '1' x $n;
    my $i = 0;
    while ($i < $n) {
        my $c = substr $s, $i, 1;
        if ($c eq '\\') { substr($mask, $i + 1, 1) = '0' if $i + 1 < $n; $i += 2; next }
        my $end;
        if ($c eq '$' && substr($s, $i + 1, 1) eq $SQ) {
            $end = $i + 2;
            $end += substr($s, $end, 1) eq '\\' ? 2 : 1 while $end < $n && substr($s, $end, 1) ne $SQ;
        } elsif ($c eq $SQ) {
            $end = index $s, $SQ, $i + 1;
        } elsif ($c eq '"') {
            $end = skip_dq($s, $i);
        } elsif ($c eq '#' && ($i == 0 || substr($s, $i - 1, 1) =~ /[\s;&|()]/)) {
            $end = index $s, "\n", $i;
        } else {
            $i++;
            next;
        }
        $end = $n - 1 if $end < 0 || $end >= $n;    # 沒結尾的引號或註解一路到尾
        substr($mask, $i, $end - $i + 1) = '0' x ($end - $i + 1);
        $i = $end + 1;
    }
    return $mask;
}

# heredoc 的分隔字照 bash：整個字去掉引號與反斜線之後的樣子（'E'F、E\OF 都是 EF 與 EOF，EOF-X 就是 EOF-X）
sub unquote_word {
    my ($w) = @_;
    my ($out, $i) = ('', 0);
    while ($i < length $w) {
        my $c = substr $w, $i, 1;
        if ($c eq '\\') { $out .= substr($w, $i + 1, 1); $i += 2; next }
        if ($c eq '$' && substr($w, $i + 1, 1) =~ /^[\x27"]$/) { $i++; next }   # $'EOF'、$"EOF"：$ 不算分隔字的一部分
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

my $HEREDOC_WORD = qr/(?>(?:\$?'[^']*'|\$?"[^"]*"|[^\s;&|<>()\\'"]|\\.)+)/;

# 由左到右把每一段 heredoc 換成 heredoc() 的結果；只認 in_code 的開頭（引號、註解、跳脫內的不算）。
# 開頭沒有結尾行的原樣留下，繼續找後面的
sub strip_heredocs {
    my ($s, $depth) = @_;
    my ($out, $copied) = ('', 0);
    my $mask = code_mask($s);
    while ($s =~ /(?<!<)<<-?[ \t]*($HEREDOC_WORD)/g) {
        my ($start, $opener_end, $word) = ($-[0], $+[0], $1);
        my $nl = index $s, "\n", $opener_end;
        next if $nl < 0;
        next unless substr($mask, $start, 1) eq '1';
        # $'…\x41…' 的跳脫 bash 會展開，這裡不展開：算不準分隔字就不剝本體（fail-closed）
        next if $word =~ /\$['"]/ && $word =~ /\\/;
        my $delim = unquote_word($word);
        next unless substr($s, $nl + 1) =~ /\A(.*?)\n[ \t]*\Q$delim\E[ \t]*(?:\n|\z)/s;
        my ($body, $consumed) = ($1, $+[0]);
        my $line_start = $start;
        $line_start-- while $line_start > 0 && substr($s, $line_start - 1, 1) ne "\n";
        $out .= substr($s, $copied, $line_start - $copied);
        $out .= heredoc('', substr($s, $line_start, $start - $line_start), substr($s, $start, $nl - $start), $word =~ /[\x27"\\]/ ? $SQ : '', $body, $depth);
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
            # c\ommit、g\it：bash 把 \o 當 o。參數位置含 / 的字是路徑，保留跳脫，commit 閘門靠它認出讀不出來的目錄；
            # 指令位置（行首或 ; & | ( 之後）的字一律還原，絕對路徑的 /usr/bin/g\it 也是
            # 只看 $out 最後 256 字：每個反斜線都掃整串 $out 會變成二次方
            my $tail = substr $out, -256;
            my $cmdpos = (length($out) <= 256 && $tail =~ /\A\s*[^\s;&|()]*\z/) || $tail =~ /[;&|(\n]\s*[^\s;&|()]*\z/;
            if ($next =~ /^\w$/ && ($cmdpos || $tail !~ m{[^\s]*/[^\s]*\z})) { $out .= $next }
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
# shortcut: 沒結尾的 heredoc 開頭每個都重掃後面全文（二次方），hook 逾時等於放行，所以超過上限就原樣輸出（引號與 heredoc 本體都不去除，比對只會更嚴）；真有超過 32KB 的指令，分次執行或請人放行
print length($cmd) > MAX_BYTES ? $cmd : skeleton($cmd, 0);
