#!/bin/env perl -w
use strict;

my %runs = (
    plain => {
    },
);


for my $run (keys %runs) {

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

