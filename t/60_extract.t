use strict;
use warnings;

use Test::More tests => 11;
use File::Temp qw(tempdir);
use Cwd;

my $wd = cwd;
END { chdir $wd; }

use Archive::Ar;

my $dir = tempdir(CLEANUP => 1);
my $content = do {local $/; <DATA>};

my $ar  = Archive::Ar->new();
ok $ar->read_memory($content), 'read_memory' or diag $ar->error;
chdir $dir or die;
ok $ar->extract, 'extract';
my @st = lstat 'foo.txt';
ok @st, 'stat';
is $st[2], 0100644, 'mode 1 matches';
is $st[7], 9, 'size 1 matches';
is $st[9], 1384344423, 'mtime 1 matches';
if (open my $fd, 'foo.txt') {
    local $/ = undef;
    my $content = <$fd>;
    is $content, "hi there\n", 'content 1 matches';
}
else {
    fail "open 'foo.txt'";
}
@st = lstat 'bar.txt';
is $st[2], 0100750, 'mode 2 matches';
is $st[7], 31, 'size 2 matches';
is $st[9], 1384344423, 'mtime 2 matches';
if (open my $fd, 'bar.txt') {
    local $/ = undef;
    my $content = <$fd>;
    is $content, "this is the content of bar.txt\n", 'content 2 matches';
}
else {
    fail "open 'bar.txt'";
}

__DATA__
!<arch>
foo.txt         1384344423  1000  1000  100644  9         `
hi there

bar.txt         1384344423  1000  1000  100750  31        `
this is the content of bar.txt

