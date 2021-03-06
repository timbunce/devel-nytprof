use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

# XXX needed because the call from example_xsub to will_die,
# made via call_sv() doesn't get profiled on older perls
plan skip_all => "needs perl >= 5.8.9 or >= 5.10.1"
    if $] < 5.008009 or $] eq "5.010000";

run_test_group;
