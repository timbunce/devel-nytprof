# test nested string evals
# inner time should propagate to outermost eval
# statement counts currently don't - debatable value
sub foo { 1 }
my $code = q{
    select(undef,undef,undef,0.2);
    foo();
    eval q{
        select(undef,undef,undef,0.2);
        foo();
        eval q{
            select(undef,undef,undef,0.2);
            foo();
        }
    }
};
eval $code;
