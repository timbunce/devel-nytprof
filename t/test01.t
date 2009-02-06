use strict;
use Test::More;
use lib qw(t/lib);
use NYTProfTest;

run_test_group(1 => sub {
                   my ($profile, $env) = @_;
                   isa_ok($profile, 'Devel::NYTProf::Data');
               });
