use strict;
use warnings;
use Test::More tests => 1;
use Archive::Ar;

my $ar = Archive::Ar->new;
isa_ok $ar, 'Archive::Ar';
