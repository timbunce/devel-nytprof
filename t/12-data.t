use strict;
use warnings;
use Carp;
use Config qw(%Config);
use Devel::NYTProf::Reader;
use Devel::NYTProf::Util qw( trace_level );
use Test::More;
use File::Spec;
use File::Temp qw( tempdir tempfile );
use Capture::Tiny qw(capture_stdout capture_stderr );
use Devel::NYTProf::Constants qw(
    NYTP_DEFAULT_COMPRESSION
    NYTP_ZLIB_VERSION
);

plan skip_all => "needs different profile data for testing on longdouble builds"
    if (defined $Config{uselongdouble} and $Config{uselongdouble} eq 'define');

my $file = "./t/nytprof_12-data.out.txt";
croak "No $file" unless -f $file;

plan skip_all => "$file doesn't work unless NYTP_ZLIB_VERSION is set" unless NYTP_ZLIB_VERSION();

# General setup

my $reporter = Devel::NYTProf::Reader->new($file, { quiet => 1 });
ok(defined $reporter, "Devel::NYTProf::Reader->new returned defined entity");
isa_ok($reporter, 'Devel::NYTProf::Reader');

my $profile = $reporter->{profile};
isa_ok($profile, 'Devel::NYTProf::Data');

# package_subinfo_map()

{
    my ($pkgref, $subinfo_obj, @keys, @elements, $expect);

    $pkgref = $profile->package_subinfo_map(0,1);
    is(ref($pkgref), 'HASH', "package_subinfo_map(0,1) returned hashref");
    @keys = keys %{$pkgref};
    is(@keys, 1, "1-element hash");
    $expect = 'main';
    is($keys[0], $expect, "Sole element is '$expect'");
    isa_ok($pkgref->{$expect}{""}[0], 'Devel::NYTProf::SubInfo');
    $subinfo_obj = $pkgref->{$expect}{""}[0];
    isa_ok($subinfo_obj, 'Devel::NYTProf::SubInfo');
    $elements[0] = scalar(@{$subinfo_obj});

    $pkgref = $profile->package_subinfo_map(1,1);
    is(ref($pkgref), 'HASH', "package_subinfo_map(1,1) returned hashref");
    @keys = keys %{$pkgref};
    is(@keys, 1, "1-element hash");
    $expect = 'main';
    is($keys[0], $expect, "Sole element is '$expect'");
    $subinfo_obj = $pkgref->{$expect}{""}[0];
    isa_ok($subinfo_obj, 'Devel::NYTProf::SubInfo');
    $elements[1] = scalar(@{$subinfo_obj});
    cmp_ok($elements[0], '!=', $elements[1],
        "Calling package_subinfo_map() with different arguments results in different count of elements in SubInfo object");

    $pkgref = $profile->package_subinfo_map(0,0);
    is(ref($pkgref), 'HASH', "package_subinfo_map(0,0) returned hashref");
    @keys = keys %{$pkgref};
    is(@keys, 1, "1-element hash");
    $expect = 'main::';
    is($keys[0], $expect, "Sole element is '$expect'");
    is(ref($pkgref->{$expect}), 'ARRAY', "That element is array ref");

    $pkgref = $profile->package_subinfo_map(1,0);
    is(ref($pkgref), 'HASH', "package_subinfo_map(1,0) returned hashref");
    @keys = keys %{$pkgref};
    is(@keys, 1, "1-element hash");
    $expect = 'main::';
    is($keys[0], $expect, "Sole element is '$expect'");
    is(ref($pkgref->{$expect}), 'ARRAY', "That element is array ref");
}

# all_fileinfos() / eval_fileinfos() / noneval_fileinfos()

my @all_fileinfos = $profile->all_fileinfos();
is(scalar(@all_fileinfos), 1, "got 1 all_fileinfo");

my @eval_fileinfos = $profile->eval_fileinfos();
is(scalar(@eval_fileinfos), 0, "got 0 eval_fileinfo");

my @noneval_fileinfos = $profile->noneval_fileinfos();
is(scalar(@noneval_fileinfos), 1, "got 1 noneval_fileinfo");

# fileinfo_of()

{
    my $profile;
    my $stdout = capture_stdout {
        $profile = Devel::NYTProf::Data->new( { filename => $file } );
    };
    like($stdout, qr/^Reading $file\nProcessing $file data\n$/s,
        "new(): captured non-quiet output");

    ok(defined $profile, "Direct call of constructor returned defined value");
    isa_ok($profile, 'Devel::NYTProf::Data');

    my ($fi, $stderr);
    $stderr = capture_stderr {
        $fi = $profile->fileinfo_of();
    };
    like($stderr, qr/^Can't resolve fid of undef value/,
        "fileinfo_of: called with argument, caught warning,");
    ok(! defined($fi), "fileinfo_of returned undef");

    my $silent_if_undef = 1;
    $stderr = capture_stderr {
        $fi = $profile->fileinfo_of(undef, $silent_if_undef);
    };
    ok(! $stderr, "fileinfo_of: called without argument, declined warning");
    ok(! defined($fi), "fileinfo_of returned undef");

    my $arg = 'foobar';
    $stderr = capture_stderr {
        $fi = $profile->fileinfo_of($arg);
    };
    like($stderr, qr/^Can't resolve fid of '$arg'/,
        "fileinfo_of: called with unknown argument");
    ok(! defined($fi), "fileinfo_of returned undef");

    $arg = {};
    $stderr = capture_stderr {
        $fi = $profile->fileinfo_of($arg);
    };
    like($stderr, qr/^Can't resolve fid of/,
        "fileinfo_of: called with inappropriate reference");
    ok(! defined($fi), "fileinfo_of returned undef");

    $stderr = capture_stderr {
        $fi = $profile->fileinfo_of($profile);
    };
    like($stderr, qr/^Can't resolve fid of/,
        "fileinfo_of: called with object of class which has no 'fid' method");
    ok(! defined($fi), "fileinfo_of returned undef");

    my $subinfo_obj = $profile->package_subinfo_map(0,1)->{"main"}{""}[0];
    $stderr = capture_stderr {
        $fi = $profile->fileinfo_of($subinfo_obj);
    };
    like($stderr, qr/^Can't resolve fid of/,
        "fileinfo_of: called with object other than Devel::NYTProf::FileInfo");
    ok(! defined($fi), "fileinfo_of returned undef");
}

# subinfo_of() / file_line_range_of_sub()

{
    my $profile = Devel::NYTProf::Data->new({ filename => $file, quiet => 1 });
    ok(defined $profile, "Direct call of constructor returned defined value");
    my %subname_subinfo_map = %{ $profile->subname_subinfo_map };
    my %expect = map { $_ => 1 }
        ( 'main::BEGIN', 'main::CORE:print', 'main::RUNTIME',
          'main::bar',   'main::baz',        'main::foo' );
    my %seen = ();
    for my $sub (keys %subname_subinfo_map) {
        $seen{$sub} = $profile->subinfo_of($sub);
    }
    is_deeply([ sort keys %seen], [ sort keys %expect],
        "subinfo_of: got expected fully qualified subroutine names");

    {
        my ($rv, $stderr);
        $stderr = capture_stderr { $rv = $profile->subinfo_of(undef); };
        ok(!defined $rv, "subinfo_of returned undef");
        like($stderr, qr/Can't resolve subinfo of undef value/s,
            "subinfo_of: got expected warning for undef argument");
    }

    {
        my ($rv, $stderr);
        my $arg = 'main::kalamazoo';
        $stderr = capture_stderr { $rv = $profile->subinfo_of($arg); };
        ok(!defined $rv, "subinfo_of returned undef");
        like($stderr, qr/Can't resolve subinfo of '$arg'/s,
            "subinfo_of: got expected warning for unknown argument");
    }

    {
        my ($rv, $stderr);
        my $arg = 'main::kalamazoo';
        $stderr = capture_stderr { $rv = $profile->file_line_range_of_sub($arg); };
        ok(!defined $rv,
            "file_line_range_of_sub() returned undef with non-existent subroutine");
        like($stderr, qr/Can't resolve subinfo of '$arg'/s,
            "file_line_range_of_sub(): got expected warning for unknown argument");
    }

    {
        my ($rv, $stderr);
        my $arg = 'main::BEGIN';
        $rv = $profile->file_line_range_of_sub($arg);
        ok(defined $rv,
            "file_line_range_of_sub() returned defined value with known sub as argument");
        like($rv->[0], qr/t\/test01\.p$/,
            "file_line_range_of_sub() identified file used in testing");
    }
}

# resolve_fid()

{
    my $profile = Devel::NYTProf::Data->new({ filename => $file, quiet => 1 });
    ok(defined $profile, "Direct call of constructor returned defined value");

    {
        local $@;
        my ($rv);
        eval { $rv = $profile->resolve_fid(); };
        like($@, qr/^No file specified/,
            "resolve_fid: captured exception for no file specified");
    }

    {
        my ($rv, $file);
        $file = '/foobar_extra_delicious';
        ok(! -f $file, "absolute file does not exist");
        $rv = $profile->resolve_fid($file);
        ok(! defined $rv, "resolve_fid returned undefined value for unknown absolute path");
    }
}


# new()

{
    my $profile = Devel::NYTProf::Data->new(
        { filename => $file, quiet => 1, skip_collapse_evals => 1 }
    );
    ok(defined $profile,
        "Direct call of constructor returned defined value; skip_collapse_evals set");
    isa_ok($profile, 'Devel::NYTProf::Data');
}

{
    my $profile;
    croak "Devel::NYTProf::new() could not locate file for processing"
        unless -f $file;
    local $@;
    eval { $profile = Devel::NYTProf::Data->new(); };
    like($@, qr/Devel::NYTProf::new\(\) could not locate file for processing/,
        "captured exception for file not found");
}

{
    SKIP: {
        skip "Bad interaction when trace_level is set", 3
            if trace_level();
        my $profile;
        local $ENV{NYTPROF_ONLOAD} = 'alpha=beta:gamma=delta:dump=1';
        my $stderr = capture_stderr {
            $profile = Devel::NYTProf::Data->new( { filename => $file, quiet => 1 } );
        };
        SKIP: {
            skip "Not working if invoked with 'perl -d'", 1 if $^P;
            like($stderr, qr/\$VAR1.*'Devel::NYTProf::Data'/s,
                "captured dump when NYTPROF_ONLOAD set");
        }
        ok(defined $profile, "Direct call of constructor returned defined value");
        isa_ok($profile, 'Devel::NYTProf::Data');
    }
}

{
    SKIP: {
        skip "NYTPROF_AUTHOR_TESTING only", 3 unless $ENV{NYTPROF_AUTHOR_TESTING};
        skip "Bad interaction when trace_level is set", 3
            if trace_level();
        my $profile;
        local $ENV{NYTPROF_ONLOAD} = 'alpha=beta:gamma=delta:dump=0';
        my $stderr = capture_stderr {
            $profile = Devel::NYTProf::Data->new( { filename => $file, quiet => 1 } );
        };
        ok(! $stderr, "Nothing dumped, as requested");
        ok(defined $profile, "Direct call of constructor returned defined value");
        isa_ok($profile, 'Devel::NYTProf::Data');
    }
    
}

{
    # This test block will probably not exercise its intended condition unless
    # we're testing with a higher trace level.
    local $ENV{NYTPROF_MAX_EVAL_SIBLINGS} = 2;
    my $profile = Devel::NYTProf::Data->new( {filename => $file, quiet => 1 });
    ok(defined $profile,
        "Direct call of constructor returned defined value; reduced NYTPROF_MAX_EVAL_SIBLINGS");
    isa_ok($profile, 'Devel::NYTProf::Data');
}

# dump_profile_data()

{
    my $profile = Devel::NYTProf::Data->new({ filename => $file, quiet => 1 });
    my ($rv, $stdout, @lines, $linecount);
    $stdout = capture_stdout { $rv = $profile->dump_profile_data(); };
    ok($rv, "dump_profile_data() returned true value");
    ok($stdout, "retrieved dumped profile data");
    @lines = split(/\n+/, $stdout);
    $linecount = scalar(@lines);
    my $indented_linecount = 0;
    for my $l (@lines) {
        $indented_linecount++ if $l =~ m/^\s+/;
    }
    cmp_ok($indented_linecount, '>', $linecount / 2,
        "with no argument for separator, most lines in dumped profile data ($indented_linecount / $linecount) are indented");

    $stdout = capture_stdout {
        $rv = $profile->dump_profile_data( { separator => ':::' } );
    };
    ok($rv, "dump_profile_data() returned true value");
    ok($stdout, "retrieved dumped profile data");
    @lines = split(/\n+/, $stdout);
    $linecount = scalar(@lines);
    my $three_colon_linecount = 0;
    for my $l (@lines) {
        $three_colon_linecount++ if $l =~ m/^[^:]+:::/;
    }
    cmp_ok($three_colon_linecount, '==', $linecount,
        "with ':::' separator, all lines in dumped profile data are appropriately delimited");
}

# get_fid_line_data()

{
    my $profile = Devel::NYTProf::Data->new({ filename => $file, quiet => 1 });
    my %dumps = ();
    for my $level (qw| line block sub |) {
        my $fid_ary;
        $dumps{$level} = capture_stdout { $fid_ary = $profile->get_fid_line_data($level); };
        is(ref($fid_ary), 'ARRAY', "get_fid_line_data() returned array ref for '$level'");
    }
    $dumps{no_arg} = capture_stdout { $profile->get_fid_line_data(); };
    is($dumps{no_arg}, $dumps{line}, "get_fid_line_data() defaults to 'line'");
}

# normalize_variables()

{
    my ($profile, $rv);
    $profile = Devel::NYTProf::Data->new({ filename => $file, quiet => 1 });
    $rv = $profile->normalize_variables(1);
    ok($rv, "normalize_variables() returned true value with true argument");

    $rv = $profile->normalize_variables(0);
    ok($rv, "normalize_variables() returned true value with false argument");

    $rv = $profile->normalize_variables();
    ok($rv, "normalize_variables() returned true value with no argument");
}

# attributes() / options()

{
    my ($profile, $rv);
    my (%expected, %seen);
    $profile = Devel::NYTProf::Data->new({ filename => $file, quiet => 1 });
    # Expected attributes will change as NYTProf changes
    # This list only reflects what's in $file
    %expected = map { $_ => 1 } ( qw|
        application
        basetime
        clock_id
        complete
        cumulative_overhead_ticks
        nv_size
        perl_version
        PL_perldb
        profiler_active
        profiler_duration
        profiler_end_time
        profiler_start_time
        ticks_per_sec
        total_stmts_discounted
        total_stmts_duration
        total_stmts_measured
        total_sub_calls
        xs_version
    | );
    $rv = $profile->attributes;
    %seen = map { $_ => 1 } keys %{$rv};
    is_deeply(\%seen, \%expected, "got expected attributes for this version of NYTProf")
        or diag( [ sort keys %expected], [ sort keys %seen ]);

    # Expected options will change as NYTProf changes
    # This list only reflects what's in $file
    %expected = map { $_ => 1 } ( qw|
        blocks
        calls
        clock
        compress
        evals
        expand
        findcaller
        forkdepth
        leave
        nameanonsubs
        nameevals
        perldb
        slowops
        stmts
        subs
        trace
        usecputime
        use_db_sub
    | );
    $rv = $profile->options;
    %seen = map { $_ => 1 } keys %{$rv};
    is_deeply(\%seen, \%expected, "got expected options for this version of NYTProf")
        or diag( [ sort keys %expected], [ sort keys %seen ]);
}

done_testing();
