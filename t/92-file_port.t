#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

eval "require Test::Portability::Files;";
plan skip_all => "Test::Portability::Files required for testing filename portability. ${ $@=~s/\.pm .*/.pm/, \$@ }"
    if $@;

plan skip_all => "Set AUTHOR_TESTING env var to enable test"
    unless $ENV{'AUTHOR_TESTING'};

Test::Portability::Files->import(); # calls plan()
#options(use_file_find => 1); # test all files not just those in MANIFEST (lots of .svn/* errors)
#options(all_tests => 1);     # to be hyper-strict (e.g., lots of DOS 8.3 length errors)
options(test_one_dot => 0);   # .indent.pro, .travis.yml, t/test02.pf.csv
run_tests();

1;
