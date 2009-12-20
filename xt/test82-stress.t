# Stress tests

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;

use Devel::NYTProf::Run qw(profile_this);

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => {
        compress => 1,
        savesrc => 1,
    },
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
        );
        isa_ok $profile, 'Devel::NYTProf::Data';
        # check if data truncated e.g. due to assertion failure
        ok $profile->{attribute}{complete};

        ok my $subs = $profile->subs_defined_in_file(1);
        ok $subs->{'main::pass'}->calls;

    },
    extra_test_count => 4,
});

__DATA__

# test for old perl bug 20010515.004 that NYTProf tickled into life
# http://markmail.org/message/3q6q2on3gl6fzdhv
# http://markmail.org/message/b7qnerilkusauydf
# based on test in perl's t/run/fresh_perl.t 
my @h = 1 .. 10;
sub bad {
    undef @h;
    open BUF, '>', \my $stdout_buf or die "Can't open STDOUT: $!";
    # is the bug is tickled this will print something like
    # HASH(0x82acc0)ARRAY(0x821b60)ARRAY(0x812f10)HASH(0x8133f0)HASH(0x8133f0)ARRAY(0x821b60)00
    print BUF for @_; # this line is very sensitive to changes
    die "\@_ affected by NYTProf" if $stdout_buf;
    close BUF;
}
bad(@h);

sub pass { }; pass(); # flag successful completion
