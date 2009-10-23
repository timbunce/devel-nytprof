use Test::More 0.84;

use strict;
use lib qw(t/lib);
use Config;
use NYTProfTest;

plan tests => 18;

use Devel::NYTProf::ReadStream qw(for_chunks);

(my $base = __FILE__) =~ s/\.t$//;

# generate an nytprof out file
my $out = 'nytprof_readstream.out';
$ENV{NYTPROF} = "file=$out";
unlink $out;

use Config;
my $this_perl = $^X;
$this_perl .= $Config{_exe} if $^O ne 'VMS' and $this_perl !~ m/$Config{_exe}$/i;

run_command($this_perl . q{ -d:NYTProf -e "sub A { };" -e "1;" -e "A()"});

my %prof;
my @seqn;

for_chunks {
    push @seqn, "$.";
    my $tag = shift;
    push @{ $prof{$tag} }, [ @_ ];
    if (1) { chomp @_; note("$. $tag @_"); }
} filename => $out;

ok scalar @seqn, 'should have read chunks';
is_deeply(\@seqn, [0..@seqn-1], "chunk seq");

#use Data::Dumper; warn Dumper \%prof;

is_deeply $prof{VERSION}, [ [ 3, 0 ] ];

# check for expected tags
# (but not START_DEFLATE as that'll be missing if there's no zlib)
for my $tag (qw(
        COMMENT ATTRIBUTE DISCOUNT SRC_LINE TIME_BLOCK
        SUB_INFO SUB_CALLERS
        PID_START PID_END NEW_FID
)) {
    is ref $prof{$tag}[0], 'ARRAY', $tag;
}

# check some attributes
my %attr = map { $_->[0] => $_->[1] } @{ $prof{ATTRIBUTE} };
cmp_ok $attr{ticks_per_sec}, '>=', 1_000_000, 'ticks_per_sec';
is $attr{application}, '-e', 'application';
is $attr{nv_size}, $Config{nvsize}, 'nv_size';
cmp_ok $attr{xs_version}, '>=', 2.1, 'xs_version';
cmp_ok $attr{basetime}, '>=', $^T, 'basetime';
