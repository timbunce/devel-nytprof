##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/~akaplan/Devel-NYTProf
##
###########################################################
package Devel::NYTProf;

package DB;

BEGIN {
	# setting $^P non-zero automatically initializes perl debugging internals
	# (mg.c calls init_debugger) if $DB::single is false. This is handy for
	# situations like mod_perl where perl wasn't started with -d flag.
	$^P=0x1;    # on
	$^P=0x0;    # then back off again for now, see below

	require Devel::NYTProf::ModuleVersion;
	require XSLoader;
	XSLoader::load('Devel::NYTProf', $Devel::NYTProf::ModuleVersion::VERSION);

	if ($] < 5.008008) {	# workaround bug in old perl versions (slow)
		local $^W = 0;
		*_DB = \&DB;
		*DB = sub { goto &_DB }
	}

	init();

	# enable debugging - see perlvar docs
	$^P=  0x002 # Line-by-line debugging (call DB::DB() per statement)
	    | 0x010 # record line range of sub definition
	    | 0x020 # start (after BEGINs) with single-step on
	    | 0x100 # informative "file" names for evals
	    | 0x200;# informative names for anonymous subroutines
	# put nothing here
    }

=for comment from perlvar

  $^P   The internal variable for debugging support.  The meanings of
	the various bits are subject to change, but currently indicate:

	0x01  Debug subroutine enter/exit.
	0x02  Line-by-line debugging.
	0x04  Switch off optimizations.
	0x08  Preserve more data for future interactive inspections.
	0x10  Keep info about source lines on which a subroutine is defined.
	0x20  Start with single-step on.
	0x40  Use subroutine address instead of name when reporting.
	0x80  Report "goto &subroutine" as well.
	0x100 Provide informative "file" names for evals based on the
		place they were compiled.
	0x200 Provide informative names to anonymous subroutines based
		on the place they were compiled.
	0x400 Debug assertion subroutines enter/exit.

	Some bits may be relevant at compile-time only, some at run-
	time only.  This is a new mechanism and the details may change.
=cut


END {
	# cleanup
	_finish();
}


1;
__END__
=head1 NAME

Devel::NYTProf - line-by-line code profiler and report generator

=head1 SYNOPSIS

 # profile code and write database to ./nytprof.out
 perl -d:NYTProf some_perl.pl

 # convert database into html
 nytprofhtml

 # or into comma seperated files
 nytprofcsv

 # or into any other format by implementing your own Devel::NYTProf::Reader
 # submit new implementations like nytprofhtml as bugs/patches for inclusion.
 # (reports go into ./profiler by default)

=head1 HISTORY

A bit of history and a shameless plug...

NYTProf stands for 'New York Times Profiler'. Indeed, this module was developed
by The New York Times Co. to help our developers quickly identify bottlenecks in
large Perl applications.  The NY Times loves Perl and we hope the community will benefit from our work as much as we have from theirs.

Please visit L<http://open.nytimes.com>, our open source blog to see what we are up to, L<http://code.nytimes.com> to see some of our open projects and then 
check out L<htt://nytimes.com> for the latest news!

=head1 DESCRIPTION
 
Devel::NYTProf will profile your perl code line-by-line and enable you to 
create reports in HTML, CSV/plain text or any other format.

This module is implemented in XS (aka C) and the profiler is on par with the speed of L<Devel::FastProf>.  This is the first release, so it will get faster.

The real strenght of Devel::NYTProf isn't its speeds, but the included
L<Devel::NYTProf::Reader> module (and its implementations).  See 
L<Devel::NYTProf::Reader> for more information, but basically the Reader
provides an interface to parsing NYTProf databases and outputing arbitrary
reports.  This means that unlike L<Devel::FastProf>, you can easily implement
your own output format without editing the C source and recompiling the module.

Included in the bin directory of this distribution are two scripts
which implement the L<Devel::NYTProf::Reader> interface: 

=over 4

=item * 
nytprofcsv - creates comma delimited profile reports

=item *
nytprofhtml - creates a very cool HTML report 
(including statistics, source code and color highlighting)

=back

=head1 ENVIRONMENT VARIABLES

I<WARNING: ignoring these settings may cause unintended side effects in code that might fork>

The behavior of Devel::NYTProf may be modified substantially through the use of
a few environment variables.

=over 4

=item trace=N

Set trace level to N. 0 is off (the default). Higher values cause more detailed trace output.

=item allowfork

Enables fork detection and file locking and disables output buffering.  This will have a severe effect on performance, so use only with code that can fork. You B<MUST> use this with code that forks! [default: off]

=item usecputime

Measure user + system CPU time instead of the real elapsed 'wall clock' time (which is the default).

Measuring CPU time has the advantage of making the measurements independant of
time spent blocked waiting for the cpu or network i/o etc. But it also has the
disadvantage of having I<far> less accurate timings on most systems.

=item use_stdout

Tells the profiler to write output to STDOUT. [default: ./nytprof.out]

=back

=head1 PLATFORM SUPPORT

The Makefile.PL script will automatically try to determine some information
about your system.  This module is mostly XS (which is C, not Perl) and takes
advantage of some less universal GNU C functions. It should work on any GNU C
system. If you encounter a problem, make sure INCLUDE has the path to stdio.h
and ext_stdio.h (if present).  See the CPAN Testers results on the distribution 
page.

=head1 BUGS

No Windows support.  I didn't test on Windows and it probably won't work.

Some eval tests may fail on perl 5.6.x. It is safe for 'force install' and
ignore this.

=head1 SEE ALSO

Mailing list and discussion at L<http://groups.google.com/group/develnytprof-dev>

Public SVN Repository and hacking instructions at L<http://code.google.com/p/perl-devel-nytprof/>

L<nytprofhtml> is a script included that produces html reports.

L<nytprofcsv> is another script included that produces plain text CSV reports.

L<Devel::NYTProf::Reader> is the module that powers the report scripts.  You
might want to check this out if you plan to implement a custom report. Its easy!

=head1 AUTHOR

B<Adam Kaplan>, akaplan at nytimes dotcom

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Adam Kaplan and The New York Times Company

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
