use Test::More tests => 8;

use strict;
use Devel::NYTProf::ReadStream qw(for_chunks);

(my $base = __FILE__) =~ s/\.t$//;

my @arr;
eval {
    for_chunks {
	push(@arr, [$., @_]);
    } filename => "$base-v20.out";
};
SKIP: {
    if ($@) {
	skip "No zlib support", 8 if $@ && $@ =~ /compression is not supported/;
	skip "Unusual NV size", 8 if $@ && $@ =~ /Profile data created by incompatible perl config/;
	die $@;
    }

    is_deeply([0..51], [map shift(@$_), @arr], "chunk seq");

    # some samples
    is_deeply($arr[0], ["VERSION", 2, 0], "version");
    is_deeply($arr[3], ["ATTRIBUTE", "xs_version", "2.05"], "attr");
    is_deeply($arr[10], ["START_DEFLATE"], "deflate");
    is_deeply($arr[11], ["PID_START", 1710, 13983], "pid start");
    is_deeply($arr[12], ["NEW_FID", 1, 0, 0, 2, 0, 0, "/Users/gisle/p/Devel-NYTProf/t/test01.p"], "fid");
    is_deeply($arr[14], ["TIME_BLOCK", 0, 0, 76, 1, 7, 7, 7], "time");
    is_deeply($arr[15], ["DISCOUNT"], "discount");

    #use Data::Dump; ddx \@arr;
}

