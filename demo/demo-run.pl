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

    system("rm -rf demo/profiler-$run") == 0
        or exit 0;
    system("perl -Mblib bin/nytprofhtml -out=demo/profiler-$run") == 0
        or exit 0;

    system "open demo/profiler-$run/index.html"
        if $^O eq 'darwin';
    system "ls -lrt demo/profiler-$run/.";

    sleep 1;
}

