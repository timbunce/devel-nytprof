# test sub name resolution
use Devel::NYTProf::Test qw(example_xsub);

# call XS sub directly
Devel::NYTProf::Test::example_xsub("foo");

# call XS sub imported into main
# (should still be reported as a call to Devel::NYTProf::Test::example_xsub)
example_xsub("foo");

# call XS sub as a method (ignore the extra arg)
Devel::NYTProf::Test->example_xsub();

# call XS sub as a method via subclass (ignore the extra arg)
@Subclass::ISA = qw(Devel::NYTProf::Test);
Subclass->example_xsub();

my $subname = "Devel::NYTProf::Test::example_xsub";
&$subname("foo");

# XXX currently goto isn't noticed by the profiler
# it's as if the call never happened. This most frequently
# affects AUTOLOAD subs.
sub launch { goto &$subname }
launch("foo");
