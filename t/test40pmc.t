use strict;
use Test::More;
use Config;
plan skip_all => ".pmc are disabled in this perl"
    if $Config{ccflags} =~ /(?<!\w)-DPERL_DISABLE_PMC\b/;
use lib qw(t/lib);
use NYTProfTest;

run_test_group;
