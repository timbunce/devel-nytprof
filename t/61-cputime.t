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
        my $trace = ($^O eq 'freebsd'); # XXX temp

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            #htmlopen => 1,
            verbose => $trace,
            skip_sitecustomize => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';
        warn "ticks_per_sec ".$profile->attributes->{ticks_per_sec}."\n"
            if $trace;

        my $subs = $profile->subname_subinfo_map;
        my $sub = $subs->{'main::foo'};
        ok $sub;
        is $sub->calls, 1, 'main::foo should be called 1 time';
        cmp_ok $sub->incl_time, '>=', 0.4 * 0.99, 'cputime of foo() should be at least 0.4';
        cmp_ok $sub->incl_time, '<', 1.1, 'cputime of foo() should be not much more than 0.4';
        is $sub->incl_time, $sub->excl_time, 'incl_time and excl_time should be the same';
    },
});

__DATA__
#!perl

BEGIN { eval { require Time::HiRes } and Time::HiRes->import('time') }

alarm(20); # watchdog timer

my $trace = 0;
my $cpu1;
my $cpu2;

sub foo {
    my $cpuspend = shift;

    # sleep to separate cputime from realtime
    # (not very effective in cpu-starved VMs)
    sleep 1;

    my $loops = 0;
    my $prev;
    while (++$loops) {
        my @times = times;
        my $crnt = $times[0] + $times[1] - $cpu1;
        warn sprintf "tick %.4f\t%f\n", $crnt, time()
            if $trace >= 2 && $prev && $crnt != $prev;
        $prev = $crnt;

        last if $crnt >= $cpuspend;
    }
    warn "cputime loop count $loops\n" if $trace >= 2;
} 

# record start time
my $start = time() + 1;

# sync up...

# spin till wall clock ticks
1 while time() <= $start;

# spin till cpu clock ticks (typically 0.1 sec max)
my @times = times;
$cpu1 = $times[0] + $times[1];
while (1) {
    @times = times;
    $cpu2 = $times[0] + $times[1];
    last if $cpu2 != $cpu1;
}

warn sprintf "step %f\t%f\n", $cpu2-$cpu1, time() if $trace;
$cpu1 = $cpu2; # set cpu1 to new current cpu time

# consume this much cpu time inside foo()
foo(0.4);

# report realtime to help identify is cputime is really measuring realtime
print "realtime used ".(time()-$start)."\n" if $trace;
