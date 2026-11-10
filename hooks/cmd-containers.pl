#!/usr/bin/env perl
# 讀 stdin 的 Bash 指令原文，印出「第三級比對用的文字」：只把三種容器的資料部分換成空字串，其餘一字不動。
# hooks/_lib.sh 的 cmd_l3text 呼叫它。三種容器（grill D1）：
#   1. git commit 的 -m / --message 字串
#   2. opsx answer … -- 後面的答案字串
#   3. cat 或 tee 的寫檔 heredoc 本體
# 認不得的寫法一律留在文字裡，所以第三級會比對到它（fail-closed）。
# 字串只有在不會被 shell 展開時才算資料：單引號內一律是資料；雙引號內含 $ 或反引號就不扣，
# 唯一例外是 git commit 標準寫法 "$(cat <<'DELIM' … DELIM)"（帶引號的 delimiter，本體不展開）。
use strict;
use warnings;

my $PLAIN = qr/[^\s"'`\$;&|<>()]/;
my $DQ_DATA = qr/"(?:[^"\\\$`]|\\.)*"/s;
my $SQ_DATA = qr/'[^']*'/;
my $CAT_HEREDOC_STRING = qr/"\$\(cat\s*<<-?'(\w+)'[ \t]*\n.*?\n[ \t]*\1[ \t]*\n[ \t]*\)"/s;

# 從目前位置取一個資料字串，回傳 '""'；不是資料就回 undef 且位置不動
sub take_string {
    my ($sref, $allow_cat_heredoc) = @_;
    return '""' if $$sref =~ /\G(?:$SQ_DATA|$DQ_DATA)/gc;
    return '""' if $allow_cat_heredoc && $$sref =~ /\G$CAT_HEREDOC_STRING/gc;
    return undef;
}

# git commit … -m "<data>" -m '<data>'：旗標之間只吃沒有引號與展開的字，遇到別的就停
sub scrub_commit {
    my ($s) = @_;
    my $out = '';
    while ($s =~ /\G(.*?\bgit\s+(?:-C\s+\S+\s+)?commit\b)/gcs) {
        $out .= $1;
        while (1) {
            if ($s =~ /\G(\s+(?:-m|--message)(?:\s+|=))/gc) {
                $out .= $1;
                my $data = take_string(\$s, 1);
                $out .= $data if defined $data;
            }
            elsif ($s =~ /\G(\s+(?:--?[\w-]+(?:=$PLAIN*)?|[^\s"'`\$;&|<>()-]$PLAIN*))/gc) {
                $out .= $1;
            }
            else { last }
        }
    }
    return $out . substr($s, pos($s) // 0);
}

# opsx answer <slug> <gate> -- "<data>"
sub scrub_answer {
    my ($s) = @_;
    my $out = '';
    while ($s =~ /\G(.*?\bopsx\s+answer\b(?:\s+$PLAIN+)*?\s+--\s+)/gcs) {
        $out .= $1;
        my $data = take_string(\$s, 0);
        $out .= $data if defined $data;
    }
    return $out . substr($s, pos($s) // 0);
}

# cat / tee 單獨一行的 heredoc：本體是資料。opener 那一行不能有 pipe、串接、展開、第二個 heredoc；
# delimiter 沒加引號時，本體不能有 $( 或反引號（shell 會展開）
sub heredoc_text {
    my ($lead, $prefix, $opener, $quote, $body, $terminator) = @_;
    my $expands = $quote eq '' && $body =~ /\$\(|`/;
    return $lead . $prefix . $opener . ($expands ? $body : '') . $terminator;
}

sub scrub_heredoc {
    my ($s) = @_;
    $s =~ s{
        (^|\n)
        ([^\n<|`\$()="']*?(?:&&|;)[ \t]*|[ \t]*)
        ((?:cat|tee)\b[^\n<|;&`\$()]*<<-?\s*(['"]?)(\w+)\4[^\n<|;&`\$()]*\n)
        (.*?)
        (\n[ \t]*\5[ \t]*(?:\n|\z))
    }{heredoc_text($1, $2, $3, $4, $6, $7)}gsex;
    return $s;
}

local $/;
my $cmd = <STDIN> // '';
print scrub_heredoc(scrub_answer(scrub_commit($cmd)));
