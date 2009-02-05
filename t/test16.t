use strict;
use Test::More qw(no_plan);
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "needs perl >= 5.10" unless $] >= 5.010;

run_test_group;
