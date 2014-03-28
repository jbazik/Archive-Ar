#!/usr/bin/perl -w

use Test::More tests => 16;

my $mod = "Archive::Ar";

use_ok($mod);

can_ok($mod, "new");
can_ok($mod, "read");
can_ok($mod, "read_memory");
can_ok($mod, "contains_file");
can_ok($mod, "extract");
can_ok($mod, "remove");
can_ok($mod, "list_files");
can_ok($mod, "add_files");
can_ok($mod, "add_data");
can_ok($mod, "write");
can_ok($mod, "get_content");
can_ok($mod, "get_data");
can_ok($mod, "get_handle");
can_ok($mod, "error");
can_ok($mod, "DEBUG");
