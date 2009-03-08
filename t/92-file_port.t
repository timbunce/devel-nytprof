#!/usr/bin/perl

use strict;
use warnings;

use Test::More qw(no_plan);

eval "use Test::Portability::Files";

# Skipping tests this way because of the way Test::Portability::Files::import
# sets a plan, and if multiple "plan skip_all =>" are used this causes a failure
# when Test::Portability::Files is available - "You tried to plan twice".

SKIP: {
    skip "Test::Portability::Files required for testing filenames portability, this currently a developer-only test", 1 unless (!$@ && (-d '.svn') && ($ENV{'NYTPROF_TEST_PORTABILITY_FILES'}) );
    options(all_tests => 1);  # to be hyper-strict
    run_tests();
}

1;
