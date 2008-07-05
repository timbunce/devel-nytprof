# vim: ts=2 sw=2 sts=0 noexpandtab:
##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/~akaplan/Devel-NYTProf
##
###########################################################
# $Id$
###########################################################
use 5.006000;
use warnings;
use strict;

use ExtUtils::MakeMaker;
use Getopt::Long;
use Config;

my $is_developer = (-d '.svn');

# --- Bail out on Windows
if ($^O eq 'MSWin32') {
	print "This module does not support Windows because of NYTProf.xs.\n"
				."Feel free to port it and submit a patch to develnytprof-dev\@googlegroups.com\n";
	die "No support for OS";
}

# --- Options
GetOptions(
	'g!'  => \my $opt_g,
	'pg!' => \my $opt_pg,
) or exit 1;

# --- Discover how much of stdio is implemented

print "Looking for stdio.h and stdio_ext.h\n";
my $INCLUDE;
my $stdio_dir;
my $stdio_ext_dir;
my $time_dir;
my $fpurge;

my $cpp =  $Config{cpp} || do {
	warn "Warning: cpp not found in your perl config.  Falling back to 'cat'\n";
	'cat';
};

my $clock_gettime = search_for_clock_gettime($time_dir);

if (defined $ENV{INCLUDE}) {
  search_paths($ENV{INCLUDE});
} else {
  search_paths('/include:/usr/include:/usr/local/include');
}
search_for_fpurge();
search_for_clock_gettime();

while (!verify_fpurge()) {
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
			search_for_fpurge();
		} else {
			last;
		}
}

$INCLUDE = $stdio_dir if defined $stdio_dir;
$INCLUDE = $stdio_ext_dir if defined $stdio_ext_dir;
my $include_string = "-I.";
$include_string .= $INCLUDE if defined $INCLUDE;

my @LIBS = ();
push @LIBS, "-lrt" if $clock_gettime;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
my %mm_opts;

$mm_opts{DEFINE} .= '-DHAS'.uc($fpurge) if defined($fpurge);
$mm_opts{DEFINE} .= ' -DHAS'.uc($clock_gettime) if $clock_gettime;
$mm_opts{DEFINE} .= ' -DHAS_STDIO_EXT_H' if defined $stdio_ext_dir;

$mm_opts{LICENSE} = 'perl' if $ExtUtils::MakeMaker::VERSION >= 6.3002;
$mm_opts{OPTIMIZE} = '-g'  if $opt_g;
$mm_opts{CCFLAGS}  = "-pg" if $opt_pg;

if (my $gccversion = $Config{gccversion}) {     # ask gcc to be more pedantic
    print "Your perl was compiled with gcc (version $Config{gccversion}), okay.\n";
    $gccversion =~ s/[^\d\.]//g; # just a number please
    $mm_opts{DEFINE} .= ' -W -Wall -Wpointer-arith -Wbad-function-cast';
    $mm_opts{DEFINE} .= ' -Wno-comment -Wno-sign-compare -Wno-cast-qual';
    $mm_opts{DEFINE} .= ' -Wmissing-noreturn -Wno-unused-parameter' if $gccversion ge "3.0";
    if ($is_developer && $opt_g) {
        $mm_opts{DEFINE} .= ' -DPERL_GCC_PEDANTIC -ansi -pedantic' if $gccversion ge "3.0";
        $mm_opts{DEFINE} .= ' -Wdisabled-optimization -Wformat'    if $gccversion ge "3.0";
        $mm_opts{DEFINE} .= ' -Wmissing-prototypes';
    }
}


WriteMakefile(
    NAME              => 'Devel::NYTProf',
    VERSION_FROM      => 'lib/Devel/NYTProf/Core.pm', # finds $VERSION
    ABSTRACT_FROM     => 'lib/Devel/NYTProf.pm', # retrieve abstract from module
    AUTHOR            => 'Adam Kaplan <akaplan@cpan.org>, Tim Bunce <timb@cpan.org>',
    PREREQ_PM         => {
    	  'List::Util'      => 0,
    	  'Test::More'      => 0,
    	  'XSLoader'        => 0,
    	  'Getopt::Long'    => 0,
    	}, # e.g., Module::Name => 1.1
    LIBS              => \@LIBS,
    EXE_FILES					=> [ 'bin/nytprofhtml', 'bin/nytprofcsv' ],
    MAN1PODS					=> { 'bin/nytprofhtml' => '$(INST_MAN1DIR)/nytprofhtml.1',
													'bin/nytprofcsv' => '$(INST_MAN1DIR)/nytprofcsv.1' },
    INC               => $include_string, # e.g., '-I. -I/usr/include/other'
		clean							=> { 
			FILES	=> "nytprof.out profiler t/nytprof.out t/profiler t/test*.*.new t/auto"
		},
		%mm_opts,
);

exit 0;

# --- Utility functions ---


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
			} elsif ($file =~ m/^time\.h$/) {
				$time_dir = $_ unless defined $time_dir;
			}
			last if (defined $stdio_dir && defined $stdio_ext_dir
				&& defined $time_dir);
		}

		closedir(DIR);
		last if (defined $stdio_dir && defined $stdio_ext_dir && defined $time_dir);
	}
}


sub search_for_fpurge {
	if (defined $stdio_dir) {
		open(STDIOH, "$cpp $stdio_dir/stdio.h |");
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
		open(STDIOEH, "$cpp $stdio_ext_dir/stdio_ext.h |");
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


sub verify_fpurge {
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


sub search_for_clock_gettime {
	my $dir = shift
		or return;
	open(TIMEH, "$cpp $dir/time.h |");
	while (<TIMEH>) {
		if (m/(clock_gettime)\s*\(/go) {
			return $1;
		}
	}
	close TIMEH;
}


# --- MakeMaker overrides ---

package MY;

# add some extra utility targets to the make file
sub post_constants {
    q{
svnmanifest::
	svn list -R .@HEAD | sort | grep -v '/$$' > MANIFEST
	svn diff MANIFEST

checkkeywords:
	$(RM_RF) blib
	find .  \( -name .svn -prune -or -name t -prune -or -name \*.pm -or -name \*.PL -or -name \*.pl \) -type f \
			-exec bash -c '[ "$$(svn pg svn:keywords {})" != "Id Revision Date" ] && echo svn propset svn:keywords \"Id Revision Date\" {}' \;

checkpod:
	$(RM_RF) blib
	find . -type f \( -name .svn -prune -o -name \*.pm -o -name \*.PL -o -name \*.pl \) \
			-exec podchecker {} \; 2>&1 | grep -v "pod syntax OK"
}
}

sub dynamic {
	my $make = shift->SUPER::dynamic(@_);
	$make .= join "\n",
		'# Copy extension to where XSLoader looks to avoid fallback to DynaLoader',
		'# See t/test14.p for more details',
		'XSL_DEST_DIR = $(INST_LIB)/$(PARENT_NAME)/auto/$(FULLEXT)',
		'XSL_DEST = $(XSL_DEST_DIR)/$(DLBASE).$(DLEXT)',
		'',
		'dynamic :: $(INST_DYNAMIC)',
		"\t".'$(NOECHO) $(MKPATH) $(XSL_DEST_DIR)',
		"\t".'$(CP) $(INST_DYNAMIC) $(XSL_DEST)',
		'';
	return $make;
}


# vim:ts=2:sw=2:sts=0:noexpandtab
