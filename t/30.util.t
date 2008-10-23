use Test::More tests => 15;

use Devel::NYTProf::Util qw(fmt_time);

my $us = "&micro;s";

is(fmt_time(0), "0");

is(fmt_time(1.1253e-10), "0ns");
is(fmt_time(1.1253e-9), "1ns");
is(fmt_time(1.1253e-8), "11ns");
is(fmt_time(1.1253e-7), "113ns");
is(fmt_time(1.1253e-6), "1$us");
is(fmt_time(1.1253e-5), "11$us");
is(fmt_time(1.1253e-4), "113$us");
is(fmt_time(1.1253e-3), "1.13ms");
is(fmt_time(1.1253e-2), "11.3ms");
is(fmt_time(1.1253e-1), "113ms");
is(fmt_time(1.1253e-0), "1.13s");
is(fmt_time(1.1253e+1), "11.3s");
is(fmt_time(1.1253e+2), "113s");
is(fmt_time(1.1253e+3), "1125s");
