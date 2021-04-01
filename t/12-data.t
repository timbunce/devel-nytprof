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

my @all_fileinfos = $profile->all_fileinfos();
is(scalar(@all_fileinfos), 1, "got 1 all_fineinfo");

my @eval_fileinfos = $profile->eval_fileinfos();
is(scalar(@eval_fileinfos), 0, "got 0 eval_fineinfo");

my @noneval_fileinfos = $profile->noneval_fileinfos();
is(scalar(@noneval_fileinfos), 1, "got 1 noneval_fineinfo");

=pod

sub all_fileinfos {
    my @all = @{shift->{fid_fileinfo}};
    shift @all;    # drop fid 0
    # return all non-nullified fileinfos
    return grep { $_->fid } @all;
}

sub eval_fileinfos {
    return grep {  $_->eval_line } shift->all_fileinfos;
}

sub noneval_fileinfos {
    return grep { !$_->eval_line } shift->all_fileinfos;
}

=cut

done_testing();
