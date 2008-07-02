#! /usr/bin/env perl
# vim: ts=2 sw=2 sts=0 noexpandtab:
##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/~akaplan/Devel-NYTProf
##
###########################################################
## $Id$
###########################################################
use warnings;
use strict;

use Carp;
use ExtUtils::testlib;
use Getopt::Long;
use Config;
use Test::More;
use Data::Dumper;

use Devel::NYTProf::Reader;
use Devel::NYTProf::Util qw(strip_prefix_from_paths);


$|=1;

# skip these tests when the provided condition is true
my %SKIP_TESTS = (
	'test06' => ($] < 5.008) ? 1 : 0,
	'test15' => ($] >= 5.008) ? 1 : 0,
);

my %opts = (
	profperlopts => '-d:NYTProf',
);
GetOptions(\%opts,
	qw/p=s I=s v|verbose d|debug html profperlopts=s/
) or exit 1;

$opts{v} ||= $opts{d};
$ENV{NYTPROF} = ''; # avoid external interference, but see NYTPROF_TEST below
$| = 1;

my $opt_perl = $opts{p};
my $opt_include = $opts{I};
my $outdir = 'nytprof';
my $profile_datafile = 'nytprof_t.out';

chdir( 't' ) if -d 't';
mkdir $outdir or die "mkdir($outdir): $!" unless -d $outdir;

my $tests_per_extn = { p => 1, v => 1, rdt => 1, x => 2 };

s:^t/:: for @ARGV; # allow args to use t/ prefix
# *.p   = perl code to profile
# *.v   = (old) profile data structure to verify
# *.rdt = result tsv data dump to verify
# *.x   = result csv dump to verify (should change to .rcv)
my @tests = @ARGV ? @ARGV : sort <*.p *.v *.rdt *.x>;  # glob-sort, for OS/2

plan tests => 1 + number_of_tests(@tests);

my $path_sep = $Config{path_sep} || ':';
if( -d '../blib' ){
	unshift @INC, '../blib/arch', '../blib/lib';
}
my $bindir = (grep { -d } qw(./bin ../bin))[0]; 
my $nytprofcsv  = "$bindir/nytprofcsv";
my $nytprofhtml = "$bindir/nytprofhtml";

my $perl5lib = $opt_include || join( $path_sep, @INC );
my $perl = $opt_perl || $^X;
# turn ./perl into ../perl, because of chdir(t) above.
$perl = ".$perl" if $perl =~ m|^\./|;

if($opts{v} ){
	print "tests: @tests\n";
	print "perl: $perl\n";
	print "perl5lib: $perl5lib\n";
	print "nytprofcvs: $nytprofcsv\n";
}

ok(-x $nytprofcsv, "Where's nytprofcsv?");


$|=1;
foreach my $test (@tests) {

	#print $test . '.'x (20 - length $test);
	$test =~ / (.+?) \. (?:(\d)\.)? (\w+) $/x or do {
		warn "Can't parse test filename '$test'";
		next;
	};
	my ($basename, $fork_seqn, $type) = ($1, $2||0, $3);

	SKIP: {
		skip "Tests incompatible with your perl version", number_of_tests($test)
			if $SKIP_TESTS{$basename};

		my $test_datafile = (profile_datafiles($profile_datafile))[ $fork_seqn ];

		if ($type eq 'p') {
			unlink_old_profile_datafiles($profile_datafile);
			profile($test, $profile_datafile);
		}
		elsif ($type eq 'v') {
			verify_old_data($test, $test_datafile);
		}
		elsif ($type eq 'rdt') {
			verify_data($test, $test_datafile);
		}
		elsif ($type eq 'x') {
			verify_report($test, $test_datafile);

			if ($opts{html}) {
				run_command("$perl $nytprofhtml --file=$profile_datafile");
			}
		}
		else {
			warn "Unrecognized extension '$type' on test file '$test'\n"
				unless $type eq 'new'; # handy for "test.pl t/test01.*"
		}
	}
}

exit 0;

sub run_command {
  my ($cmd) = @_;
  local $ENV{PERL5LIB} = $perl5lib;
  open(RV, "$cmd |") or die "Can't execute $cmd: $!\n";
  my @results = <RV>;
  close RV or warn "Error status $? from $cmd\n";
  if ($opts{v}) {
    print "$cmd\n";
    print @results;
    print "\n";
  }
  return @results;
}


sub profile {
	my ($test, $profile_datafile) = @_;
	
	my @NYTPROF;
	push @NYTPROF, $ENV{NYTPROF_TEST} if $ENV{NYTPROF_TEST};
	push @NYTPROF, "file=$profile_datafile";
	local $ENV{NYTPROF} = join ":", @NYTPROF;
	print "NYTPROF=$ENV{NYTPROF}\n" if $opts{v} && $ENV{NYTPROF};

	my @results = run_command("$perl $opts{profperlopts} $test");
	pass($test); # mainly to show progress
}


sub verify_old_data {
	my ($test, $profile_datafile) = @_;

	my $hash = eval {
		my %opts = ( relative_paths => [ @INC, '.' ] );
		Devel::NYTProf::Reader::process($profile_datafile, \%opts)
	};
	if ($@) {
		diag($@);
		fail($test);
		return;
	}

  # remove times unless specifically testing times
  foreach my $outer (keys %$hash) {
		pop_times($hash->{$outer});
	}

	my $expected;
	eval scalar slurp_file($test);
	is_deeply($hash, $expected, $test)
		or dump_data_to_file($hash, "$test.new");
}


sub verify_data {
	my ($test, $profile_datafile) = @_;

	my $profile = eval { Devel::NYTProf::Data->new( { filename => $profile_datafile }) };
	if ($@) {
		diag($@);
		fail($test);
		return;
	}

	$profile->normalize_variables;
	dump_profile_to_file($profile, "$test.new");
	my @got      = slurp_file("$test.new");
	my @expected = slurp_file($test);

	is_deeply(\@got, \@expected, $test)
		or diff_files($test, "$test.new");
}


sub dump_data_to_file {
	my ($profile, $file) = @_;
	open my $fh, ">", $file or croak "Can't open $file: $!";
	local $Data::Dumper::Indent = 1;
	local $Data::Dumper::Sortkeys = 1;
	print $fh Data::Dumper->Dump([$profile],['expected']);
	return;
}


sub dump_profile_to_file {
	my ($profile, $file) = @_;
	open my $fh, ">", $file or croak "Can't open $file: $!";
	$profile->dump_profile_data( {
		filehandle => $fh,
		separator  => "\t",
	} );
	return;
}


sub diff_files {
	# we don't care if this fails, it's just an aid to debug test failures
	my @opts = split / /, $ENV{NYTPROF_DIFF_OPTS}||''; # e.g. '-y'
	@opts = ('-u') unless @opts;
	system("diff", @opts, @_);
}


sub verify_report {
	my ($test, $profile_datafile) = @_;

	# generate and parse/check csv report

	my @results = run_command("$perl $nytprofcsv --file=$profile_datafile");

	# determine the name of the generated csv file
	my $csvfile = $test;
	# fork tests will still report using the original script name
	$csvfile =~ s/\.\d\./.0./;

	# foo.p  => foo.p.csv  is tested by foo.x
	# foo.pm => foo.pm.csv is tested by foo.pm.x
	$csvfile =~ s/\.x//;
	$csvfile .= ".p" unless $csvfile =~ /\.p/;

	my @got      = slurp_file("$outdir/${csvfile}.csv");
	my @expected = slurp_file($test);

	if ($opts{d}) {
		print "GOT:\n";
		print @got;
		print "EXPECTED:\n";
		print @expected;
		print "\n";
	}

	my $index = 0;
	foreach (@expected) {
    if ($expected[$index++] =~ m/^# Version/) {
    	splice @expected, $index-1, 1;
    }
  }
 
	my @accuracy_errors;
	$index = 0;
	my $limit = scalar(@got)-1;
	while ($index < $limit) {
		$_ = shift @got;

    if (m/^# Version/) {
			next;
    }

    # Ignore version numbers
		s/^([0-9.]+),([0-9.]+),([0-9.]+),(.*)$/0,$2,0,$4/o;
		my $t0 = $1;
		my $c0 = $2;
		my $tc0 = $3;

		if (defined $expected[$index]
		   and 0 != $expected[$index] =~ s/^\|([0-9.]+)\|(.*)/0$2/
		   and $c0 # protect against div-by-0 in some error situations
		) {
			push @accuracy_errors, "$test line $index: got $t0 expected ~$1 for time"
				if abs($1 - $t0) > 0.2; # Test times. expected to be within 200ms
			my $tc = $t0 / $c0;
			push @accuracy_errors, "$test line $index: got $tc0 expected ~$tc for time/calls"
				if abs($tc - $tc0) > 0.00002; # expected to be very close (rounding errors only)
		}

		push @got, $_;
		$index++;
	}

	if ($opts{d}) {
		print "TRANSFORMED TO:\n";
		print @got;
		print "\n";
	}

	is_deeply(\@got, \@expected, $test) or do {
		spit_file("$test.new", join("", @got));
		diff_files($test, "$test.new");
	};
	is(join("\n",@accuracy_errors), '', $test);
}


sub pop_times {
	my $hash = shift||return;

	foreach my $key (keys %$hash) {
		shift @{$hash->{$key}};
		pop_times($hash->{$key}->[1]);
	}
}


sub number_of_tests {
	my $total_tests = 0;
	for (@_) {
		next unless m/\.(\w+)$/;
		my $tests = $tests_per_extn->{$1};
		warn "Unknown test type '$1' for test file '$_'\n" if not defined $tests;
		$total_tests += $tests if $tests;
	}
	return $total_tests;
}


sub slurp_file { # individual lines in list context, entire file in scalar context
	my ($file) = @_;
	open my $fh, "<", $file or croak "Can't open $file: $!";
	return <$fh> if wantarray;
	local $/ = undef; # slurp;
	return <$fh>;
}


sub spit_file {
	my ($file, $content) = @_;
	open my $fh, ">", $file or croak "Can't open $file: $!";
	print $fh $content;
	close $fh or die "Error closing $file: $!";
}


sub profile_datafiles {
	my ($filename) = @_;
	croak "No filename specified" unless $filename;
	my @profile_datafiles = glob("$filename*");
	# sort to ensure datafile without pid suffix is first
	@profile_datafiles = sort @profile_datafiles;
	return @profile_datafiles; # count in scalar context
}

sub unlink_old_profile_datafiles {
	my ($filename) = @_;
	my @profile_datafiles = profile_datafiles($filename);
	warn "Unlinking old @profile_datafiles\n"
		if @profile_datafiles and $opts{v};
	1 while unlink @profile_datafiles;
}


# vim:ts=2:sw=2
