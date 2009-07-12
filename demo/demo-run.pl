#!/bin/env perl -w
use strict;
use IO::Handle;

my $NYTPROF = ($ENV{NYTPROF}) ? "$ENV{NYTPROF}:" : "";

my %runs = (
    start_begin => {
        skip => 0,
        NYTPROF => 'start=begin:optimize=0',
    },
    start_check => {
        skip => 1,
        NYTPROF => 'start=init:optimize=0',
    },
    start_end => {
        skip => 1,
        NYTPROF => 'start=end:optimize=0',
    },
);


for my $run (keys %runs) {

    next if $runs{$run}{skip};
    $ENV{NYTPROF}      = $NYTPROF . $runs{$run}{NYTPROF} || '';
    $ENV{NYTPROF_HTML} = $runs{$run}{NYTPROF_HTML} || '';

    my $cmd = "perl -d:NYTProf demo/demo-code.pl @ARGV";
    open my $fh, "| $cmd"
        or die "Error starting $cmd\n";

    # feed data into the stdin read loop in demo/demo-code.pl
    $fh->autoflush;
    print $fh "$_\n" for (1..10);
    sleep 2;
    print $fh "$_\n" for (1..10);
    close $fh
        or die "Error closing pipe to $cmd: $!\n";

    my $outdir = "demo-out/profiler-$run";
    system("rm -rf $outdir") == 0 or exit 0;
    system("mkdir -p $outdir") == 0 or exit 0;
    system("perl -Mblib bin/nytprofhtml --open --out=$outdir") == 0
        or exit 0;

    #system "ls -lrt $outdir/.";

    sleep 1;
}

