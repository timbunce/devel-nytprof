use Test::More tests => 10;

use_ok('Devel::NYTProf::Core');
my $version = $Devel::NYTProf::Core::VERSION;
ok $version, 'lib/Devel/NYTProf/Core.pm $VERSION should be set';

use_ok('Devel::NYTProf::Data');
is $Devel::NYTProf::Data::VERSION, $version, 'lib/Devel/NYTProf/Data.pm $VERSION should match';

use_ok('Devel::NYTProf::Util');
is $Devel::NYTProf::Util::VERSION, $version, 'lib/Devel/NYTProf/Util.pm $VERSION should match';

use_ok('Devel::NYTProf::Reader');
is $Devel::NYTProf::Reader::VERSION, $version, 'lib/Devel/NYTProf/Reader.pm $VERSION should match';

use_ok('Devel::NYTProf');
is $Devel::NYTProf::VERSION, $version, 'lib/Devel/NYTProf.pm $VERSION should match';
# clean up after ourselves
DB::finish_profile();
unlink 'nytprof.out';
