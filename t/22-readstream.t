use Test::More;

use strict;
use lib qw(t/lib);
use Config;
use NYTProfTest;

plan tests => 20;

use Devel::NYTProf::ReadStream qw(for_chunks);

my $pre589 = ($] < 5.008009 or $] eq "5.010000");

(my $base = __FILE__) =~ s/\.t$//;

# generate an nytprof out file
my $out = 'nytprof_readstream.out';
$ENV{NYTPROF} = "file=$out";
unlink $out;

run_perl_command(q{-d:NYTProf -e "sub A { };" -e "1;" -e "A()"});

my %prof;
my @seqn;

for_chunks {
    push @seqn, "$.";
    my $tag = shift;
    push @{ $prof{$tag} }, [ @_ ];
    if (1) {
        my @params = @_;
        not defined $_ and $_ = '(undef)' for @params;
        chomp @params;
        print "# $. $tag @params\n";
    }
} filename => $out;

ok scalar @seqn, 'should have read chunks';
is_deeply(\@seqn, [0..@seqn-1], "chunk seq");

#use Data::Dumper; warn Dumper \%prof;

is_deeply $prof{VERSION}, [ [ 4, 0 ] ];

# check for expected tags
# but not START_DEFLATE as that'll be missing if there's no zlib
# and not SRC_LINE as old perl's 
for my $tag (qw(
        COMMENT ATTRIBUTE DISCOUNT TIME_BLOCK
        SUB_INFO SUB_CALLERS
        PID_START PID_END NEW_FID
)) {
    is ref $prof{$tag}[0], 'ARRAY', $tag;
}

SKIP: {
    skip 'needs perl >= 5.8.9 or >= 5.10.1', 1 if $pre589;
    is ref $prof{SRC_LINE}[0], 'ARRAY', 'SRC_LINE';
}

# check some attributes
my %attr = map { $_->[0] => $_->[1] } @{ $prof{ATTRIBUTE} };
cmp_ok $attr{ticks_per_sec}, '>=', 1_000_000, 'ticks_per_sec';
is $attr{application}, '-e', 'application';
is $attr{nv_size}, $Config{nvsize}, 'nv_size';
cmp_ok $attr{xs_version}, '>=', 2.1, 'xs_version';
cmp_ok $attr{basetime}, '>=', $^T, 'basetime';

is_deeply $prof{SUB_INFO}, [
    [ 1, 1, 1, 'main::A' ],
    [ 1, 0, 0, 'main::BEGIN' ],
    [ 1, 1, 1, 'main::RUNTIME' ]
];

$prof{SUB_CALLERS}[0][$_] = 0 for (3,4);
is_deeply $prof{SUB_CALLERS}, [
    [ 1, 3, 1, 0, 0, '0', 0, 'main::A', 'main::RUNTIME' ]
];
