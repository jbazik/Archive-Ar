use strict;
use warnings;
use Test::More tests => 3;
use File::Temp qw( tempdir );
use File::Spec;
use Archive::Ar;

my $dir = tempdir( CLEANUP => 1 );
my $fn  = File::Spec->catfile($dir, 'foo.ar');

note "fn = $fn";

do { 
  open my $fh, '>', $fn;
  binmode $fh;
  while(<DATA>) {
    chomp;
    print $fh unpack('u', $_);
  }
  close $fh;
};

subtest 'filename' => sub {
  plan tests => 3;
  
  my $ar = Archive::Ar->new($fn);
  isa_ok $ar, 'Archive::Ar';

  is_deeply scalar $ar->list_files, [map { "$_.txt" } qw( foo bar baz )], "scalar context";
  is_deeply [$ar->list_files],      [map { "$_.txt" } qw( foo bar baz )], "list context";
};

subtest 'glob' => sub {
  plan tests => 3;

  open my $fh, '<', $fn;
  my $ar = Archive::Ar->new($fh);
  isa_ok $ar, 'Archive::Ar';

  is_deeply scalar $ar->list_files, [map { "$_.txt" } qw( foo bar baz )], "scalar context";
  is_deeply [$ar->list_files],      [map { "$_.txt" } qw( foo bar baz )], "list context";
};

subtest 'memory' => sub {
  plan tests => 4;

  open my $fh, '<', $fn;
  my $data = do { local $/; <$fh> };
  close $fh;
  
  my $ar = Archive::Ar->new;
  isa_ok $ar, 'Archive::Ar';
  is $ar->read_memory($data), 242;

  is_deeply scalar $ar->list_files, [map { "$_.txt" } qw( foo bar baz )], "scalar context";
  is_deeply [$ar->list_files],      [map { "$_.txt" } qw( foo bar baz )], "list context";
};


__DATA__
M(3QA<F-H/@IF;V\N='AT("`@("`@("`@,3,X-#,T-#0R,R`@,3`P,"`@,3`P
M,"`@,3`P-C0T("`Y("`@("`@("`@8`IH:2!T:&5R90H*8F%R+G1X="`@("`@
M("`@(#$S.#0S-#0T,C,@(#$P,#`@(#$P,#`@(#$P,#8T-"`@,S$@("`@("`@
M(&`*=&AI<R!I<R!T:&4@8V]N=&5N="!O9B!B87(N='AT"@IB87HN='AT("`@
M("`@("`@,3,X-#,T-#0R,R`@,3`P,"`@,3`P,"`@,3`P-C0T("`Q,2`@("`@
1("`@8`IA;F0@86=A:6XN"@H`
