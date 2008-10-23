# vim: ts=8 sw=2 sts=0 noexpandtab:
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

our $VERSION = '2.05';

package    # hide the package from the PAUSE indexer
    DB;

# Enable specific perl debugger flags.
# Set the flags that influence compilation ASAP so we get full details
# (sub line ranges etc) of modules loaded as a side effect of loading
# Devel::NYTProf::Core (ie XSLoader, strict, Exporter etc.)
# See "perldoc perlvar" for details of the $^P flags
$^P = 0x010     # record line range of sub definition
    | 0x100     # informative "file" names for evals
    | 0x200;    # informative names for anonymous subroutines

# XXX hack, need better option handling
my $use_db_sub = ($ENV{NYTPROF} && $ENV{NYTPROF} =~ m/\buse_db_sub=1\b/);

$^P |= 0x002    # line-by-line profiling (if $DB::single true)
    | 0x020     # start (after BEGINs) with single-step on
    if $use_db_sub;

require Devel::NYTProf::Core;    # loads XS

if ($use_db_sub) {               # install DB::DB sub
    *DB = ($] < 5.008008)
        ? sub { goto &DB_profiler }    # workaround bug in old perl versions (slow)
        : \&DB_profiler;
}

init_profiler();                       # provides true return value for module

# put nothing here!

__END__

=head1 NAME

Devel::NYTProf - Powerful feature-rich perl source code profiler

=head1 SYNOPSIS

 # profile code and write database to ./nytprof.out
 perl -d:NYTProf some_perl.pl

 # convert database into a set of html files, e.g., ./nytprof/index.html
 nytprofhtml

 # or into comma seperated files, e.g., ./nytprof/*.csv
 nytprofcsv

=head1 DESCRIPTION

Devel::NYTProf is a powerful feature-rich perl source code profiler.

 * Performs per-line statement profiling for fine detail
 * Performs per-subroutine statement profiling for overview
 * Performs per-block statement profiling (the first profiler to do so)
 * Accounts correctly for time spent after calls return
 * Performs inclusive and exclusive timing of subroutines
 * Subroutine times are per calling location (a powerful feature)
 * Can profile compile-time activity, just run-time, or just END time
 * Uses novel techniques for efficient profiling
 * Sub-microsecond (100ns) resolution on systems with clock_gettime()
 * Very fast - the fastest statement and subroutine profilers for perl
 * Handles applications that fork, with no performance cost
 * Immune from noise caused by profiling overheads and I/O
 * Program being profiled can stop/start the profiler
 * Generates richly annotated and cross-linked html reports
 * Trivial to use with mod_perl - add one line to httpd.conf
 * Includes an extensive test suite
 * Tested on very large codebases

NYTProf is effectively two profilers in one: a statement profiler, and a
subroutine profiler.

=head2 Statement Profiling

The statement profiler measures the time between entering one perl statement
and entering the next. Whenever execution reaches a new statement, the time
since entering the previous statement is calculated and added to the time
associated with the line of the source file that the previous statement starts on.

By default the statement profiler also determines the first line of the current
block and the first line of the current statement, and accumulates times
associated with those. NYTProf is the only Perl profiler to perform block level
profiling.

Another innovation unique to NYTProf is automatic compensation for a problem
inherent in simplistic statement-to-statement timing. Consider a statement that
calls a subroutine and then performs some other work that doesn't execute new
statements, for example:

  foo(...) + mkdir(...);

In all other statement profilers the time spent in remainder of the expression
(mkdir in the example) will be recorded as having been spent I<on the last
statement executed in foo()>! Here's another example:

  while (<>) {
     ...
     1;
  }

After the first time around the loop, any further time spent evaluating the
condition (waiting for input in this example) would be be recorded as having
been spent I<on the last statement executed in the loop>!

NYTProf avoids these problems by intercepting the opcodes which indicate that
control is returning into some previous statement and adjusting the profile
accordingly.

The statement profiler naturally generates a lot of data which is streamed out
to a file in a very compact format. NYTProf takes care to not include the
measurement and writing overheads in the profile times (some profilers produce
'noisy' data due to periodic stdio flushing).

=head2 Subroutine Profiling

The subroutine profiler measures the time between entering a subroutine and
leaving it. It then increments a call count and accumulates the duration.
For each subroutine called, separate counts and durations are stored I<for each
location that called the subroutine>.

Subroutine entry is detected by intercepting the entersub opcode. Subroutine
exit is detected via perl's internal save stack. The result is both extremely
fast and very robust.

=head3 Subroutine Recursion

For subroutines that recurse directly or indirectly, such as Error::try,
the inclusive time is only measured for the outer-most call.

The inclusive times of recursive calls are still measured and are accumulated
separately. Also the 'maximum recursion depth' per calling location is recorded.

=head2 Application Profiling

NYTProf records extra information in the data file to capture details that may
be useful when analysing the performance. It also records the filename and line
ranges of all the subroutines.

NYTProf can profile applications that fork, and does so with no loss of
performance. There's (now) no special 'allowfork' mode. It just works.
NYTProf detects the fork and starts writing a new profile file with the pid
appended to the filename.

=head2 Fast Profiling

The NYTProf profiler is written almost entirely in C and great care has been
taken to ensure it's very efficient.

=head2 Apache Profiling

Just add one line near the start of your httpd.conf file:

 PerlModule Devel::NYTProf::Apache

By default you'll get a F</tmp/nytprof.$$.out> file for the parent process and
a F</tmp/nytprof.$parent.out.$$> file for each worker process.

NYTProf takes care to detect when control is returning back from perl to
mod_perl so time spent in mod_perl (such as waiting for the next request)
does not get allocated to the last statement executed.

Works with mod_perl 1 and 2. See L<Devel::NYTProf::Apache> for more information.

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

=head1 NYTPROF ENVIRONMENT VARIABLE

The behavior of Devel::NYTProf may be modified by setting the 
environment variable C<NYTPROF>.  It is possible to use this environment
variable to effect multiple setting by separating the values with a C<:>.  For
example:

    export NYTPROF=trace=2:start=init:file=/tmp/nytprof.out

=head2 addpid=1

Append the current process id to the end of the filename.

This avoids concurrent, or consecutive, processes from overwriting the same file.

=head2 trace=N

Set trace level to N. 0 is off (the default). Higher values cause more detailed trace output.

=head2 start=...

Specify at which phase of program execution the profiler should be enabled:

  start=begin - start immediately (the default)
  start=init  - start at begining of INIT phase (after compilation)
  start=end   - start at begining of END phase
  start=no    - don't automatically start

The start=no option is handy if you want to explicitly control profiling
by calling DB::enable_profile() and DB::disable_profile() yourself.

=head2 subs=0

Set to 0 to disable the collection of subroutine caller and timing details.

=head2 blocks=0

Set to 0 to disable the determination of block and subroutine location per statement.
This makes the profiler about 50% faster (as of July 2008) and produces smaller
output files, but you loose some valuable information. The extra cost is likely
to be reduced in later versions anyway, as little optimization has been done on
that part of the code.

=head2 leave=0

Set to 0 to disable the extra work done to allocate times accurately when
returning into the middle of statement. For example leaving a subroutine
and returning into the middle of statement, or re-evaluting a loop condition.

This feature also ensures that in embedded environments, such as mod_perl,
the last statement executed doesn't accumulate the time spent 'outside perl'.

NYTProf is the only line-level profiler to measure these times correctly.
The profiler is fast enough that you shouldn't need to disable this feature.

=head2 use_db_sub=1

Set to 1 to enable use of the traditional DB::DB() subroutine to perform
profiling, instead of the faster 'opcode redirection' technique that's used by
default. Also effectively sets C<leave=0> (see above).

The default 'opcode redirection' technique can't profile subroutines that were
compiled before NYTProf was loaded. So using use_db_sub=1 can be useful in
cases where you can't load the profiler early in the life of the application.

=head2 usecputime=1

Measure user CPU + system CPU time instead of the real elapsed 'wall clock'
time (which is the default).

Measuring CPU time has the advantage of making the measurements independant of
time spent blocked waiting for the cpu or network i/o etc. But it also has the
severe disadvantage of having typically I<far> less accurate timings.

Most systems use a 0.01 second granularity. With modern processors having multi-
gigahertz clocks, 0.01 seconds is like a lifetime. The cpu time clock 'ticks'
happen so rarely relative to the activity of a most applications that you'd
have to run the code for many hours to have any hope of reasonably useful results.

(It may be possible to use the C<clock=N> option to select a
high-resolution cpu time clock. I've not tried that yet.
If you try it, please let me know how it works out.)

=head2 file=...

Specify the output file to write profile data to (default: './nytprof.out').

=head2 compress=...

Specify the compression level to use, if NYTProf is compiled with compression
support. Valid values are 0 to 9, with 0 disabling compression. The default is
6 as higher values yield little extra compression but the cpu cost starts to
rise significantly. Using level 1 still gives you a significant reduction in file size.

If NYTProf was not compiled with compression support, this option is silently ignored.

=head2 clock=N

Systems which support the C<clock_gettime()> system call typically
support several clocks. By default NYTProf uses CLOCK_MONOTONIC.
This option enables you to select a different clock by specifying the
integer id of the clock (which may vary between systems). If the clock
you select isn't available then CLOCK_REALTIME is used.

This is a wizardly option and best avoided unless you really know what
you're doing and understand the subtle differences between the clocks.

=head1 SELECTIVE PROFILING

You can profile only parts of an application by calling DB::enable_profile()
and DB::disable_profile() at the appropriate moments.

Using the C<start=no> option lets you leave the profiler disabled until the
right moment, or circumstances, are reached.

=head1 REPORTS

The L<Devel::NYTProf::Data> module provides a low-level interface for loading
the profile data.

The L<Devel::NYTProf::Reader> module provides an interface for generating
arbitrary reports.  This means that you can implement your own output format in
perl. (Though the module is in a state of flux and may be deprecated soon.)

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

=head2 threads

C<Devel::NYTProf> is not currently thread safe. If you'd be interested in
helping to make it thread safe then please get in touch with us.

=head2 For perl versions before 5.8.8 it may change what caller() returns

For example, the Readonly module croaks with an "Invalid tie" when profiled with
perl versions before 5.8.8. That's because L<Readonly> explicitly checking for
certain values from caller().  We're not quite sure what the cause is yet.

=head2 Calls made via operator overloading

Calls made via operator overloading are not noticed by any subroutine profiler.
Though the statements executed by the code in the overload subs are profiled.

=head2 goto

The C<goto &$sub;> isn't recognised as a subroutine call by the subroutine profiler.

=head2 #line directives

The reporting code currently doesn't handle #line directives, but at least it
warns about them. Patches welcome.

=head1 CAVEATS

=head2 Virtual Machines

I recommend you don't do performance profiling while running in a
virtual machine.  If you do you're likely to find inexplicable spikes
of real-time appearing at unreasonable places in your code. You should pay
less attention to the statement timings and rely more on the subroutine
timings. They will still be noisy but less so than the statement times.

You could also try using the C<clock=N> option to select a high-resolution
I<cpu-time> clock instead of a real-time one. That should be much less
noisy, though you will loose visibility of wait-times due to network
and disk I/O, for example.

If your system doesn't support the C<clock=N> option then you could try
using the C<usecputime=1> option. That will give you cpu-time measurements
but only at a very low 1/100th of a second resolution.

=head1 BUGS

Possibly.

=head1 SEE ALSO

Screenshots of L<nytprofhtml> v2.01 reports can be seen at
L<http://timbunce.files.wordpress.com/2008/07/nytprof-perlcritic-index.png> and
L<http://timbunce.files.wordpress.com/2008/07/nytprof-perlcritic-all-perl-files.png>.
A writeup of the new features of NYTProf v2 can be found at
L<http://blog.timbunce.org/2008/07/15/nytprof-v2-a-major-advance-in-perl-profilers/>
and the background story, explaining the "why", can be found at
L<http://blog.timbunce.org/2008/07/16/nytprof-v2-the-background-story/>.

Mailing list and discussion at L<http://groups.google.com/group/develnytprof-dev>

Public SVN Repository and hacking instructions at L<http://code.google.com/p/perl-devel-nytprof/>

L<nytprofhtml> is a script included that produces html reports.
L<nytprofcsv> is another script included that produces plain text CSV reports.

L<Devel::NYTProf::Reader> is the module that powers the report scripts.  You
might want to check this out if you plan to implement a custom report (though
it may be deprecated in a future release).

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
keep NYTProf working with the latest development perl versions. Nicholas Clark
added zip compression. Jan Dubois contributed Windows support.

Adam's work is sponsored by The New York Times Co. L<http://open.nytimes.com>.
Tim's work was partly sponsored by Shopzilla. L<http://www.shopzilla.com>.

=cut
