# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;

use Devel::NYTProf::Run qw(profile_this);

run_test_group( {
    extra_options => {
        # set options for this test:
        usecputime => 1,
        # restrict irrelevant options:
        compress => 1, slowops => 0, savesrc => 1, leave => 0,
    },
    extra_test_count => 5,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        my $src_code = q{
            alarm(20); # watchdog timer
            sub foo {
                my $wait = 0.5; # consume this much cpu time inside foo()
                my $cpu1 = (times)[0];
                while (1) {
                    my $cpu2 = (times)[0];
                    last if $cpu2 > $cpu1 + $wait;
                }
            } 
            # could spin waiting for (times)[0] to change before calling foo
            foo();
        };
        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            #htmlopen => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs = $profile->subname_subinfo_map;
        my $sub = $subs->{'main::foo'};
        ok $sub;
        is $sub->calls, 1, 'main::foo should be called 1 times';
        cmp_ok $sub->incl_time, '>', 0.4, 'cputime of foo() should be at least ~0.5';
        cmp_ok $sub->incl_time, '<', 1.0, 'cputime of foo() should be around 0.5';
    },
});
