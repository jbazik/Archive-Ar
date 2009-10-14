#!/usr/bin/perl -w

use Test::More (tests => 2);
use strict;

use Archive::Ar();

my ($padding_archive) = new Archive::Ar();
$padding_archive->add_data("test.txt", "here\n");
my ($archive_results) = $padding_archive->write();
ok(length($archive_results) == 74, "Archive::Ar pads un-even number of bytes successfully\n");
$padding_archive = new Archive::Ar();
$padding_archive->add_data("test.txt", "here1\n");
$archive_results = $padding_archive->write();
ok(length($archive_results) == 74, "Archive::Ar pads even number of bytes successfully\n");
