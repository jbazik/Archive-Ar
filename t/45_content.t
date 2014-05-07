use strict;
use warnings;

use Test::More tests => 4;
use File::Temp qw( tempdir );
use File::Spec;

use Archive::Ar;

my $dir = tempdir( CLEANUP => 1 );
my $fn  = File::Spec->catfile($dir, 'foo.ar');

note "fn = $fn";

my $content = do {local $/ = undef; <DATA>};
open my $fh, '>', $fn or die "$fn: $!\n";
binmode $fh;
print $fh $content;
close $fh;

my $ar = Archive::Ar->new($fn);
isa_ok $ar, 'Archive::Ar';
is $ar->get_content("foo.txt")->{data}, "hi there\n";
is $ar->get_content("bar.txt")->{data}, "this is the content of bar.txt\n";
is $ar->get_content("baz.txt")->{data}, "and again.\n";


__DATA__
!<arch>
foo.txt         1384344423  1000  1000  100644  9         `
hi there

bar.txt         1384344423  1000  1000  100644  31        `
this is the content of bar.txt

baz.txt         1384344423  1000  1000  100644  11        `
and again.

