use Test::More;

use strict;

use lib qw(t/lib);
use NYTProfTest;

plan skip_all => "doesn't work with fork() emulation" if (($^O eq "MSWin32") || ($^O eq 'VMS'));

plan tests => 5;

my $out = 'nytprof-forkdepth.out';

is run_forkdepth(  0 ),   1;
is run_forkdepth(  1 ),   2;
is run_forkdepth(  2 ),   3;
is run_forkdepth( -1 ),   3;
is run_forkdepth( undef), 3;

exit 0;

sub run_forkdepth {
    my ($forkdepth) = @_;

    unlink $_ for glob("$out.*");

    $ENV{NYTPROF} = "file=$out:addpid=1";
    $ENV{NYTPROF} .= ":forkdepth=$forkdepth" if defined $forkdepth;

    my $forkdepth_cmd = q{-d:NYTProf -e "fork and wait,exit 0; fork and wait"};
    run_perl_command($forkdepth_cmd);

    my @files = glob("$out.*");
    unlink $_ for @files;

    return scalar @files;
}

