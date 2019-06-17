use strict;
use Test::More;
use lib qw(t/lib);
plan skip_all => "only >5.12 testdata" if $] < 5.014;

use NYTProfTest;

# hack to disable sawampersand test, just to simplify the testing across versions
$ENV{DISABLE_NYTPROF_SAWAMPERSAND} = 1;

run_test_group;

unlink glob ('auto/test14/*');
rmdir 'auto/test14';
rmdir 'auto';
