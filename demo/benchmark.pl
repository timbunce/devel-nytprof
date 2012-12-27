#! /usr/bin/env perl
# vim: ts=8 sw=4 sts=4 expandtab:
##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/perldoc?Devel::NYTProf
##
###########################################################
## $Id: benchmark.pl 322 2008-07-15 04:33:35Z tim.bunce $
###########################################################
use warnings;
use strict;

use Carp;
use Config;
use Getopt::Long;
use Benchmark qw(:hireswallclock timethese cmpthese);
use Devel::NYTProf::Data; # just to print path

GetOptions(
    'v|verbose' => \my $opt_verbose,
) or exit 1;

my $regex = shift;

my $subs_count = shift || 2000;
my $loop_count = shift || 1000;

# simple benchmark script to measure profiling overhead
my $test_script = "benchmark_code.pl";
open my $fh, ">", $test_script or die "Can't write to $test_script: $!\n";
print $fh q{
    my $subs_count = shift || die "No subs count";
    my $loop_count = shift || die "No loop count";
    sub foo {
        my $loop = shift;
        my $a = 0;
        while ($loop-- > 0) { ++$a; ++$a; ++$a; }
    }
    while ($subs_count-- > 0) {
        foo($loop_count)
    }
};
close $fh or die "Error writing to $test_script: $!\n";
END { unlink $test_script };


my %tests = (
    baseline => {
        perlargs => '',
    },
    dprof => {
        perlargs => '-d:DProf',
        datafile => 'tmon.out',
    },
    fastprof => {
        perlargs => '-MDevel::FastProf',
        datafile => 'fastprof.out',
    },
    profit => {
        perlargs => '-MDevel::Profit',
        datafile => 'profit.out',
    },
    nytprof_o => {
        env => [ NYTPROF => 'use_db_sub=0:file=nytprof_o.out' ],
        perlargs => '-d:NYTProf',
        datafile => 'nytprof_o.out',
    },
    nytprof_s => {
        env => [ NYTPROF => 'use_db_sub=1:file=nytprof_s.out' ],
        perlargs => '-d:NYTProf',
        datafile => 'nytprof_s.out',
    },
    nytprof_ob => {
        env => [ NYTPROF => 'blocks:file=nytprof_ob.out' ],
        perlargs => '-d:NYTProf',
        datafile => 'nytprof_ob.out',
    },
);

my %test_subs;
while ( my ($testname, $testinfo) = each %tests ) {
    if ($regex && $testname ne 'baseline' && $testname !~ m/$regex/o) {
        warn "Skipped $testname\n";
        next;
    }
    if (!run_test($testinfo, 1, 1)) {
        warn "Can't run $testname profiler - skipped\n";
        next;
    }
    $testinfo->{testname} = $testname;
    $test_subs{$testname} = sub { run_test($testinfo, $subs_count, $loop_count) };
}

printf "Profiler performance using perl %8s %s (%s %s %s)\n",
    $], $Config{archname},
    $Config{gccversion} ? 'gcc' : $Config{cc},
    (split / /, $Config{gccversion}||$Config{ccversion}||'')[0]||'',
    $Config{optimize};
printf "NYTProf is $INC{'Devel/NYTProf/Data.pm'}\n";

cmpthese(4, \%test_subs, 'nop');

for my $testname (sort keys %test_subs) {
    my $testinfo = $tests{$testname};
    if ($testinfo->{datafile}) {
        printf "%10s: %6dKB %s\n",
            $testname, (-s $testinfo->{datafile})/1024, $testinfo->{datafile};
        unlink $testinfo->{datafile};
    }
}

exit 0;

sub run_test {
    my($testinfo, $subs_count, $loop_count) = @_;

    my $env = $testinfo->{env};
    local $ENV{$env->[0]} = $env->[1] if $env;

    my $cmd = "perl $testinfo->{perlargs} $test_script $subs_count $loop_count";
    system($cmd) == 0;
}
