package # hide from pause package indexer
    Devel::NYTProf::Test;

# this module is just to test the test suite
# see t/test60-subname.p for example

require Devel::NYTProf::Core;
require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw(example_xsub example_sub);

sub example_sub { }

1;
