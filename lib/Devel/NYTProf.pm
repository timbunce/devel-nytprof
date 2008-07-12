# vim: ts=2 sw=2 sts=0 noexpandtab:
##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/dist/Devel-NYTProf/
##
###########################################################
## $Id$
###########################################################
package Devel::NYTProf;

package	# hide the package from the PAUSE indexer
	DB;

	# Enable specific perl debugger flags.
	# Set the flags that influence compilation ASAP so we get full details
	# (sub line ranges etc) of modules loaded as a side effect of loading
	# Devel::NYTProf::Core (ie XSLoader, strict, Exporter etc.)
	$^P = 0x010 # record line range of sub definition
	    | 0x100 # informative "file" names for evals
	    | 0x200;# informative names for anonymous subroutines

	# XXX hack, need better option handling
	my $use_db_sub = ($ENV{NYTPROF} && $ENV{NYTPROF} =~ m/\buse_db_sub=1\b/);

	$^P |=0x002 # line-by-line profiling (if $DB::single true)
	    | 0x020 # start (after BEGINs) with single-step on
			if $use_db_sub;

	require Devel::NYTProf::Core; # loads XS

	if ($use_db_sub) {	# install DB::DB sub
		*DB = ($] < 5.008008)
			? sub { goto &DB_profiler } # workaround bug in old perl versions (slow)
			: \&DB_profiler;
	}

	init_profiler(); # provides true return value for module

	# put nothing here!

__END__

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

=head1 NAME

Devel::NYTProf - Powerful feature-rich perl source code profiler

=head1 SYNOPSIS

 # profile code and write database to ./nytprof.out
 perl -d:NYTProf some_perl.pl

 # convert database into html files, e.g., ./nytprof/index.html
 nytprofhtml

 # or into comma seperated files, e.g., ./nytprof/*.csv
 nytprofcsv

=head1 DESCRIPTION
 
Devel::NYTProf is a powerful feature-rich perl source code profiler.

 * Performs per-line statement profiling for fine detail
 * Performs per-subroutine statement profiling for overview
 * Performs per-block profiling (the first profiler to do so)
 * Performs inclusive timing of subroutines, per calling location
 * Accounts correctly for time spent after calls return
 * Can profile compile-time activity or just run-time
 * Uses novel techniques for efficient profiling
 * Very fast - the fastest line-profiler for perl
 * Handles applications that fork, with no performance cost
 * Immune from noise caused by profiling overheads and i/o
 * Program being profiled can stop/start the profiler
 * Generates richly annotated and cross-linked html reports
 * Trivial to use with mod_perl - add one line to httpd.conf
 * Includes an extensive test suite
 * Tested on very large codebases

=head1 PROFILING

Usually you'd load Devel::NYTProf on the command line using the perl -d option:

 perl -d:NYTProf some_perl.pl

To save typing the ':NYTProf' you could set the PERL5DB env var 

 PERL5DB='use Devel::NYTProf'

and then just perl -d would work:

 perl -d some_perl.pl

Or you can avoid the need to add the -d option at all by using the C<PERL5OPT> env var:

  PERL5OPT=-d:NYTProf

That's also very handy when you can't alter the perl command line being used to
run the script you want to profile.

=head1 ENVIRONMENT VARIABLES

The behavior of Devel::NYTProf may be modified by setting the 
environment variable C<NYTPROF>.  It is possible to use this environment
variable to effect multiple setting by separating the values with a C<:>.  For
example:

    export NYTPROF=trace=2:begin=1:file=/tmp/nytprof.out

=over 4

=item trace=N

Set trace level to N. 0 is off (the default). Higher values cause more detailed trace output.

=item begin=1

Include compile-time activity in the profile. Currently that's not the default,
but that's likely to change in future.

=item subs=0

Set to 0 to disable the collection of subroutine inclusive timings.

=item blocks=0

Set to 0 to disable the determination of block and subroutine location per statement.
This makes the profiler about 50% faster (as of July 2008) but you loose some
valuable information. The extra cost is likely to be reduced in later versions
anyway, as little optimization has been done on that part of the code.
The profiler is fast enough that you shouldn't need to do this.

=item leave=0

Set to 0 to disable the extra work done to allocate times accurately when
returning into the middle of statement. For example leaving a subroutine
and returning into the middle of statement, or re-evaluting a loop condition.

Normally line-based profilers measure the time between starting one 'statement'
and starting the next. So when a subroutine call returns, the time spent
copying the return value and evaluating and remaining expressions in the
calling statement, get incorrectly allocated to the last statement executed in
the subroutine. Similarly for loop conditions.

This feature also ensures that in embedded environments, such as mod_perl,
the last statement executed doesn't accumulate the time spent 'outside perl'.

NYTProf is the only line-level profiler to measure these times correctly.
The profiler is fast enough that you shouldn't need to disable this feature.


=item use_db_sub=1

Set to 1 to enable use of the traditional DB::DB() subroutine to perform
profiling, instead of the faster 'opcode redirection' technique that's used by
default. It also disables some extra mechanisms that help ensure more accurate
results for things like the last statements in subroutines.

If you find a use, or need, for use_db_sub=1 then please let us know,
otherise this vestige of old slower ways is likely to be removed.

=item usecputime=1

Measure user + system CPU time instead of the real elapsed 'wall clock' time (which is the default).

Measuring CPU time has the advantage of making the measurements independant of
time spent blocked waiting for the cpu or network i/o etc. But it also has the
severe disadvantage of having I<far> less accurate timings on most systems.

=item file=...

Specify the output file to write profile data to (default: './nytprof.out').

=back

=head1 REPORTS

The L<Devel::NYTProf::Data> module provides a low-level interface for loading
teh profile data.

The L<Devel::NYTProf::Reader> module provides an interface for generating
arbitrary reports.  This means that you can implement your own output format in
perl.

Included in the bin directory of this distribution are two scripts
which implement the L<Devel::NYTProf::Reader> interface: 

=over 4

=item * 
nytprofcsv - creates comma delimited profile reports

=item *
nytprofhtml - creates attractive, richly annotated, and fully cross-linked html
reports (including statistics, source code and color highlighting)

=back

=head1 LIMITATIONS

=head2 Only profiles code loaded after this module

Loading via the perl -d option ensures it's loaded first.

=head2 threads

C<Devel::NYTProf> is not currently thread safe.

=head2 For perl versions before 5.8.8 it may change what caller() returns

For example, the Readonly module croaks with an "Invalid tie" when profiled with
perl versions before 5.8.8. That's because it's explicitly checking for certain
values from caller().  We're not quite sure what the cause is yet.

=head2 Subroutine exclusive time is not (currently) available

Time spent within a subroutine, exclusive of time spent in any subroutines it
calls, it not currently avalable. It's planned to be added soon.

=head2 Windows

Currently there's no support for Windows.

=head1 BUGS

Possibly.

=head1 SEE ALSO

Mailing list and discussion at L<http://groups.google.com/group/develnytprof-dev>

Public SVN Repository and hacking instructions at L<http://code.google.com/p/perl-devel-nytprof/>

L<nytprofhtml> is a script included that produces html reports.

L<nytprofcsv> is another script included that produces plain text CSV reports.

L<Devel::NYTProf::Reader> is the module that powers the report scripts.  You
might want to check this out if you plan to implement a custom report. Its easy!

=head1 AUTHOR

B<Adam Kaplan>, C<< <akaplan at nytimes.com> >>.
B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>.
B<Steve Peters>, C<< <steve at fisharerojo.org> >>.

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2008 by Adam Kaplan and The New York Times Company.
  Copyright (C) 2008 by Tim Bunce, Ireland.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=head1 HISTORY

A bit of history and a shameless plug...

NYTProf stands for 'New York Times Profiler'. Indeed, this module was initially
developed from Devel::FastProf by The New York Times Co. to help our developers
quickly identify bottlenecks in large Perl applications.  The NY Times loves
Perl and we hope the community will benefit from our work as much as we have
from theirs.

Please visit L<http://open.nytimes.com>, our open source blog to see what we
are up to, L<http://code.nytimes.com> to see some of our open projects and then
check out L<http://nytimes.com> for the latest news!

=head2 Background

Subroutine-level profilers:

  Devel::DProf        | 1995-10-31 | ILYAZ
  Devel::AutoProfiler | 2002-04-07 | GSLONDON
  Devel::Profiler     | 2002-05-20 | SAMTREGAR
  Devel::Profile      | 2003-04-13 | JAW
  Devel::DProfLB      | 2006-05-11 | JAW
  Devel::WxProf       | 2008-04-14 | MKUTTER

Statement-level profilers:

  Devel::SmallProf    | 1997-07-30 | ASHTED
  Devel::FastProf     | 2005-09-20 | SALVA
  Devel::NYTProf      | 2008-03-04 | AKAPLAN
  Devel::Profit       | 2008-05-19 | LBROCARD

Devel::NYTProf is a (now distant) fork of Devel::FastProf, which was itself an
evolution of Devel::SmallProf.

Adam Kaplan took Devel::FastProf and added html report generation (based on
Devel::Cover) and a test suite - a tricky thing to do for a profiler.
Meanwhile Tim Bunce had been extending Devel::FastProf to add novel
per-sub and per-block timing, plus subroutine caller tracking.

When Devel::NYTProf was released Tim switched to working on Devel::NYTProf
because the html report would be a good way to show the extra profile data, and
the test suite made development much easier and safer.

Then he went a little crazy and added a slew of new features, in addition to
per-sub and per-block timing and subroutine caller tracking. These included the
'opcode interception' method of profiling, ultra-fast and robust inclusive
subroutine timing, doubling performance, plus major changes to html reporting
to display all the extra profile call and timing data in richly annotated and
cross-linked reports.

Steve Peters came on board along the way with patches for portability and to
keep NYTProf working with the latest development perl versions.

Adam's work is sponsored by The New York Times Co. L<http://open.nytimes.com>.
Tim's work was partly sponsored by Shopzilla. L<http://www.shopzilla.com>.

=cut
