#! /usr/bin/env perl
##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/~akaplan/Devel-NYTProf
##
###########################################################
use warnings;
use strict;
use ExtUtils::testlib;
use Benchmark;
use Getopt::Long;
use Config;
use Test::More tests => 36;
use_ok('Devel::NYTProf::Reader');

# skip these tests when the provided condition is true
my %SKIP_TESTS = (
	'test06' => ($] < 5.008) ? 1 : 0,
	'test15' => ($] >= 5.008) ? 1 : 0,
);

my %opts;
GetOptions(\%opts, qw/p=s I=s v/);

my $opt_perl = $opts{p};
my $opt_include = $opts{I};

chdir( 't' ) if -d 't';
my @tests = @ARGV ? @ARGV : sort <*.p *.v *.x>;  # glob-sort, for OS/2

my $path_sep = $Config{path_sep} || ':';
if( -d '../blib' ){
	unshift @INC, '../blib/arch', '../blib/lib';
}
my $fprofcsv = './bin/nytprofcsv';
if( -d '../bin' ) {
	$fprofcsv = ".$fprofcsv";
}

my $perl5lib = $opt_include || join( $path_sep, @INC );
my $perl = $opt_perl || $^X;

if( $opts{v} ){
	print "tests: @tests\n";
	print "perl: $perl\n";
	print "perl5lib: $perl5lib\n";
	print "fprofcvs: $fprofcsv\n";
}
if( $perl =~ m|^\./| ) {
	# turn ./perl into ../perl, because of chdir(t) above.
	$perl = ".$perl";
}
#ok(-f $perl, "Where's Perl?");
ok(-x $fprofcsv, "Where's fprofcsv?");

can_ok('Devel::NYTProf::Reader', 'process');

$|=1;
foreach my $test (@tests) {
	#print $test . '.'x (20 - length $test);
	$test =~ /(\w+)\.(\w)$/;
	
		if ($2 eq 'p') {
			profile($test);
		} elsif($2 eq 'v') {
			SKIP: {
        skip "Tests incompatible with your perl version", 1, 
              if (defined($SKIP_TESTS{$1}) and $SKIP_TESTS{$1});
        verify_result($test);
      }
		} elsif($2 eq 'x') {
			SKIP: {
        skip "Tests incompatible with your perl version", 1, 
              if (defined($SKIP_TESTS{$1}) and $SKIP_TESTS{$1});
        verify_report($test);
		  }
		}
}

sub profile {
	my $test = shift;
	my @results;
	local $ENV{PERL5LIB} = $perl5lib;
	
	if ($test eq "test04.p") {
		$ENV{NYTPROF} = "allowfork";	
	} else {
		$ENV{NYTPROF} = "";	
	}

	my $t_start = new Benchmark;
	open(RV, "$perl -d:NYTProf $test |") or warn "$- can't run $!\n";
	@results = <RV>;
	close RV;
	my $t_total = timediff( new Benchmark, $t_start );

	if ( $opts{v} ) {
		print "\n";
		print @results;
	}
	#print timestr( $t_total, 'nop' ), "\n";
}

sub verify_result {
	my $test = shift;
	no warnings;
  my $hash = Devel::NYTProf::Reader::process();
	use warnings;

  # remove times unless specifically testing times
  foreach my $outer (keys %$hash) {
		pop_times($hash->{$outer});
	}

	my $expected;
	{
		local $/ = undef;
		open(TEST, $test) or die "Unable to open test $test: $!\n";
		my $contents = <TEST>; #slurp
		close TEST;
		eval $contents;
	}
	is_deeply($hash, $expected, $test);
}

sub verify_report {
	my $test = shift;

	local $ENV{PERL5LIB} = $perl5lib;
	open(RV, "$perl $fprofcsv |") or die "fprofcvs can't run $!\n";
	my $results = <RV>;
	close RV;
	if ($opts{v}) {
		print <RV>;
		print "\n";
	}


	# parse/check
  my $infile;
  { local ($1, $2);
	$test =~ /^(\w+\.(\w+\.)?)x$/;
  $infile = $1;
  if (defined $2) {
  } else {
    $infile .= "p.";
  }
  }
	open(IN, "profiler/${infile}csv") or die "Can't open test file: ${infile}csv";
	my @got = <IN>;
	close IN;

	open(EXP, $test) or die "Unable to open testing file t/$test\n";
	my @expected = <EXP>;
	close EXP;

	if ($opts{v}) {
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

		if (0 != $expected[$index] =~ s/^\|([0-9.]+)\|(.*)/0$2/o) {
			# Test times. expected to be within 200ms
			ok(abs($1 - $t0) < 0.2, "Time accuracy - $test line $index");
			my $tc = $t0 / $c0;
			ok(abs($tc - $tc0) < 0.2, "Time/Call accuracy - $test line $index");
		}

		push @got, $_;
		$index++;
	}

	if ($opts{v}) {
		print "TRANSFORMED TO:\n";
		print @got;
		print "\n";
	}

	is_deeply(\@got, \@expected, $test);
}

sub pop_times {
	my $hash = shift||return;

	foreach my $key (keys %$hash) {
		shift @{$hash->{$key}};
		pop_times($hash->{$key}->[1]);
	}
}
