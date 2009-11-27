# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;

use Devel::NYTProf::Run qw(profile_this);

run_test_group( {
    extra_options => { start => 'begin' },
    extra_test_count => 16,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        my $src_code = q{
            sub foo { 42 }
            BEGIN {
                foo(2);
                *CORE::GLOBAL::sleep = \&foo;
            }
            sleep 1;
        };
        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs = $profile->subname_subinfo_map;

        is scalar keys %$subs, 3, 'should be 3 subs';
        ok $subs->{'main::BEGIN'};
        ok $subs->{'main::RUNTIME'};
        ok $subs->{'main::foo'};

        my @fi = $profile->all_fileinfos;
        is @fi, 1, 'should be 1 fileinfo';
        my $fid = $fi[0]->fid;

        my @a; # ($file, $fid, $first, $last); 
        @a = $profile->file_line_range_of_sub('main::BEGIN');
        is "$a[1] $a[2] $a[3]", "$fid 3 6", 'details for main::BEGIN should match';
        @a = $profile->file_line_range_of_sub('main::RUNTIME');
        is "$a[1] $a[2] $a[3]", "$fid 1 1", 'details for main::RUNTIME should match';
        @a = $profile->file_line_range_of_sub('main::foo');
        is "$a[1] $a[2] $a[3]", "$fid 2 2", 'details for main::foo should match';

        $subs = $profile->subs_defined_in_file($fid);
        my $sub;
        is scalar keys %$subs, 3, 'should be 3 subs';
        ok $sub = $subs->{'main::BEGIN'};
        SKIP: {
            skip "needs perl >= 5.8.9 or >= 5.10.1", 1
                if $] < 5.008009 or $] eq "5.010000";
            is $sub->calls, 1, 'main::BEGIN should be called 1 time';
        };
        ok $sub = $subs->{'main::RUNTIME'};
        is $sub->calls, 0, 'main::RUNTIME should be called 0 times';
        ok $sub = $subs->{'main::foo'};
        is $sub->calls, 2, 'main::foo should be called 2 times';

    },
});
