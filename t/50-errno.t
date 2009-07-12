use Test::More tests => 8;

my $nytprof_out;
BEGIN {
    $nytprof_out = "nytprof-50-errno.out";
    $ENV{NYTPROF} = "start=init:file=$nytprof_out";
    unlink $nytprof_out;
}

use Devel::NYTProf;
use Devel::NYTProf::Test qw(example_xsub example_sub);


# simple assignment and immediate check of $!
$! = 9999;
is 0+$!, 9999, '$! should not be altered by NYTProf';

my $size1 = -s $nytprof_out;
cmp_ok $size1, '>=', 0, "$nytprof_out should exist";

SKIP: {
    skip 'On VMS buffer is not flushed', 1 if ($^O eq 'VMS'); 
    cmp_ok $size1, '>', 0, "$nytprof_out should not be empty";
}

$! = 9999;
example_sub();
is 0+$!, 9999, "\$! should not be altered by assigning fids to previously unprofiled modules ($!)";

$! = 9999;
example_xsub();
is 0+$!, 9999, "\$! should not be altered by assigning fids to previously unprofiled modules ($!)";

$! = 9999;

SKIP: {
    skip 'On VMS buffer does not flush', 1 if($^O eq 'VMS');
    while (-s $nytprof_out == $size1) {
        # execute lots of statements to force some i/o even if zipping
        busy();
    }
    is 0+$!, 9999, '$! should not be altered by NYTProf i/o';
}

ok not eval { example_xsub(0, "die"); 1; };
like $@, qr/^example_xsub\(die\)/;

exit 0;

sub busy {
    # none of this should alter $!
    for (my $i = 1_000; $i > 0; --$i) {
        example_xsub();
        next if $i % 100;
        example_sub();
    }
}
