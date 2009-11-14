use Test::More;

use strict;
use lib qw(t/lib);

use NYTProfTest;

use Devel::NYTProf::Run qw(profile_this);

run_test_group( {
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
