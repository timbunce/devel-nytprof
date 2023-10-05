use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

#plan skip_all => "needs perl >= 5.10" unless $] >= 5.010;
plan skip_all => "needs perl >= 5.10 and <= 5.36"
    unless ($] >= 5.010 and $] <= 5.036);

run_test_group;
