use strict;
use warnings;
use Carp;
use Devel::NYTProf::Reader;
use Test::More qw( no_plan );
use File::Temp qw( tempdir );
use Data::Dumper;

my $file = "./t/nytprof_11-reader.out.txt";
croak "No $file" unless -f $file;
my $reporter = Devel::NYTProf::Reader->new($file);
ok(defined $reporter, "Devel::NYTProf::Reader->new returned defined entity");
isa_ok($reporter, 'Devel::NYTProf::Reader');

#my $tdir = tempdir( CLEANUP => 1 );
my $tdir = tempdir( );
ok($reporter->output_dir($tdir), "output_dir set");
is($reporter->output_dir(), $tdir, "output_dir() returned value already set");
is($reporter->get_param('output_dir'), $tdir, "get_param() returned expected value");
is($reporter->set_param('output_dir'), $tdir, "set_param() returned expected value; value already defined");

{
    local $@;
    my $param = 'foobar';
    eval { $reporter->set_param($param => sub {}); };
    like($@, qr/Attempt to set $param to.*?failed: $param is not a valid parameter/,
        "set_param(): caught exception for invalid parameter");
}
$reporter->set_param(mk_report_source_line => sub {
    my ($linenum, $line, $stats_for_line, $statistics, $profile, $filestr) = @_;
    $line =~ s/^\s*//;
    my $delim = ',';

	my $time  = $stats_for_line->{'time'} || 0;
	my $calls = $stats_for_line->{'calls'} || 0;
	$time  += $stats_for_line->{evalcall_stmts_time_nested} || 0;

    my $text = sprintf("%f%s%g%s%f%s%s\n",
        $time, $delim,
        $calls, $delim,
		($calls) ? $time/$calls : 0, $delim,
        $line,
    );
    return $text;
});
is(ref($reporter->{mk_report_source_line}), 'CODE', "mk_report_source_line set");

$reporter->set_param(mk_report_xsub_line => sub { "" });
is(ref($reporter->{mk_report_xsub_line}), 'CODE', "mk_report_xsub_line set");
is($reporter->get_param('mk_report_xsub_line'), "", "get_param() returned expected value");

my $ffile = "./t/foobar.nytprof_11-reader.out.txt";
ok(!defined($reporter->file_has_been_modified($ffile)),
    "file_has_been_modified(): nonexistent file");

# generate the files
{
    local $@;
    eval { $reporter->report({ quiet => 1 } ); };
    ok(! $@, "report() ran without exception");
}
my $csvcount = 0;
opendir my $DIRH, $tdir or croak "Unable to open $tdir for reading";
while (my $f = readdir $DIRH) {
    chomp $f;
    $csvcount++ if $f =~ m/\.csv$/;
}
closedir $DIRH or croak "Unable to close $tdir after reading";
is($csvcount, 3, "3 csv reports created");
