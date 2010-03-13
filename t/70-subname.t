# Tests CORE::GLOBAL::foo plus assorted data model methods

use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;

eval "use Sub::Name 0.04; 1"
	or plan skip_all => "Sub::Name required";


use Devel::NYTProf::Run qw(profile_this);

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => {
		start => 'init', compress => 1, leave => 0, stmts => 0, slowops => 0,
   	},
    extra_test_count => 2,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
			#htmlopen => 1,
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs = $profile->subname_subinfo_map;

        ok $subs->{'main::named'};
    },
});

__DATA__
#!perl
use Sub::Name;
(subname 'named' => sub { print "sub called\n" })->();
