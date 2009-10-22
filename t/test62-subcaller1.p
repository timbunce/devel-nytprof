# test determination of subroutine caller in unusual cases

{
    package MyTie;
    # this TIESCALAR call isn't seen by perl < 5.8.9 and 5.10.1
    sub TIESCALAR { bless {}, shift; }
    sub FETCH { }
    sub STORE { }
}

tie my $tied, 'MyTie', 42;  # TIESCALAR
$tied = 1;                  # STORE
if ($tied) { 1 }            # FETCH

# test dying from an xsub
require Devel::NYTProf::Test;
eval { Devel::NYTProf::Test::example_xsub(0, "die") };

# test dying from an xsub where the surrounding eval is an
# argument to a sub call. This used to coredump.
sub use_eval_arg { }
use_eval_arg eval { Devel::NYTProf::Test::example_xsub(0, "die") };

exit 0;
