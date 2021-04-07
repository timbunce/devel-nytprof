use strict;
use warnings;
use Carp;
use Devel::NYTProf::Data;
#use Devel::NYTProf::Util qw( trace_level );
use Test::More;
#use File::Spec;
#use File::Temp qw( tempdir tempfile );
use Data::Dumper;$Data::Dumper::Indent=1;
#use Capture::Tiny qw(capture_stdout capture_stderr );

# Relax this restriction once we figure out how to make test $file work for
# Appveyor.
plan skip_all => "doesn't work without HAS_ZLIB" if (($^O eq "MSWin32") || ($^O eq 'VMS'));

# General setup

my $file = "./t/nytprof_13-data.out.txt";
croak "No $file" unless -f $file;

my $profile = Devel::NYTProf::Data->new({ filename => $file, quiet => 1 });
ok(defined $profile, "Devel::NYTProf::Data->new() returned defined value");

my @all_fileinfos = $profile->all_fileinfos();
is(scalar(@all_fileinfos), 1, "got 1 all_fileinfo");
my $fi = $all_fileinfos[0]; 
print STDERR Dumper($fi);
isa_ok($fi, 'Devel::NYTProf::FileInfo');

my $expected_f = '/home/jkeenan/gitwork/zzzothers/devel-nytprof/t/test01.p';
is($fi->filename, $expected_f, "Got expected filename");
is($fi->filename_without_inc, $expected_f, "Got expected filename without inc");
my $expected_fid = 1;
is($fi->fid, $expected_fid, "Got expected fid");
is($fi->size, 0, "Got expected file size");
is($fi->mtime, 0, "Got expected file mtime");
isa_ok($fi->profile, 'Devel::NYTProf::Data');
is($fi->flags, 18, "Got expected flags");
ok($fi->is_file, "We're dealing with a file");

my $et = $fi->excl_time();
cmp_ok($et, '>', 0, "Got positive excl time: $et");

my $expected = "fid${expected_fid}: $expected_f";
is($fi->summary, $expected, "Got expected summary");

ok(! $fi->eval_fid, "Not an eval fid");
ok(! $fi->eval_line, "Hence, no eval line");
ok(!$fi->is_eval, "We're not dealing with a simple eval");
ok(! defined $fi->outer(), "outer() returns undefined value because no eval fid");
ok(! defined $fi->sibling_evals, "sibling_evals() returns undefined value because no eval fid");

# TODO XXX: Test an eval fid

done_testing();
