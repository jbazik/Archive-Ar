#!/usr/bin/perl -w

use Test::More tests => 9;
use Test::MockObject;

BEGIN {
        chdir 't' if -d 't';
        use lib '../blib/lib', 'lib/', '..';
}

my $mod = "Archive::Ar";
my $mock = new Test::MockObject;
my $ar;

use_ok($mod);
can_ok($mod, "new");


$mock->set_false("read");
local *Archive::Ar::read;
*Archive::Ar::read = sub { return $mock->read(); };

ok($ar = new Archive::Ar, "The new operator without any arguments should always succeed");
ok($ar = Archive::Ar->new(), "Class-method new() without any arguments");
ok(!$mock->called("read"), "Archive::Ar's read() shouldn't be called if there are no arguments");

$ar = new Archive::Ar("myfilename");

ok(!$ar, "The new operator with a filename should fail if read fails");
ok($mock->called("read"), "Object creation should call read() if it is given a filename");
$mock->clear();

my $GLOB = *STDIN;
$ar = new Archive::Ar($GLOB);

ok(!$ar, "The new operator with a GLOB should fail if read fails");
ok($mock->called("read"), "Object creation should call read() if it is given a file GLOB");



# The rest will have to be done with integration tests, as there is no good fake filesystem mod

$mock->clear();



