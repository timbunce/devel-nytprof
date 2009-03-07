#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

plan skip_all => "This currently a developer-only test"
    unless -d '.svn';

eval "use Test::Portability::Files";
plan skip_all => "Test::Portability::Files required for testing filename portability"
    if $@;

plan skip_all => "Set NYTPROF_TEST_PORTABILITY_FILES env var to enable test"
    unless $ENV{'NYTPROF_TEST_PORTABILITY_FILES'};

options(all_tests => 1);  # to be hyper-strict
run_tests();

1;
