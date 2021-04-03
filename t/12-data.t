use strict;
use warnings;
use Carp;
use Devel::NYTProf::Reader;
use Devel::NYTProf::Util qw( trace_level );
use Test::More;
use File::Spec;
use File::Temp qw( tempdir tempfile );
use Data::Dumper;$Data::Dumper::Indent=1;
use Capture::Tiny qw(capture_stdout capture_stderr );

# Relax this restriction once we figure out how to make test $file work for
# Appveyor.
plan skip_all => "doesn't work without HAS_ZLIB" if (($^O eq "MSWin32") || ($^O eq 'VMS'));

my $file = "./t/nytprof_12-data.out.txt";
croak "No $file" unless -f $file;

my $reporter = Devel::NYTProf::Reader->new($file, { quiet => 1 });
ok(defined $reporter, "Devel::NYTProf::Reader->new returned defined entity");
isa_ok($reporter, 'Devel::NYTProf::Reader');

# package_subinfo_map()

my $profile = $reporter->{profile};
isa_ok($profile, 'Devel::NYTProf::Data');
my $pkgref = $profile->package_subinfo_map(0,1);
is(ref($pkgref), 'HASH', "package_subinfo_map() returned hashref");
isa_ok($pkgref->{"main"}{""}[0], 'Devel::NYTProf::SubInfo');
my $subinfo_obj = $pkgref->{"main"}{""}[0];
isa_ok($subinfo_obj, 'Devel::NYTProf::SubInfo');

# all_fileinfos() / eval_fileinfos() / noneval_fileinfos()

my @all_fileinfos = $profile->all_fileinfos();
is(scalar(@all_fileinfos), 1, "got 1 all_fineinfo");

my @eval_fileinfos = $profile->eval_fileinfos();
is(scalar(@eval_fileinfos), 0, "got 0 eval_fineinfo");

my @noneval_fileinfos = $profile->noneval_fileinfos();
is(scalar(@noneval_fileinfos), 1, "got 1 noneval_fineinfo");

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
        "fileinfo_of: called without unknown argument");
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

    $stderr = capture_stderr {
        $fi = $profile->fileinfo_of($subinfo_obj);
    };
    like($stderr, qr/^Can't resolve fid of/,
        "fileinfo_of: called with object other than Devel::NYTProf::FileInfo");
    ok(! defined($fi), "fileinfo_of returned undef");
}

# subinfo_of()

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

done_testing();
