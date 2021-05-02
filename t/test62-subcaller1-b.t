use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "needs perl >= 5.33.3 (see t/test62-subcaller1-a)"
    if $] < 5.033003;

run_test_group;
