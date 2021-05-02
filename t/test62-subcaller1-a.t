use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "needs perl >= 5.8.9 or >= 5.10.1"
    if $] < 5.008009 or $] eq "5.010000";

plan skip_all => "needs perl < 5.33.3 (see t/test62-subcaller1-b.t)" # XXX
    if $] >= 5.033003;

run_test_group;
