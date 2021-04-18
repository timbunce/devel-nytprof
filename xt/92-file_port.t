#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

eval "require Test::Portability::Files;";
plan skip_all => "Test::Portability::Files required for testing filename portability. ${ $@=~s/\.pm .*/.pm/, \$@ }"
    if $@;

plan skip_all => "Set NYTPROF_TEST_PORTABILITY_FILES env var to enable test"
    unless $ENV{'NYTPROF_TEST_PORTABILITY_FILES'};

Test::Portability::Files->import(); # calls plan()
#options(use_file_find => 1); # test all files not just those in MANIFEST (lots of .svn/* errors)
#options(all_tests => 1);     # to be hyper-strict (e.g., lots of DOS 8.3 length errors)
run_tests();

1;
