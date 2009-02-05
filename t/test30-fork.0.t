use strict;
use Test::More qw(no_plan);
use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "doesn't work with fork() emulation" if $^O eq "MSWin32";

run_test_group;
