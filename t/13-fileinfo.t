use strict;
use warnings;
use Carp;
use Config qw(%Config);
use Devel::NYTProf::Data;
use Test::More;
use Devel::NYTProf::Constants qw(
    NYTP_DEFAULT_COMPRESSION
    NYTP_ZLIB_VERSION
);

plan skip_all => "needs different profile data for testing on longdouble builds"
    if (defined $Config{uselongdouble} and $Config{uselongdouble} eq 'define');

plan skip_all => "needs different profile data for testing on quadmath builds"
    if (defined $Config{usequadmath} and $Config{usequadmath} eq 'define');

my $file = "./t/nytprof_13-data.out.txt";
croak "No $file" unless -f $file;

plan skip_all => "$file doesn't work unless NYTP_ZLIB_VERSION is set" unless NYTP_ZLIB_VERSION();

# General setup

my $profile = Devel::NYTProf::Data->new({ filename => $file, quiet => 1 });
ok(defined $profile, "Devel::NYTProf::Data->new() returned defined value");

my @all_fileinfos = $profile->all_fileinfos();
is(scalar(@all_fileinfos), 1, "got 1 all_fileinfo");
my $fi = $all_fileinfos[0];
isa_ok($fi, 'Devel::NYTProf::FileInfo');

# For filename(), filename_without_inc() and summary(), return value will
# differ based on whether we're running from top-level directory (e.g., via
# 'prove') or via test harness (e.g., via 'make test').  So, rather than
# demand an exact match on the return value, we'll try to match the end of the
# absolute path.

my $expected_pattern = qr/t\/test01\.p$/;
like($fi->filename, $expected_pattern,
    "Got expected pattern for filename");
like($fi->filename_without_inc, $expected_pattern,
    "Got expected pattern for filename without inc");
like($fi->summary, $expected_pattern,
    "Got expected pattern for summary");

my $expected_fid = 1;
is($fi->fid, $expected_fid, "Got expected fid");
is($fi->size, 0, "Got expected file size");
is($fi->mtime, 0, "Got expected file mtime");
isa_ok($fi->profile, 'Devel::NYTProf::Data');
is($fi->flags, 18, "Got expected flags");
ok($fi->is_file, "We're dealing with a file");

my $et = $fi->excl_time();
cmp_ok($et, '>', 0, "Got positive excl time: $et");

ok(! $fi->eval_fid, "Not an eval fid");
ok(! $fi->eval_line, "Hence, no eval line");
ok(!$fi->is_eval, "We're not dealing with a simple eval");
ok(! defined $fi->outer(), "outer() returns undefined value because no eval fid");
ok(! defined $fi->sibling_evals, "sibling_evals() returns undefined value because no eval fid");

my @subs_defined = $fi->subs_defined();
isa_ok($subs_defined[0], 'Devel::NYTProf::SubInfo');

my @subs_defined_sorted = $fi->subs_defined_sorted();
isa_ok($subs_defined_sorted[0], 'Devel::NYTProf::SubInfo');

# TODO XXX: Test an eval fid

done_testing();
