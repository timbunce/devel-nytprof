use strict;
use warnings;
use Carp;
use Config qw(%Config);
use Devel::NYTProf::Reader;
use Test::More;
use Devel::NYTProf::Constants qw(
    NYTP_DEFAULT_COMPRESSION
    NYTP_ZLIB_VERSION
);

plan skip_all => "needs different profile data for testing on longdouble builds"
    if (defined $Config{uselongdouble} and $Config{uselongdouble} eq 'define');

my $file = "./t/nytprof_14-subinfo.out.txt";
croak "No $file" unless -f $file;

plan skip_all => "$file doesn't work unless NYTP_ZLIB_VERSION is set" unless NYTP_ZLIB_VERSION();

# General setup

my $reporter = Devel::NYTProf::Reader->new($file, { quiet => 1 });
ok(defined $reporter, "Devel::NYTProf::Reader->new returned defined entity");
isa_ok($reporter, 'Devel::NYTProf::Reader');

my $profile = $reporter->{profile};
isa_ok($profile, 'Devel::NYTProf::Data');

my ($pkgref, $subinfo_obj, @keys, $expect);

$pkgref = $profile->package_subinfo_map(0,1);
is(ref($pkgref), 'HASH',
    "Devel::NYTProf::Data->package_subinfo_map(0,1) returned hashref");
@keys = keys %{$pkgref};
is(@keys, 1, "1-element hash");
$expect = 'main';
is($keys[0], $expect, "Sole element is '$expect'");
isa_ok($pkgref->{$expect}{""}[0], 'Devel::NYTProf::SubInfo');
$subinfo_obj = $pkgref->{$expect}{""}[0];
isa_ok($subinfo_obj, 'Devel::NYTProf::SubInfo');

## Covered, but not explicitly:
## recur_max_depth
## recur_incl_time
## cache

$expect = 1;
is($subinfo_obj->fid, $expect, "Got expected fid");

my ($fl,
    $ll, $calls);

$fl = $subinfo_obj->first_line;
ok(($fl =~ m/^\d+/ and $fl >= 0), "first_line() returned non-negative integer");
$ll = $subinfo_obj->last_line;
ok(($ll =~ m/^\d+/ and $fl >= 0), "last_line() returned non-negative integer");
$calls = $subinfo_obj->calls;
ok(($calls =~ m/^\d+/ and $fl >= 0), "calls() returned non-negative integer");

my ($subname, $package, $without);
$subname = $subinfo_obj->subname;
($package, $without) = split '::', $subname, 2;
is($package, 'main', "subname() returned expected package");
is($subinfo_obj->subname_without_package, $without,
    "subname_without_package() returned expected name");
is($subinfo_obj->package, $package,
    "package() returned expected package");

$profile = $subinfo_obj->profile;
is(ref($profile), 'Devel::NYTProf::Data',
    "profile() returns Devel::NYTProf::Data object");

ok(defined($subinfo_obj->incl_time), "incl_time() returned defined value");
ok(defined($subinfo_obj->excl_time), "excl_time() returned defined value");
ok(defined($subinfo_obj->recur_max_depth), "recur_max_depth() returned defined value");
ok(defined($subinfo_obj->recur_incl_time), "recur_incl_time() returned defined value");
is(ref($subinfo_obj->cache), 'HASH', "cache() returned hash ref");

my @caller_places = $subinfo_obj->caller_places;
for my $c (@caller_places) {
    is(ref($c), 'ARRAY',
        "each element of any returned by caller_places() is an array ref");
}
is($subinfo_obj->caller_count, scalar(@caller_places),
    "caller_count() returned expected count");

my $fileinfo = $subinfo_obj->fileinfo;
isa_ok($fileinfo, 'Devel::NYTProf::FileInfo');

done_testing();
