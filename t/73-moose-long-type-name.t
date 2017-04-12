use strict;
use Test::More;

use lib qw(t/lib);
use NYTProfTest;

eval "use Moose; 1" or plan skip_all => "Moose required";
eval "use MooseX::Types::Moose; 1" or plan skip_all => "MooseX::Types::Moose required";
eval "use MooseX::Types::Structured; 1" or plan skip_all => "MooseX::Types::Structured required";

use Devel::NYTProf::Run qw(profile_this);

my $src_code = join("", <DATA>);

run_test_group( {
    extra_options => {
        start => 'begin', compress => 1, stmts => 0, slowops => 0,
    },
    extra_test_count => 2,
    extra_test_code  => sub {
        my ($profile, $env) = @_;

        $profile = profile_this(
            src_code => $src_code,
            out_file => $env->{file},
            skip_sitecustomize => 1,
            htmlopen => $ENV{NYTPROF_TEST_HTMLOPEN},
        );
        isa_ok $profile, 'Devel::NYTProf::Data';

        my $subs = $profile->subname_subinfo_map;

        ok 1;
    },
});

__DATA__
#!perl
package Class;
use strict;
use warnings;
use Moose;
use MooseX::Types::Moose qw(:all);
use MooseX::Types::Structured qw(
    Dict
    Map
    Optional
    Tuple
);

has some_attribute => (
    is  => "ro",
    isa => Maybe[
        Dict[
            some => Int,
            really => ArrayRef[
                Dict[
                    long      => Optional[Int],
                    typecheck => Optional[Str],
                    that      => Optional[Str],
                    seems     => Optional[Str],
                    to        => Optional[Str],
                    go        => Optional[Str],
                    on        => Optional[Int],
                    forever   => Optional[Str],
                    and       => Optional[Bool],
                    just      => Optional[Int],
                    never     => Optional[Str],
                    stops     => Optional[Maybe[Str]],
                    this      => Optional[Int],
                    used      => Optional[Int],
                    to        => Optional[Int],
                    cause     => Optional[Int],
                    a         => Optional[Int],
                    segfault  => Optional[Int],
                ],
            ],
        ],
    ],
    default                       => undef,
    documentation                 => "...",
);

package main;
my $obj = Class->new();

1;

