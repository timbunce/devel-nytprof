use Test::More tests => 1;

use Config;

use_ok( 'Devel::NYTProf::Core' );

diag( "Testing Devel::NYTProf $Devel::NYTProf::Core::VERSION on perl $] $Config{archname}" );
