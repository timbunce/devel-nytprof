# test merging of sub calls from eval fids

sub foo { print "foo\n" }

my $code = 'foo()';

# call once from particular line
eval $code;

# call twice from the same line
eval $code or die $@ for (1,2);

# once from an eval inside an eval
eval "eval q{$code}";
