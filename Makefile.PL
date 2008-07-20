# vim: ts=2 sw=2 sts=0 noexpandtab:
##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/dist/Devel-NYTProf/
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
	print "This module does not currently support Windows.\n"
				."Please help us port it - contact us at develnytprof-dev\@googlegroups.com\n";
	die "No support for OS" if $ENV{AUTOMATED_TESTING}; # keep cpan-testers happy
}

# --- Options
GetOptions(
	'g!'  => \my $opt_g,
	'pg!' => \my $opt_pg,
) or exit 1;

# --- Discover how much of stdio is implemented

my $cpp =  $Config{cpp} || do {
	warn "Warning: cpp not found in your perl config.  Falling back to 'cat'\n";
	'cat';
};

print "Looking for header files and functions...\n";
my $INCLUDE;
my $clock_gettime;

my $h_files;
my @h_dirs;
push @h_dirs, split /:/, $ENV{INCLUDE} if $ENV{INCLUDE};
push @h_dirs, split ' ', $Config{libsdirs};
push @h_dirs, qw(/include /usr/include /usr/local/include);
@h_dirs = grep { -d $_ } @h_dirs;

$h_files = find_h_files(@h_dirs);

# search for clock_gettime
$clock_gettime = search_h_file('time.h', qr/(clock_gettime)\s*\(/)
	and print "Found $clock_gettime in time.h\n";


my @LIBS = ();
push @LIBS, "-lrt" if $clock_gettime;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
my %mm_opts;

$mm_opts{DEFINE} .= ' -DHAS_'.uc($clock_gettime) if $clock_gettime;

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
    	},
    LIBS              => \@LIBS,
    EXE_FILES					=> [ 'bin/nytprofhtml', 'bin/nytprofcsv' ],
    MAN1PODS					=> { 'bin/nytprofhtml' => '$(INST_MAN1DIR)/nytprofhtml.1',
													'bin/nytprofcsv' => '$(INST_MAN1DIR)/nytprofcsv.1' },
    INC               => $INCLUDE,
    clean             => { 
        FILES => "t/nytprof_t.out nytprof t/nytprof.out t/*.outdir t/test*.*.new t/auto"
    },
    dist  => {
        DIST_DEFAULT=> 'clean distcheck disttest tardist',
        PREOP => '$(MAKE) -f Makefile.old distdir',
        COMPRESS => 'gzip -v9', SUFFIX => 'gz',
    },
    %mm_opts,
);

exit 0;

# --- Utility functions ---


sub find_h_files {
	my @dirs = @_;
	my %h_files;
	foreach my $dir (@dirs) {
		next unless $dir;
		opendir(DIR, $dir)
			or next; # silently ignore missing directories

		while (my $file = readdir(DIR)) {
			next unless $file =~ /\.h$/;
			$h_files{$file} ||= $dir; # record first found
		}
	}
	close DIR;
	return \%h_files;
}

sub search_h_file {
	my ($h_file, $regex) = @_;
	my $dir = $h_files->{$h_file}
		or return undef;
	open H, "$cpp $dir/$h_file |";
	while (<H>) {
		return $1 if m/$regex/;
	}
	close H;
	return undef
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
