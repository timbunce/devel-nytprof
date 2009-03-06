#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

eval "use Test::Portability::Files";
SKIP: {
    skip "Test::Portability::Files required for testing filenames portability, this currently a developer-only test", 1 unless (!$@ && (-d '.svn') && ($ENV{'NYTPROF_TEST_PORTABILITY_FILES'}) );
    options(all_tests => 1);  # to be hyper-strict
    run_tests();
}

1;
