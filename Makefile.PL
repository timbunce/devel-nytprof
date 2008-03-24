##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/~akaplan/Devel-NYTProf
##
###########################################################
use 5.008001;
use warnings;
use strict;
use ExtUtils::MakeMaker;
use Config;

# --- Discover how much of stdio is implemented

print "Looking for stdio.h and stdio_ext.h\n";
my $INCLUDE;
my $stdio_dir;
my $stdio_ext_dir;

sub search_paths {
	my $dir = shift;
	my @dirs = split /:/, $dir;
	foreach (@dirs) {
		opendir(DIR, $_) or "Unable to open $_\n" and next;

		while(my $file = readdir(DIR)) {
			if ($file =~ m/^stdio\.h$/) {
				$stdio_dir = $_ unless defined $stdio_dir;
			} elsif ($file =~ m/^stdio_ext\.h$/) {
				$stdio_ext_dir = $_ unless defined $stdio_ext_dir;
			}
			last if (defined $stdio_dir && defined $stdio_ext_dir);
		}

		closedir(DIR);
		last if (defined $stdio_dir && defined $stdio_ext_dir);
	}
}

my $fpurge;
sub search_files {
	if (defined $stdio_dir) {
		open(STDIOH, "$stdio_dir/stdio.h");
		while (<STDIOH>) {
			if (m/(_{0,2}fpurge)\s*\(/go) {
				$fpurge = $1;
				$stdio_ext_dir = undef;
				last;
			}
		}
		close STDIOH;
	}

	return if (defined $fpurge);

	if (defined $stdio_ext_dir) {
		open(STDIOEH, "$stdio_ext_dir/stdio_ext.h");
		while (<STDIOEH>) {
			if (m/(_{0,2}fpurge)\s*\(/go) {
				$fpurge = $1;
				$stdio_dir = undef;
				last;
			}
		}
		close STDIOEH;
	}
}

# verify
sub verify {
	if (defined ($fpurge)) {
		if (defined $stdio_ext_dir) {
			print "Found $fpurge in $stdio_ext_dir/stdio_ext.h\n";
			$INCLUDE = $stdio_ext_dir;
		} else {
			print "Found $fpurge in $stdio_dir/stdio.h\n";
			$INCLUDE = $stdio_dir;
		}
		return 1;
	}
	undef;
}

if (defined $ENV{INCLUDE}) {
  search_paths($ENV{INCLUDE});
} else {
  search_paths('/include:/usr/include:/usr/local/include');
}
search_files();

while(!verify) {
	print<<EOD;
		Unable to find an fpurge function in your INCLUDE path 
		files. fpurge isn't required, but will result in MUCH
		faster profiling if your code may fork.  If it normally 
		found in stdio_ext.h, and sometimes in stdio.h.  Try 
		using `find' or `locate' to discover where these files
		reside.  Enter paths to include in the search here, 
		seperated by ':' (or leave it blank to not use fpurge 
		at all)

EOD
		my $pathstr = prompt("Additional header search paths:", "");
		if (length $pathstr) {
			search_paths($pathstr);
			search_files();
		} else {
			last;
		}
}

$INCLUDE = $stdio_dir if defined $stdio_dir;
$INCLUDE = $stdio_ext_dir if defined $stdio_ext_dir;
my $DEFINE = '-DHAS'.uc($fpurge);
$DEFINE .= ' -DHAS_STDIO_EXT_H' if defined $stdio_ext_dir;

# ---

if ($Config::Config{d_gettimeod}) {
    $DEFINE .= ' -D_HAS_GETTIMEOFDAY';
}

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Devel::NYTProf',
    VERSION_FROM      => 'lib/Devel/NYTProf.pm', # finds $VERSION
    PREREQ_PM         => {
    	  'Getopt::Long'    => 0,
    	}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Devel/NYTProf.pm', # retrieve abstract from module
       AUTHOR         => 'Adam Kaplan <akaplan@>') : ()),
    LIBS              => [''], # e.g., '-lm'
    EXE_FILES					=> [ 'bin/nytprofhtml', 'bin/nytprofcsv' ],
    MAN1PODS					=> { 'bin/nytprofhtml' => '$(INST_MAN1DIR)/nytprofhtml.1',
													'bin/nytprofcsv' => '$(INST_MAN1DIR)/nytprofcsv.1' },
    DEFINE            => $DEFINE, # e.g., '-DHAVE_SOMETHING'
    												# e.g., '-I. -I/usr/include/other'
    INC               => "-I. -I$INCLUDE", # e.g., '-I. -I/usr/include/other'
		clean							=> { FILES	=> "nytprof.out profiler t/nytprof.out t/profiler" },
		test							=> { TESTS => 'test.pl' },
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
