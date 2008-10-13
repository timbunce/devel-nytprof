package # hide from pause package indexer
    Devel::NYTProf::Test;

# this module is just to test the test suite
# see t/test60-subname.p for example

use Devel::NYTProf::Core;
use base qw(Exporter);

our @EXPORT_OK = qw(example_xsub);

1;
