use Test::More tests => 5;

my $nytprof_out;
BEGIN {
    $ENV{NYTPROF} = "start=init";
    $nytprof_out = "nytprof.out";
    unlink $nytprof_out;
}

use Devel::NYTProf;
use Devel::NYTProf::Test qw(example_xsub example_sub);


# simple assignment and immediate check of $!
$! = 9999;
is 0+$!, 9999, '$! should not be altered by NYTProf';

my $size1 = -s $nytprof_out;
cmp_ok $size1, '>', 0, "$nytprof_out should exist and not be empty";

$! = 9999;
example_sub();
is 0+$!, 9999, "\$! should not be altered by assigning fids to previously unprofiled modules ($!)";

$! = 9999;
example_xsub();
is 0+$!, 9999, "\$! should not be altered by assigning fids to previously unprofiled modules ($!)";

$! = 9999;
while (-s $nytprof_out == $size1) {
    # execute lots of statements to force some i/o even if zipping
    busy();
}
is 0+$!, 9999, '$! should not be altered by NYTProf i/o';

exit 0;

sub busy {
    # none of this should alter $!
    for (my $i = 1_000; $i > 0; --$i) {
        example_xsub();
        next if $i % 100;
        example_sub();
    }
}
