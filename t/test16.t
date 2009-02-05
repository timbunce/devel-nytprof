use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "needs perl >= 5.10" unless $] >= 5.010;
plan 'no_plan';

run_test_group;
