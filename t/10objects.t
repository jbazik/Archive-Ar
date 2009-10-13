#!/usr/bin/perl -w

use Test::More tests => 13;

BEGIN {
        chdir 't' if -d 't';
        use lib '../blib/lib', 'lib/', '..';
}

my $mod = "Archive::Ar";

use_ok("File::Spec");
use_ok("Time::Local");
use_ok($mod);

can_ok($mod, "new");
can_ok($mod, "list_files");
can_ok($mod, "read");
can_ok($mod, "read_memory");
can_ok($mod, "list_files");
can_ok($mod, "add_files");
can_ok($mod, "add_data");
can_ok($mod, "write");
can_ok($mod, "get_content");
can_ok($mod, "DEBUG");
