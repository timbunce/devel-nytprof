# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;
use Data::Dumper;

use Devel::NYTProf::Run qw(profile_this);

my $pre589 = ($] < 5.008009 or $] eq "5.010000");

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => { start => 'begin' },
    extra_test_count => 16,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs = $profile->subname_subinfo_map;

        my $begin = ($pre589) ? 'main::BEGIN' : 'main::BEGIN@3';
        is scalar keys %$subs, 3, "should be 3 subs (got @{[ keys %$subs ]})";
        ok $subs->{$begin};
        ok $subs->{'main::RUNTIME'};
        ok $subs->{'main::foo'};

        my @fi = $profile->all_fileinfos;
        is @fi, 1, 'should be 1 fileinfo';
        my $fid = $fi[0]->fid;

        my @a; # ($file, $fid, $first, $last); 
        @a = $profile->file_line_range_of_sub($begin);
        is "$a[1] $a[2] $a[3]", "$fid 3 6", "details for $begin should match";
        @a = $profile->file_line_range_of_sub('main::RUNTIME');
        is "$a[1] $a[2] $a[3]", "$fid 1 1", 'details for main::RUNTIME should match';
        @a = $profile->file_line_range_of_sub('main::foo');
        is "$a[1] $a[2] $a[3]", "$fid 2 2", 'details for main::foo should match';

        $subs = $profile->subs_defined_in_file($fid);
        my $sub;
        is scalar keys %$subs, 3, 'should be 3 subs';
        ok $sub = $subs->{$begin};
        SKIP: {
            skip "needs perl >= 5.8.9 or >= 5.10.1", 1 if $pre589;
            is $sub->calls, 1, "$begin should be called 1 time";
        };
        ok $sub = $subs->{'main::RUNTIME'};
        is $sub->calls, 0, 'main::RUNTIME should be called 0 times';
        ok $sub = $subs->{'main::foo'};
        is $sub->calls, 2, 'main::foo should be called 2 times';

    },
});

__DATA__
#!perl
sub foo { 42 }
BEGIN {
    foo(2);
    *CORE::GLOBAL::sleep = \&foo;
}
sleep 1;
