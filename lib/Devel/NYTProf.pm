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

our $VERSION = '2.11';

package    # hide the package from the PAUSE indexer
    DB;

# Enable specific perl debugger flags (others may be set later).
# Set the flags that influence compilation ASAP so we get full details
# (sub line ranges etc) of modules loaded as a side effect of loading
# Devel::NYTProf::Core (ie XSLoader, strict, Exporter etc.)
# See "perldoc perlvar" for details of the $^P ($PERLDB) flags
$^P = 0x010     # record line range of sub definition
    | 0x100     # informative "file" names for evals
    | 0x200;    # informative names for anonymous subroutines

require Devel::NYTProf::Core;    # loads XS and sets options

# XXX hack, need better option handling e.g., add DB::get_option('use_db_sub')
my $use_db_sub = ($ENV{NYTPROF} && $ENV{NYTPROF} =~ m/\buse_db_sub=1\b/);
if ($use_db_sub) {                     # install DB::DB sub
    *DB = ($] < 5.008008)
        ? sub { goto &DB_profiler }    # workaround bug in old perl versions (slow)
        : \&DB_profiler;
}
sub sub { die "DB::sub" }              # needed for perl <5.8.7 (<perl@24265)

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

  # or into comma separated files, e.g., ./nytprof/*.csv
  nytprofcsv

=head1 DESCRIPTION

Devel::NYTProf is a powerful feature-rich perl source code profiler.

=over

=item *

Performs per-line statement profiling for fine detail

=item *

Performs per-subroutine statement profiling for overview

=item *

Performs per-block statement profiling (the first profiler to do so)

=item *

Accounts correctly for time spent after calls return

=item *

Performs inclusive and exclusive timing of subroutines

=item *

Subroutine times are per calling location (a powerful feature)

=item *

Can profile compile-time activity, just run-time, or just END time

=item *

Uses novel techniques for efficient profiling

=item *

Sub-microsecond (100ns) resolution on systems with clock_gettime()

=item *

Very fast - the fastest statement and subroutine profilers for perl

=item *

Handles applications that fork, with no performance cost

=item *

Immune from noise caused by profiling overheads and I/O

=item *

Program being profiled can stop/start the profiler

=item *

Generates richly annotated and cross-linked html reports

=item *

Trivial to use with mod_perl - add one line to httpd.conf

=item *

Includes an extensive test suite

=item *

Tested on very large codebases

=back

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
be useful when analyzing the performance. It also records the filename and line
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

Any colon or equal characters in a value can be escaped by preceding them with
a backslash.

=head2 addpid=1

Append the current process id to the end of the filename.

This avoids concurrent, or consecutive, processes from overwriting the same file.

=head2 trace=N

Set trace level to N. 0 is off (the default). Higher values cause more detailed
trace output. Trace output is written to STDERR or wherever the L</log=F>
option has specified.

=head2 log=F

Specify the name of the file that L</trace=N> output should be written to.

=head2 start=...

Specify at which phase of program execution the profiler should be enabled:

  start=begin - start immediately (the default)
  start=init  - start at beginning of INIT phase (after compilation)
  start=end   - start at beginning of END phase
  start=no    - don't automatically start

The start=no option is handy if you want to explicitly control profiling
by calling DB::enable_profile() and DB::disable_profile() yourself.

=head2 optimize=0

Disable the perl optimizer.

By default NYTProf leaves perl's optimizer enabled.  That gives you more
accurate profile timing overall, but can lead to I<odd> statement counts for
individual sets of lines. That's because the perl's peephole optimizer has
effectively rewritten the statements but you can't see what the rewritten
version looks like.

For example:

  1     if (...) {
  2         return;
  3     }

may be rewritten as

  1    return if (...)

so the profile won't show a statement count for line 2 in your source code
because the C<return> was merged into the C<if> statement on the preceding line.

Using the C<optimize=0> option disables the optimizer so you'll get lower
overall performance but more accurately assigned statement counts.

If you find any other examples of the effect of optimizer on NYTProf output
(other than performance, obviously) please let us know.

=head2 subs=0

Set to 0 to disable the collection of subroutine caller and timing details.

=head2 blocks=0

Set to 0 to disable the determination of block and subroutine location per statement.
This makes the profiler about 50% faster (as of July 2008) and produces smaller
output files, but you lose some valuable information. The extra cost is likely
to be reduced in later versions anyway, as little optimization has been done on
that part of the code.

=head2 stmts=0

Set to 0 to disable the statement profiler. (Implies C<blocks=0>.)
The reports won't contain any statement timing detail.

This significantly reduces the overhead of the profiler and can also be useful
for profiling large applications that would normally generate a very large
profile data file.

=head2 leave=0

Set to 0 to disable the extra work done by the statement profiler
to allocate times accurately when
returning into the middle of statement. For example leaving a subroutine
and returning into the middle of statement, or re-evaluating a loop condition.

This feature also ensures that in embedded environments, such as mod_perl,
the last statement executed doesn't accumulate the time spent 'outside perl'.

NYTProf is the only line-level profiler to measure these times correctly.
The profiler is fast enough that you shouldn't need to disable this feature.

=head2 findcaller=1

Force NYTProf to recalculate the name of the caller of the each sub instead of
'inheriting' the name calculated when the caller was entered. (Rarely needed,
but might be useful in some odd cases.)

=head2 use_db_sub=1

Set to 1 to enable use of the traditional DB::DB() subroutine to perform
profiling, instead of the faster 'opcode redirection' technique that's used by
default. Also effectively sets C<leave=0> (see above).

The default 'opcode redirection' technique can't profile subroutines that were
compiled before NYTProf was loaded. So using use_db_sub=1 can be useful in
cases where you can't load the profiler early in the life of the application.

=head2 savesrc=1

Save a copy of all source code into the profile data file. This makes the file
self-contained, so the reporting tools no longer depend on having the original
source code files available. So it also insulates you from later changes to
those files that would normally make the reports out of sync with the data.

By default NYTProf saved some source code: the arguments to the C<perl -e>
option, the script fed to perl via STDIN when using C<perl ->, and the source
code of string evals. (Currently string eval  source code isn't available in
the reports. Patches welcome.)

If you're using perl 5.10.0 or 5.8.8 (or earlier) then you need to also enable
the C<use_db_sub=1> option otherwise perl doesn't make the source code
available to NYTProf. Perl 5.8.9 and 5.10.1+ don't require that.

=head2 slowops=N

Profile perl opcodes that can be slow. These include opcodes that make system
calls, such as C<print>, C<read>, C<sysread>, C<socket> etc., plus regular
expression opcodes like C<subst> and C<match>.

If C<N> is 0 then slowops profiling is disabled.

If C<N> is 1 then all the builtins are treated as being defined in the C<CORE>
package. So times for C<print> calls from anywhere in your code are merged and
accounted for as calls to an xsub called C<CORE::print>.

If C<N> is 2 then builtins are treated as being defined in the package that
calls them. So calls to C<print> from package C<Foo> are treated as calls to an
xsub called C<Foo::CORE:print>. Note the single colon after CORE.

Default is 0 as this is a new feature and still somewhat experimental.
The default may change to 2 in a future release.

The opcodes are currently profiled using their internal names, so C<printf> is C<prtf>
and the C<-x> file test is C<fteexec>. This is likely to change in future.

=head2 usecputime=1

Measure user CPU + system CPU time instead of the real elapsed 'wall clock'
time (which is the default).

Measuring CPU time has the advantage of making the measurements independent of
time spent blocked waiting for the cpu or network i/o etc. But it also has the
severe disadvantage of having typically I<far> less accurate timings.

Most systems use a 0.01 second granularity. With modern processors having multi-
gigahertz clocks, 0.01 seconds is like a lifetime. The cpu time clock 'ticks'
happen so rarely relative to the activity of a most applications that you'd
have to run the code for many hours to have any hope of reasonably useful results.

A better alternative would be to use the C<clock=N> option to select a
high-resolution cpu time clock, if available on your system.

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
integer id of the clock (which may vary between operating system types).
If the clock you select isn't available then CLOCK_REALTIME is used.

See L</CLOCKS> for more information.

=head2 sigexit=1

When perl exits normally it runs any code defined in C<END> blocks.
NYTProf defines an END block that finishes profiling and writes out the final
profile data.

If the process ends due to a signal then END blocks are not executed.
The C<sigexit> option tells NYTProf to catch some signals (e.g. INT, HUP, PIPE,
SEGV, BUS) and ensure a usable by executing:

    DB::finish_profile();
    exit 1;

You can also specify which signals to catch in this way by listing them,
seperated by commas, as the value of the option (case is not significant):

    sigexit=int,hup

=head2 forkdepth=N

When a perl process that is being profiled executes a fork() the child process
is also profiled. The forkdepth option can be used to control this. If
forkdepth is zero then profiling will be disabled in the child process.

If forkdepth is greater than zero then profiling will be enabled in the child
process and the forkdepth value in that process is decremented by one.

If forkdepth is -1 (the default) then there's no limit on the number of
generations of children that are profiled.

=head1 RUN-TIME CONTROL OF PROFILING

You can profile only parts of an application by calling DB::disable_profile()
to stop collecting profile data, and calling DB::enable_profile() to start
collecting profile data.

Using the C<start=no> option lets you leave the profiler disabled initially
until you call DB::enable_profile() at the right moment.

The profile output file can't be used until it's been properly completed and
closed.  Calling DB::disable_profile() doesn't do that.  To make a profile file
usable before the profiled application has completed you can call
DB::finish_profile(). Alternatively you could call DB::enable_profile($newfile).

=head2 DB::disable_profile()

Stops collection of profile data.

Subroutine calls which were made while profiling was enabled and are still on
the call stack (have not yet exited) will still have their profile data
collected when they exit.

=head2 DB::enable_profile($newfile)

Enables collection of profile data. If $newfile is true the profile data will be
written to $newfile (after completing and closing the previous file, if any).
If $newfile already exists it will be deleted first.

=head2 DB::finish_profile()

Calls DB::disable_profile(), then completes the profile data file by writing
subroutine profile data, and then closes the file. The in memory subroutine
profile data is then discarded.

=head1 REPORTS

The L<Devel::NYTProf::Data> module provides a low-level interface for loading
the profile data.

The L<Devel::NYTProf::Reader> module provides an interface for generating
arbitrary reports.  This means that you can implement your own output format in
perl. (Though the module is in a state of flux and may be deprecated soon.)

Included in the bin directory of this distribution are two scripts
which implement the L<Devel::NYTProf::Reader> interface: 

=over 12

=item nytprofcsv

creates comma delimited profile reports

=item nytprofhtml

creates attractive, richly annotated, and fully cross-linked html
reports (including statistics, source code and color highlighting)

=back

=head1 CLOCKS

Here we discuss the way NYTProf gets high-resolution timing information from
your system and related issues.

=head2 POSIX Clocks

These are the clocks that your system may support if it supports the POSIX
C<clock_gettime()> function. Other clock sources are listed in the
L</Other Clocks> section below.

The C<clock_gettime()> interface allows clocks to return times to nanosecond
precision. Of course few offer nanosecond I<accuracy> but the extra precision
helps reduce the cumulative error that naturally occurs when adding together
many timings. When using these clocks NYTProf outputs timings as a count of 100
nanosecond ticks.

=head3 CLOCK_REALTIME

CLOCK_REALTIME is typically the system's main high resolution 'wall clock time'
source.  The same source as used for the gettimeofday() call used by most kinds
of perl benchmarking and profiling tools.

If your system doesn't support clock_gettime() then NYTProf will use
gettimeofday(), or the nearest equivalent,

The problem with real time is that it's far from simple. It tends to drift and
then be reset to match 'reality', either sharply or by small adjustments (via the
adjtime() system call).

Surprisingly, it can also go backwards, for reasons explained in
http://preview.tinyurl.com/5wawnn

=head3 CLOCK_MONOTONIC

CLOCK_MONOTONIC represents the amount of time since an unspecified point in
the past (typically system start-up time).  It increments uniformly
independent of adjustments to 'wallclock time'.

=head3 CLOCK_VIRTUAL

CLOCK_VIRTUAL increments only when the CPU is running in user mode on behalf of the calling process.

=head3 CLOCK_PROF

CLOCK_PROF increments when the CPU is running in user I<or> kernel mode.

=head3 CLOCK_PROCESS_CPUTIME_ID

CLOCK_PROCESS_CPUTIME_ID represents the amount of execution time of the process associated with the clock.

=head3 CLOCK_THREAD_CPUTIME_ID

CLOCK_THREAD_CPUTIME_ID represents the amount of execution time of the thread associated with the clock.

=head3 Finding Available POSIX Clocks

On unix-like systems you can find the CLOCK_* clocks available on you system
using a command like:

  grep -r 'define *CLOCK_' /usr/include

Look for a group that includes CLOCK_REALTIME. The integer values listed are
the clock ids that you can use with the C<clock=N> option.

A future version of NYTProf should be able to list the supported clocks.

=head2 Other Clocks

This section lists other clock sources that NYTProf may use.

=head3 gettimeofday

This is the traditional high resolution time of day interface for most
unix-like systems. It's used on platforms like Mac OS X which don't
(yet) support C<clock_gettime()>.

With this clock NYTProf outputs timings as a count of 1 microsecond ticks.

=for comment re high resolution timing for OS X:
http://developer.apple.com/qa/qa2004/qa1398.html
http://www.macresearch.org/tutorial_performance_and_time
http://cocoasamurai.blogspot.com/2006/12/tip-when-you-must-be-precise-be-mach.html
http://boredzo.org/blog/archives/2006-11-26/how-to-use-mach-clocks

=head3 Time::HiRes

On systems which don't support C<clock_gettime()> or C<gettimeofday()>
NYTProf falls back to using the L<Time::HiRes> module.
With this clock NYTProf outputs timings as a count of 1 microsecond ticks.

=head2 Clock References

Relevant specifications and manual pages:

  http://www.opengroup.org/onlinepubs/000095399/functions/clock_getres.html
  http://linux.die.net/man/3/clock_gettime

Why 'realtime' can appear to go backwards:

  http://preview.tinyurl.com/5wawnn

=for comment
http://preview.tinyurl.com/5wawnn redirects to:
http://groups.google.com/group/comp.os.linux.development.apps/tree/browse_frm/thread/dc29071f2417f75f/ac44671fdb35f6db?rnum=1&_done=%2Fgroup%2Fcomp.os.linux.development.apps%2Fbrowse_frm%2Fthread%2Fdc29071f2417f75f%2Fc46264dba0863463%3Flnk%3Dst%26rnum%3D1%26

=for comment - these links seem broken
http://webnews.giga.net.tw/article//mailing.freebsd.performance/710
http://sean.chittenden.org/news/2008/06/01/

=head1 LIMITATIONS

=head2 threads

C<Devel::NYTProf> is not currently thread safe. If you'd be interested in
helping to make it thread safe then please get in touch with us.

=head2 For perl < 5.8.8 it may change what caller() returns

For example, the L<Readonly> module croaks with "Invalid tie" when profiled with
perl versions before 5.8.8. That's because L<Readonly> explicitly checking for
certain values from caller(). The L<NEXT> module is also affected.

=head2 For perl < 5.10.1 it can't see some implicit calls and callbacks

For perl versions prior to 5.8.9 and 5.10.1, some implicit subroutine calls
can't be seen by the I<subroutine> profiler. Technically this affects calls
made via the various perl C<call_*()> internal APIs.

For example, the C<TIE><whatever> subroutine called by C<tie()>, all calls
made via operator overloading, and callbacks from XS code, are not seen.

The effect is that time in the subroutines for those calls is
accumulated by the subs that trigger them. So time spent in calls invoked by
perl to handle overloading are accumulated by the subroutines that trigger
overloading (so it is measured, but the cost is dispersed across possibly many
calling locations).

Although the calls aren't seen by the subroutine profiler, the individual
I<statements> executed by the code in the called subs are profiled by the
statement profiler.

=head2 goto

The C<goto &foo;> isn't recognized as a subroutine call by the subroutine profiler.

=head2 Calls to XSubs which exit via an exception

Calls to XSubs which exit via an exception are not recorded by subroutine profiler.

=head2 #line directives

The reporting code currently doesn't handle #line directives, but at least it
warns about them. Patches welcome.

=head2 Scope::Upper unwind()

NYTProf is currently incompatible with the deep magic performed by
Scope::Upper's unwind() function. As a partial workaround you can set the
C<subs=0:leave=0> options, but you won't get any subroutine timings.
See L<http://rt.cpan.org/Public/Bug/Display.html?id=50634>

=head1 CAVEATS

=head2 SMP Systems

On systems with multiple processors, which includes most modern machines,
(from Linux docs though applicable to most SMP systems):

  The CLOCK_PROCESS_CPUTIME_ID and CLOCK_THREAD_CPUTIME_ID clocks are realized on
  many platforms using timers from the CPUs (TSC on i386, AR.ITC on Itanium).
  These registers may differ between CPUs and as a consequence these clocks may
  return bogus results if a process is migrated to another CPU.

  If the CPUs in an SMP system have different clock sources then there is no way
  to maintain a correlation between the timer registers since each CPU will run
  at a slightly different frequency. If that is the case then
  clock_getcpuclockid(0) will return ENOENT to signify this condition. The two
  clocks will then only be useful if it can be ensured that a process stays on a
  certain CPU.

  The processors in an SMP system do not start all at exactly the same time and
  therefore the timer registers are typically running at an offset. Some
  architectures include code that attempts to limit these offsets on bootup.
  However, the code cannot guarantee to accurately tune the offsets. Glibc
  contains no provisions to deal with these offsets (unlike the Linux Kernel).
  Typically these offsets are small and therefore the effects may be negligible
  in most cases.

In summary, SMP systems are likely to give 'noisy' profiles.
Setting a L<Processor Affinity> may help.

=head3 Processor Affinity

Processor affinity is an aspect of task scheduling on SMP systems.
"Processor affinity takes advantage of the fact that some remnants of a process
may remain in one processor's state (in particular, in its cache) from the last
time the process ran, and so scheduling it to run on the same processor the
next time could result in the process running more efficiently than if it were
to run on another processor." (From http://en.wikipedia.org/wiki/Processor_affinity)

Setting an explicit processor affinity can avoid the problems described in
L</SMP Systems>.

Processor affinity can be set using the C<taskset> command on Linux.

Note that processor affinity is inherited by child processes, so if the process
you're profiling spawns cpu intensive sub processes then your process will be
impacted by those more than it otherwise would.

=head2 Virtual Machines

I recommend you don't do performance profiling while running in a
virtual machine.  If you do you're likely to find inexplicable spikes
of real-time appearing at unreasonable places in your code. You should pay
less attention to the statement timings and rely more on the subroutine
timings. They will still be noisy but less so than the statement times.

You could also try using the C<clock=N> option to select a high-resolution
I<cpu-time> clock instead of a real-time one. That should be much less
noisy, though you will lose visibility of wait-times due to network
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

Blog posts L<http://blog.timbunce.org/tag/nytprof/> and L<http://technorati.com/search/nytprof>

Public SVN Repository and hacking instructions at L<http://code.google.com/p/perl-devel-nytprof/>

L<nytprofhtml> is a script included that produces html reports.
L<nytprofcsv> is another script included that produces plain text CSV reports.

L<Devel::NYTProf::Reader> is the module that powers the report scripts.  You
might want to check this out if you plan to implement a custom report (though
it's very likely to be deprecated in a future release).

L<Devel::NYTProf::ReadStream> is the module that lets you read a profile data
file as a stream of chunks of data.

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
Tim's work was partly sponsored by Shopzilla L<http://www.shopzilla.com> during 2008.

=cut
