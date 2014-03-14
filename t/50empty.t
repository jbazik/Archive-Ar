#!/usr/bin/perl -w

use Test::More tests => 2;

my $zero_ar =
   "!<arch>\nzero            1394762259  1000  1000  100644  0         `\n";

use Archive::Ar();

my $a = Archive::Ar->new();
$a->read_memory($zero_ar);
my $d = $a->get_content('zero');
isnt("$d->{size}", '', 'size is not empty string');
is("$d->{size}", "0", 'size is zero');
