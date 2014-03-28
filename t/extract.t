#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 8;
use File::Temp qw(tempdir);
use Cwd;

my $wd = cwd;
END { chdir $wd; }

use Archive::Ar;

my $dir = tempdir(CLEANUP => 1);
my $content = do {local $/; <DATA>};

my $ar  = Archive::Ar->new();
ok $ar->read_memory($content) or diag $ar->error;
chdir $dir or die;
ok $ar->extract;
my @st = lstat 'foo.txt';
ok @st;
is $st[2], 0100644;
is $st[4], 1000;
is $st[5], 1000;
is $st[7], 9;
is $st[9], 1384344423;

__DATA__
!<arch>
foo.txt         1384344423  1000  1000  100644  9         `
hi there

bar.txt         1384344423  1000  1000  100644  31        `
this is the content of bar.txt

