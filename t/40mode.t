#!/usr/bin/perl -w

use Test::More tests => 19;

use File::Temp qw(tempfile);
use Archive::Ar;

my ($fh, $file) = tempfile(UNLINK => 1);
my $data;
while (<DATA>) {
    next if /^#/;
    chomp;
    $data .= unpack('u', $_);
}
print $fh $data;
close $fh;

my $ar = Archive::Ar->new($file);
isa_ok($ar, 'Archive::Ar', 'object');
is_deeply([$ar->list_files], [qw(odd even)], 'list_files');

my $filedata = $ar->get_content('odd');
is($filedata->{name}, 'odd',		'file1, filedata/name');
is($filedata->{uid}, 2202,		'file1, filedata/uid');
is($filedata->{gid}, 2988,		'file1, filedata/gid');
is($filedata->{mode}, 0100644,		'file1, filedata/mode');
is($filedata->{date}, 1255532835,	'file1, filedata/date');
is($filedata->{size}, 11,		'file1, filedata/size');
is($filedata->{data}, "oddcontent\n",	'file1, filedata/data');

$filedata = $ar->get_content('even');
is($filedata->{name}, 'even',		'file2, filedata/name');
is($filedata->{uid}, 2202,		'file2, filedata/uid');
is($filedata->{gid}, 2988,		'file2, filedata/gid');
is($filedata->{mode}, 0100644,		'file2, filedata/mode');
is($filedata->{date}, 1255532831,	'file2, filedata/date');
is($filedata->{size}, 12,		'file2, filedata/size');
is($filedata->{data}, "evencontent\n",	'file2, filedata/data');

my ($nfh, $nfile) = tempfile(UNLINK => 1);

print $nfh $ar->write;
close $nfh;

my $nar = Archive::Ar->new($nfile);

is_deeply([$ar->list_files], [$nar->list_files], 'write/read, list_files');
is_deeply($ar->get_content('odd'), $nar->get_content('odd'), 'write/read, file1 compare');
is_deeply($ar->get_content('even'), $nar->get_content('even'), 'write/read, file2 compare');

__END__
#
# Uuencoded ar archive produced by ar(1).
#
M(3QA<F-H/@IO9&0@("`@("`@("`@("`@,3(U-34S,C@S-2`@,C(P,B`@,CDX
M."`@,3`P-C0T("`Q,2`@("`@("`@8`IO9&1C;VYT96YT"@IE=F5N("`@("`@
M("`@("`@,3(U-34S,C@S,2`@,C(P,B`@,CDX."`@,3`P-C0T("`Q,B`@("`@
1("`@8`IE=F5N8V]N=&5N=`H`
