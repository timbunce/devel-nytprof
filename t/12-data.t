use strict;
use warnings;
use Carp;
use Devel::NYTProf::Reader;
use Test::More;
use File::Spec;
use File::Temp qw( tempdir );
use Data::Dumper;$Data::Dumper::Indent=1;

# Relax this restriction once we figure out how to make test $file work for
# Appveyor.
plan skip_all => "doesn't work without HAS_ZLIB" if (($^O eq "MSWin32") || ($^O eq 'VMS'));

my $file = "./t/nytprof_12-data.out.txt";
croak "No $file" unless -f $file;

my $reporter = Devel::NYTProf::Reader->new($file, { quiet => 1 });
ok(defined $reporter, "Devel::NYTProf::Reader->new returned defined entity");
isa_ok($reporter, 'Devel::NYTProf::Reader');

my $profile = $reporter->{profile};
isa_ok($profile, 'Devel::NYTProf::Data');
my $pkgref = $profile->package_subinfo_map(0,1);
is(ref($pkgref), 'HASH', "package_subinfo_map() returned hashref");

done_testing();
