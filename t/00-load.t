use Test::More tests => 2;

use Config;

# we note the time in the test log here (the first test) and in t/zzz.t
# so we can judge how fast the set of tests ran and this the rough speed of the system
diag("Tests started at ". localtime(time));

use_ok( 'Devel::NYTProf::Core' );

diag( "Testing Devel::NYTProf $Devel::NYTProf::Core::VERSION on perl $] $Config{archname}" );

use_ok( 'Devel::NYTProf::Constants', qw(
    NYTP_DEFAULT_COMPRESSION NYTP_ZLIB_VERSION
) );

diag( sprintf "Compression: default level is %d, zlib version %s",
    NYTP_DEFAULT_COMPRESSION(), NYTP_ZLIB_VERSION()
);

if ("$Config{archname} $Config{osvers}" =~ /\b xen \b/x) {
    diag("It looks like this is running inside a Xen virtual machine.");
    diag("Operating system clocks are typically unstable in this situation,");
    diag("so tests may fail or produce odd warnings.");
    diag("Use of NYTProf inside a virtual machine is not recommended.");
}
