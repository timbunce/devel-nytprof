use Test::More tests => 2;

use Config;

use_ok( 'Devel::NYTProf::Core' );

diag( "Testing Devel::NYTProf $Devel::NYTProf::Core::VERSION on perl $] $Config{archname}" );

use_ok( 'Devel::NYTProf::Constants', qw(NYTP_DEFAULT_COMPRESSION) );

diag( sprintf "default compression level is %d", NYTP_DEFAULT_COMPRESSION() );
