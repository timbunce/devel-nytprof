##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/~akaplan/Devel-NYTProf
##
###########################################################
package Devel::NYTProf;

BEGIN {
	our $VERSION = '0.01';
}

package DB;

BEGIN {
	# disable debugging
	$^P=0x0;

	require XSLoader;
	XSLoader::load('Devel::NYTProf', $Devel::NYTProf::VERSION);

	if ($] < 5.008008) {
		local $^W = 0;
		*_DB = \&DB;
		*DB = sub { goto &_DB }
	}

	# Preloaded methods go here.
	init();

	# enable debugging
	$^P= 0x332;
	# put nothing here
}

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
large Perl applications.  The Times loves Perl and we hope the community will 
benefit from our work as much as we have from theirs.

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

=item allowfork

Enables fork detection and file locking and disables output buffering.  This will have a severe effect on performance, so use only with code that can fork. You B<MUST> use this with code that forks! [default: off]

=item useclocktime

Uses real wall clock time instead of CPU time.  With this setting, the profiler will measure time in units of actual microseconds.  The problem with this is that it includes time that your program was 'running' but not actually executing in the CPU (maybe it was waiting for its turn to run in the cpu, or maybe it was suspended).  If you don't know anything about process scheduling, then don't worry about this setting. [default: off]

=item use_stdout

Tells the profiler to write output to STDOUT. [default: ./nytprof.out]

=back

=head1 PLATFORM SUPPORT

The Makefile.PL script will automatically try to determine some information
about your system.  This module is mostly XS (which is C, not Perl) and takes
advantage of some less universal GNU C functions. It should work on any GNU C
system, but has been verified to work on the following:

=over 4

=item 1.
Solaris 8, (SunOS 5.8)

=item 2.
Solaris 9, (SunOS 5.9)

=item 3.
Ubuntu Linux 7.10 - Gutsy Gibbon

=item 4.
OpenBSD 4.1

=back

With Perl 5.8.6, 5.8.7 and 5.8.8

=head1 BUGS

No Windows support.  I didn't test on Windows and it probably won't work.

=head1 SEE ALSO

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
