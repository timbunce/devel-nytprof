use strict;
use warnings;
use Carp;
use Config qw(%Config);
use Devel::NYTProf::Reader;
use Test::More;
use File::Spec;
use File::Temp qw( tempdir );
use Devel::NYTProf::Constants qw(
    NYTP_DEFAULT_COMPRESSION
    NYTP_ZLIB_VERSION
);

plan skip_all => "needs different profile data for testing on longdouble builds"
    if (defined $Config{uselongdouble} and $Config{uselongdouble} eq 'define');

my $file = "./t/nytprof_11-reader.out.txt";
croak "No $file" unless -f $file;

plan skip_all => "$file doesn't work unless NYTP_ZLIB_VERSION is set" unless NYTP_ZLIB_VERSION();

# new()

my $reporter = Devel::NYTProf::Reader->new($file, { quiet => 1 });
ok(defined $reporter, "Devel::NYTProf::Reader->new returned defined entity");
isa_ok($reporter, 'Devel::NYTProf::Reader');

# output_dir() / get_param() / set_param()

my $tdir = tempdir( CLEANUP => 1 );
ok($reporter->output_dir($tdir), "output_dir set");
is($reporter->output_dir(), $tdir, "output_dir() returned value already set");
is($reporter->get_param('output_dir'), $tdir, "get_param() returned expected value");
is($reporter->set_param('output_dir'), $tdir,
       "set_param() returned expected value; value already defined");

{
    local $@;
    my $param = 'foobar';
    eval { $reporter->set_param($param => sub {}); };
    like($@, qr/Attempt to set $param to.*?failed: $param is not a valid parameter/,
        "set_param(): caught exception for invalid parameter");
}
$reporter->set_param(mk_report_source_line => sub {
    my ($linenum, $line, $stats_for_line, $statistics, $profile, $filestr) = @_;
    $line =~ s/^\s*//;
    my $delim = ',';

	my $time  = $stats_for_line->{'time'} || 0;
	my $calls = $stats_for_line->{'calls'} || 0;
	$time  += $stats_for_line->{evalcall_stmts_time_nested} || 0;

    my $text = sprintf("%f%s%g%s%f%s%s\n",
        $time, $delim,
        $calls, $delim,
		($calls) ? $time/$calls : 0, $delim,
        $line,
    );
    return $text;
});
is(ref($reporter->{mk_report_source_line}), 'CODE', "mk_report_source_line set");

$reporter->set_param(mk_report_xsub_line => sub { "" });
is(ref($reporter->{mk_report_xsub_line}), 'CODE', "mk_report_xsub_line set");
is($reporter->get_param('mk_report_xsub_line'), "", "get_param() returned expected value");

# file_has_been_modified()

my $ffile = "./t/foobar.nytprof_11-reader.out.txt";
ok(!defined($reporter->file_has_been_modified($ffile)),
    "file_has_been_modified(): nonexistent file");

# current_level()

is($reporter->get_param('current_level'), '',
    "param current_level starts as empty string");
my $expected_level = 'line';
is($reporter->current_level(), $expected_level,
    "current_level(): without argument, defaults to $expected_level");
$expected_level = 'block';
is($reporter->current_level($expected_level), $expected_level,
    "current_level(): with argument, set to $expected_level");
$expected_level = 'line';
is($reporter->current_level($expected_level), $expected_level,
    "current_level(): with argument, set to $expected_level");

# report()

{
    local $@;
    eval { $reporter->report({ quiet => 1 } ); };
    ok(! $@, "report() ran without exception");
}
my $csvcount = 0;
opendir my $DIRH, $tdir or croak "Unable to open $tdir for reading";
while (my $f = readdir $DIRH) {
    chomp $f;
    $csvcount++ if $f =~ m/\.csv$/;
}
closedir $DIRH or croak "Unable to close $tdir after reading";
is($csvcount, 3, "3 csv reports created");

# _output_additional()

my $fname = 'hello.txt';
my $content = "hello world\n";
my $expected_file = File::Spec->catfile($tdir, $fname);
$reporter->_output_additional($fname, $content);
ok(-f $expected_file, "_output_additional() created file");
{
    local $/ = undef;
    open my $fh, "<", $expected_file or croak "Can't open $expected_file: $!";
    my $seen_content = <$fh>;
    close $fh or croak "Can't close $expected_file: $!";
    is($seen_content, $content, "additional file has expected content");
}

# fname_for_fileinfo()

{
    my $profile = $reporter->{profile};
    my @all_fileinfos = $profile->all_fileinfos;
    my @fis = @all_fileinfos;
    if ($reporter->current_level() ne 'line') {
        @fis = grep { not $_->is_eval } @fis;
    }
    my $fname;
    {
        local $@;
        eval { $reporter->fname_for_fileinfo(); };
        like($@, qr/No fileinfo/,
            "fname_for_fileinfo(): caught exception for lack of first argument");
    }
    $fname = $reporter->fname_for_fileinfo($fis[0]);
    like($fname, qr/test01-p-1-line/,
        "fname_for_fileinfo() returned expected value");
    $fname = $reporter->fname_for_fileinfo($fis[0], 'block');
    like($fname, qr/test01-p-1-block/,
        "fname_for_fileinfo() returned expected value, argument supplied");
}

# url_for_sub() / href_for_sub()

{
    my $profile = $reporter->{profile};
    my %subname_subinfo_map = %{ $profile->subname_subinfo_map };
    my %expect = (
        'main::bar'         =>  { subregex => qr/(?:t-)?test01-p-1-line\.html#6/,
                                  hrfregex => qr/href="(?:t-)?test01-p-1-line\.html#6"/,
                                },
        'main::baz'         =>  { subregex => qr/(?:t-)?test01-p-1-line\.html#10/,
                                  hrfregex => qr/href="(?:t-)?test01-p-1-line\.html#10"/,
                                },
        'main::foo'         =>  { subregex => qr/(?:t-)?test01-p-1-line\.html#1/,
                                  hrfregex => qr/href="(?:t-)?test01-p-1-line\.html#1"/,
                                },
        'main::CORE:print'  =>  { subregex => qr/(?:t-)?test01-p-1-line\.html#main__CORE_print/,
                                  hrfregex => qr/href="(?:t-)?test01-p-1-line\.html#main__CORE_print"/,
                                },
    );
    while ( my ($subname, $si) = each %subname_subinfo_map ) {
        next unless $si->incl_time;
        like($reporter->url_for_sub($subname), $expect{$subname}{subregex},
            "url_for_sub() returned expected value for $subname");
        like($reporter->href_for_sub($subname), $expect{$subname}{hrfregex},
            "href_for_sub() returned expected value for $subname");
    }
}

# href_for_file()

{
    my $profile = $reporter->{profile};
    my @fis = sort { $b->meta->{'time'} <=> $a->meta->{'time'} }
        $profile->noneval_fileinfos;
    my %levels = reverse %{$profile->get_profile_levels};
    my %expect = (
        line    => qr/href="(?:t-)?test01-p-1-line.html"/,
        block   => qr/href="(?:t-)?test01-p-1-block.html"/,
        sub     => qr/href="(?:t-)?test01-p-1-sub.html"/,
    );
    my %hrefs = map { $_ => $reporter->href_for_file($fis[0], undef, $_) }
                grep { $levels{$_} } qw(line block sub);
    for my $h (keys %hrefs) {
        like($hrefs{$h}, qr/$expect{$h}/, "Got expected href for $h");
    }
}

done_testing();
