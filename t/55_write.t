use strict;
use warnings;

use Test::More tests => 4;
use File::Temp qw( tempdir );
use File::Spec;

use Archive::Ar qw(GNU BSD);

my $dir = tempdir( CLEANUP => 1 );
note "dir = $dir";

subtest 'write filename' => sub {
  plan tests => 2;
  
  my $ar = before();
  my $fn = File::Spec->catfile($dir, "libfoo.a");
  
  my $size = $ar->write($fn);
  note "size = $size";
  ok $size, 'write';
  
  undef $ar;
  
  check_content(Archive::Ar->new($fn));
};

subtest 'write string' => sub {
  plan tests => 2;
  
  my $content = before()->write;
  
  note "size = " . length $content;
  ok defined $content, 'write';
  
  
  my $ar = Archive::Ar->new;
  $ar->read_memory($content);
  
  check_content($ar);
};

subtest 'write bsd' => sub {
  plan tests => 2;
  
  my $ar = before();
  my $fn = File::Spec->catfile($dir, "libfoo.a");
  
  my $size = $ar->write($fn, {type=>BSD});
  note "size = $size";
  ok $size, 'write';
  
  undef $ar;
  
  check_content(Archive::Ar->new($fn));
};

subtest 'write gnu' => sub {
  plan tests => 2;
  
  my $ar = before();
  my $fn = File::Spec->catfile($dir, "libfoo.a");
  
  my $size = $ar->write($fn, {type=>GNU});
  note "size = $size";
  ok $size, 'write';
  
  undef $ar;
  
  check_content(Archive::Ar->new($fn));
};

sub before
{
  my $ar = Archive::Ar->new;
  $ar->add_data("foo.txt", "foo content", {
    uid  => 101,
    gid  => 202,
    date => 12345679,
    mode => 0100640,
  });
  $ar->add_data("bar.txt", "bar content\nbar content\n", {
    uid  => 303,
    gid  => 404,
    date => 123456798,
    mode => 0100600,
  });
  $ar;
}

sub check_content
{
  my $ar = shift;
  
  subtest 'content' => sub {
    plan tests => 3;
    is_deeply scalar $ar->list_files, [qw( foo.txt bar.txt )], 'contains files foo and bar';
    is_deeply $ar->get_content('foo.txt'), { name => 'foo.txt', date => 12345679, uid => 101, gid => 202, mode => 0100640, data => "foo content", size => 11 }, "foo content";
    is_deeply $ar->get_content('bar.txt'), { name => 'bar.txt', date => 123456798, uid => 303, gid => 404, mode => 0100600, data => "bar content\nbar content\n", size => 24 }, "bar content";
  };
}
