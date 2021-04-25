use strict;
use warnings;
use File::Temp qw( tempfile );
use Capture::Tiny qw( capture_stderr );
use Test::More;

warn "\nXXXXXX: t/rt70211.t\n";
my ($fh, $tfile) = tempfile();
print $fh <<EOF;
BEGIN { }
1;
EOF
close $fh;

my $stderr = capture_stderr {
    my $rv = system(qq|$^X -Iblib/lib -MDevel::NYTProf $tfile|);
};
TODO: {
    local $TODO = "logwarn is still being triggered";
    ok(! $stderr, "RT-70211: No warning logged")
        or diag($stderr);
}

done_testing;
