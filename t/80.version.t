use Test::More tests => 10;

use_ok('Devel::NYTProf::Core');
my $version = $Devel::NYTProf::Core::VERSION;
ok $version;

use_ok('Devel::NYTProf::Data');
is $Devel::NYTProf::Data::VERSION, $version;

use_ok('Devel::NYTProf::Util');
is $Devel::NYTProf::Util::VERSION, $version;

use_ok('Devel::NYTProf::Reader');
is $Devel::NYTProf::Reader::VERSION, $version;

use_ok('Devel::NYTProf');
is $Devel::NYTProf::VERSION, $version;
# clean up after ourselves
DB::finish_profile();
unlink 'nytprof.out';
