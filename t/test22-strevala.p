# test merging of anon subs from evals

my $code = 'sub { print "sub called\n" }';

# call once from particular line
eval($code)->();

# call twice from the same line
eval($code)->() for (1,2);

# called from inside a string eval
eval q{
    eval($code)->() for (1,2);
};
