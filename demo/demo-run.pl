#!/bin/env perl -w
use strict;

my %runs = (
    start_begin => {
        skip => 0,
        NYTPROF => 'start=begin',
    },
    start_check => {
        skip => 0,
        NYTPROF => 'start=init',
    },
    start_end => {
        skip => 0,
        NYTPROF => 'start=end',
    },
);


for my $run (keys %runs) {

    next if $runs{$run}{skip};
    $ENV{NYTPROF}      = $runs{$run}{NYTPROF} || '';
    $ENV{NYTPROF_HTML} = $runs{$run}{NYTPROF_HTML} || '';

    system("perl -Mblib -MDevel::NYTProf demo/demo-code.pl @ARGV") == 0
        or exit 0;

    my $outdir = "demo-out/profiler-$run";
    system("rm -rf $outdir") == 0 or exit 0;
    system("mkdir -p $outdir") == 0 or exit 0;
    system("perl -Mblib bin/nytprofhtml -out=$outdir") == 0
        or exit 0;

    system "open $outdir/index.html"
        if $^O eq 'darwin';
    system "ls -lrt $outdir/.";

    sleep 1;
}

