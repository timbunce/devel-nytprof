use Test::More;

use strict;
use lib qw(t/lib);

use NYTProfTest;

use Devel::NYTProf::Run qw(profile_this);

run_test_group( {
    extra_test_count => 1,
    _extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => "1+1"
        );
        isa_ok $profile, 'Devel::NYTProf::Data';
    },
});
