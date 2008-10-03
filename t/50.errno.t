use Test::More tests => 4;

my $nytprof_out;
BEGIN {
    $ENV{NYTPROF} = "start=init";
    $nytprof_out = "nytprof.out";
    unlink $nytprof_out;
}

use Devel::NYTProf;

# some modules just to 'do some work'
use Text::Wrap;
use Benchmark;
use Socket;


# simple assignment and immediate check of $!
$! = 9999;
is 0+$!, 9999, '$! should not be altered by NYTProf';

my $size1 = -s $nytprof_out;
ok $size1, "$nytprof_out should be non-empty";

$! = 9999;
new Benchmark;
fill("", "", ("foo bar baz") x 100);
is 0+$!, 9999, '$! should not be altered by assigning fids to previously unprofiled modules';

$! = 9999;
while (-s $nytprof_out == $size1) {
    # execute lots of statements to force some i/o even if zipping
    # none of this should alter $!
    timediff(new Benchmark, new Benchmark);
    $Text::Wrap::columns = 9;
    fill("", "", ("foo bar baz") x 100);
    pack_sockaddr_un("foo"); # call xs sub
}
is 0+$!, 9999, '$! should not be altered by NYTProf i/o';

exit 0;
