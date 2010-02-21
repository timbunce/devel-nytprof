# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;

use Devel::NYTProf::Run qw(profile_this);

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => {
        # set options for this test:
        usecputime => 1,
        # restrict irrelevant options:
        compress => 1, slowops => 0, savesrc => 0, leave => 0, stmts => 0,
    },
    extra_test_count => 6,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

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
        is $sub->incl_time, $sub->excl_time, 'incl_time and excl_time should be the same';
    },
});

__DATA__
#!perl

alarm(20); # watchdog timer

my $trace = 0;
my $cpu1 = (times)[0];
my $cpu2;

sub foo {
    my $end = shift;

    # sleep to separate cputime from realtime
    # (not very effective in cpu-starved VMs)
    sleep 1;

    my $loops = 0;
    my $prev;
    while (++$loops) {

        my $crnt = (times)[0];
        warn "tick $crnt ".time()."\n"
            if $crnt != $prev and $trace >= 2;
        $prev = $crnt;

        last if $crnt >= $end;
    }
    warn "cputime loop count $loops\n" if $trace;
} 

# sync up: spin till clock ticks
1 while $cpu1 == ($cpu2 = (times)[0]);
warn "cputime step ".($cpu2-$cpu1)."\n" if $trace;

# record start time
my $start = time();

# consume this much cpu time inside foo()
foo($cpu2 + 0.4);

# report realtime to help identify is cputime is really measuring realtime
print "realtime used ".(time()-$start)."\n" if $trace;
