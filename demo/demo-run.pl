#!/bin/env perl -w
use strict;

my %runs = (
    plain => {
    },
    subs => {
        NYTPROF => 'blocks',
        NYTPROF_DATASET => 'fid_sub_time',
    },
    blocks => {
        NYTPROF => 'blocks',
        NYTPROF_DATASET => 'fid_block_time',
    },
    blocks2 => {
        NYTPROF => 'blocks',
        NYTPROF_DATASET => 'fid_block_time',
        NYTPROF_HTML => 1,
    },
);


for my $run (keys %runs) {

    $ENV{NYTPROF}      = $runs{$run}{NYTPROF} || '';
    $ENV{NYTPROF_HTML} = $runs{$run}{NYTPROF_HTML} || '';
    $ENV{NYTPROF_DATASET} = $runs{$run}{NYTPROF_DATASET} || '';

    system("perl -Mblib -MDevel::NYTProf demo-code.pl @ARGV") == 0
        or exit 0;

    system("perl -Mblib bin/nytprofhtml -out=profiler-$run") == 0
        or exit 0;

    system "open profiler-$run/index.html"
        if $^O eq 'darwin';

    sleep 1;
}

