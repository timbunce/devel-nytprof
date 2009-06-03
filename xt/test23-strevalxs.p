# test string eval made from embedded environment
use Devel::NYTProf::Test qw(example_xsub_eval);

example_xsub_eval(); # calls eval_pv() perlapi
