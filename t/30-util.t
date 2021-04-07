use Test::More tests => 67;

use Devel::NYTProf::Util qw(
    fmt_time fmt_incl_excl_time
    html_safe_filename
    trace_level
    get_abs_paths_alternation_regex
    get_alternation_regex
    strip_prefix_from_paths
    fmt_float
    calculate_median_absolute_deviation
    _dumper
);
use Cwd;
use File::Spec;

my $us = "µs";

is(fmt_time(0), "0s");

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

is(fmt_incl_excl_time(3, 3), "3.00s");
is(fmt_incl_excl_time(3, 2), "3.00s (2.00+1.00)");
is(fmt_incl_excl_time(3, 2.997), "3.00s (3.00+3.00ms)");
is(fmt_incl_excl_time(0.1, 0.0997), "100ms (99.7+300$us)");
is(fmt_incl_excl_time(4e-5, 1e-5), "40$us (10+30)");

is html_safe_filename('/foo/bar'), 'foo-bar';
is html_safe_filename('\foo\bar'), 'foo-bar';
is html_safe_filename('\foo/bar'), 'foo-bar';
is html_safe_filename('C:foo'), 'C-foo';
is html_safe_filename('C:\foo'), 'C-foo';
is html_safe_filename('<lots>of|\'really\'special*"chars"?'), 'lots-of-really-special-chars';
is html_safe_filename('no.dots.please'), 'no-dots-please';

my $trace_level = (($ENV{NYTPROF}||'') =~ m/\b trace=(\d+) /x) ? $1 : 0;
is trace_level(), $trace_level, "trace_level $trace_level";

my $inc = [
          '../blib/arch',
          '../blib/lib',
          '/usr/home/username//devel-nytprof/t',
          '/usr/home/username//devel-nytprof/blib/arch',
          '/usr/home/username//devel-nytprof/blib/lib',
          't/lib',
          '/usr/local/lib/perl5/site_perl/mach/5.32',
          '/usr/local/lib/perl5/site_perl',
          '/usr/local/lib/perl5/5.32/mach',
          '/usr/local/lib/perl5/5.32',
          '/usr/local/lib/perl5/site_perl/mach/5.32',
          '/usr/local/lib/perl5/site_perl',
          '/usr/local/lib/perl5/5.32/mach',
          '/usr/local/lib/perl5/5.32'
        ];

my $x1 = get_abs_paths_alternation_regex($inc, qr/^|\[/);
is(ref($x1), 'Regexp', "compiled regex");

my $x2 = get_abs_paths_alternation_regex($inc);
is(ref($x2), 'Regexp', "compiled regex");
isnt($x1, $x2, "different regexes");

my $x3 = get_alternation_regex($inc);
is(ref($x3), 'Regexp', "compiled regex");
isnt($x1, $x3, "different regexes");

{
    local $@;
    my $x4;
    eval{ $x4 = get_abs_paths_alternation_regex([], qr/^|\[/); };
    like($@, qr/No paths/, "get_abs_paths_alternation_regex(): got expected exception: first argument is empty");
}

my $rv;
my $p = File::Spec->catfile(cwd(), 't', 'test02.p');
{
    local $@;
    eval { strip_prefix_from_paths({}, $p, '^'); };
    like($@, qr/first argument must be array ref/,
        "strip_prefix_from_paths(): exception with non-arrayref 1st argument");
}
$rv = strip_prefix_from_paths($inc);
ok(! defined $rv, "strip_prefix_from_paths() returned undefined value with no defined paths");
{
    local $@;
    eval { strip_prefix_from_paths($inc, $p, '^'); };
    like($@, qr/second argument must be array ref/,
        "strip_prefix_from_paths(): exception with non-arrayref 2nd argument");
}
$rv = strip_prefix_from_paths($inc, [$p], '^');
ok(! defined $rv, "strip_prefix_from_paths(): anchor specified");
$rv = strip_prefix_from_paths($inc, [$p], undef, undef);
ok(! defined $rv, "strip_prefix_from_paths(): anchor and replacement unspecified");
$rv = strip_prefix_from_paths([], [$p], undef, undef);
ok(! defined $rv, "strip_prefix_from_paths(): empty first argument");

my %floats = (
    444444  => { default => '444444', prec3 => '444444' },
    44444.4 => { default => '44444.40000', prec3 => '44444.400' },
    4444.44 => { default => '4444.44000', prec3 => '4444.440' },
    444.444 => { default => '444.44400', prec3 => '444.444' },
    44.4444 => { default => '44.44440', prec3 => '44.444' },
    4.44444 => { default => '4.44444', prec3 => '4.444' },
    .444444 => { default => '0.44444', prec3 => '0.444' },
    .044444 => { default => '0.04444', prec3 => '0.044' },
);
for my $k (sort {$b <=> $a} keys %floats) {
    my $l = fmt_float($k);
    is($l, $floats{$k}{default}, "fmt_float applied to $k");
    my $m = fmt_float($k, 3);
    is($m, $floats{$k}{prec3}, "fmt_float, precision 3, applied to $k");
}

my $val = '0.00004';
is(fmt_float($val), '4.0e-5', "fmt_float, applied to $val");

my ($median_ref, @values);
@values = ( 1, 2, 3, 4, 5 );
{
    local $@;
    eval { $median_ref = calculate_median_absolute_deviation(@values); };
    like($@, qr/No array ref given/, "calculate_median_absolute_deviation() must take array ref");
}
$median_ref = calculate_median_absolute_deviation(\@values);
is($median_ref->[0], 1, "median distance to median value");
is($median_ref->[1], 3, "median value");

@values = ( 0, 0, 0, 1, 2, 3, 4, 5 );
my $ign = 'ignore zeroes';
$median_ref = calculate_median_absolute_deviation(\@values, $ign);
is($median_ref->[0], 1, "median distance to median value; $ign");
is($median_ref->[1], 3, "median value; $ign");

$median_ref = calculate_median_absolute_deviation(\@values);
is($median_ref->[0], 2, "median distance to median value");
is($median_ref->[1], 2, "median value");

$median_ref = calculate_median_absolute_deviation([]);
is_deeply($median_ref, [0,0],
    "No values in arrayref passed to calculate_median_absolute_deviation()");

my $arr = [ 1 .. 3 ];
my $hsh = { gamma => 'delta', alpha => 'beta' };
my @rvs = _dumper($arr, $hsh);
like($rvs[0], qr/
    \$VAR1\s+=\s+\[\s+1,\n
    \s+2,\n
    \s+3\n
    \];\n
    /sx, "array ref dumped as expected");
like($rvs[1], qr/
    \$VAR2\s+=\s+\{\n
    \s+?'alpha'\s+=>\s+'beta',\n
    \s+?'gamma'\s+=>\s+'delta'\n
    \};\n
/sx, "hash ref dumped as expected");

