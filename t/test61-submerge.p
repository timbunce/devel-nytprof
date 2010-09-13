# test merging of sub info and sub callers
# which is applied to, e.g., anon subs inside evals

sub foo { print "foo @_\n" }

my $code = 'sub { foo() }';

eval($code)->(); eval($code)->(); eval($code)->();
