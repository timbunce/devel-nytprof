use Test::More;

use strict;
use lib qw(t/lib);
use NYTProfTest;

# test run_test_group() with extra_test_code and profile_this()
# also regression test for deflate bug
# https://rt.cpan.org/Ticket/Display.html?id=50851

use Devel::NYTProf::Run qw(profile_this);

run_test_group( {
    extra_options => { stmts => 0 }, # RT#50851
    extra_test_count => 1,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => "1+1",
            out_file => $env->{file},
        );
        isa_ok $profile, 'Devel::NYTProf::Data';
    },
});
