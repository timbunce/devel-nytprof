use strict;
use warnings;
use Carp;
use Devel::NYTProf::Reader;
use Devel::NYTProf::Util qw( trace_level );
use Test::More;
use File::Spec;
use File::Temp qw( tempdir tempfile );
use Data::Dumper;$Data::Dumper::Indent=1;
use Capture::Tiny ();

# Relax this restriction once we figure out how to make test $file work for
# Appveyor.
plan skip_all => "doesn't work without HAS_ZLIB" if (($^O eq "MSWin32") || ($^O eq 'VMS'));

my $file = "./t/nytprof_12-data.out.txt";
croak "No $file" unless -f $file;

my $reporter = Devel::NYTProf::Reader->new($file, { quiet => 1 });
ok(defined $reporter, "Devel::NYTProf::Reader->new returned defined entity");
isa_ok($reporter, 'Devel::NYTProf::Reader');

my $profile = $reporter->{profile};
isa_ok($profile, 'Devel::NYTProf::Data');
my $pkgref = $profile->package_subinfo_map(0,1);
is(ref($pkgref), 'HASH', "package_subinfo_map() returned hashref");

my @all_fileinfos = $profile->all_fileinfos();
is(scalar(@all_fileinfos), 1, "got 1 all_fineinfo");

my @eval_fileinfos = $profile->eval_fileinfos();
is(scalar(@eval_fileinfos), 0, "got 0 eval_fineinfo");

my @noneval_fileinfos = $profile->noneval_fileinfos();
is(scalar(@noneval_fileinfos), 1, "got 1 noneval_fineinfo");

{
    my $profile;
    my $stdout = Capture::Tiny::capture_stdout {
        $profile = Devel::NYTProf::Data->new( { filename => $file } );
    };
    like($stdout, qr/^Reading $file\nProcessing $file data\n$/s,
        "new(): captured non-quiet output");

    ok(defined $profile, "Direct call of constructor returned defined value");
    isa_ok($profile, 'Devel::NYTProf::Data');

    my ($fi, $stderr);
    $stderr = Capture::Tiny::capture_stderr {
        $fi = $profile->fileinfo_of();
    };
    like($stderr, qr/^Can't resolve fid of undef value/,
        "fileinfo_of: called without argument, caught warning,");
    ok(! defined($fi), "fileinfo_of returned undef");

    my $silent_if_undef = 1;
    $stderr = Capture::Tiny::capture_stderr {
        $fi = $profile->fileinfo_of(undef, $silent_if_undef);
    };
    ok(! $stderr, "fileinfo_of: called without argument, declined warning");
    ok(! defined($fi), "fileinfo_of returned undef");

    my $arg = 'foobar';
    $stderr = Capture::Tiny::capture_stderr {
        $fi = $profile->fileinfo_of($arg);
    };
    like($stderr, qr/^Can't resolve fid of '$arg'/,
        "fileinfo_of: called without unknown argument");
    ok(! defined($fi), "fileinfo_of returned undef");
}

{
    my $profile = Devel::NYTProf::Data->new( { filename => $file, quiet => 1 } );
    ok(defined $profile, "Direct call of constructor returned defined value");
    isa_ok($profile, 'Devel::NYTProf::Data');
}

{
    my $profile = Devel::NYTProf::Data->new(
        { filename => $file, quiet => 1, skip_collapse_evals => 1 }
    );
    ok(defined $profile, "Direct call of constructor returned defined value; skip_collapse_evals set");
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
        my $stderr = Capture::Tiny::capture_stderr {
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
        my $stderr = Capture::Tiny::capture_stderr {
            $profile = Devel::NYTProf::Data->new( { filename => $file, quiet => 1 } );
        };
        ok(! $stderr, "Nothing dumped, as requested");
        ok(defined $profile, "Direct call of constructor returned defined value");
        isa_ok($profile, 'Devel::NYTProf::Data');
    }
}

#print "XXX: $ENV{NYTPROF_ONLOAD}\n";

#for my $tl (2 .. 5) {
#    test_trace_levels($file, $tl);
#}
#
#sub test_trace_levels {
#    my ($file, $tl) = @_;
#    #local $ENV{NYTPROF} = "trace=$tl:start=init";
#    #system(qq|export NYTPROF="trace=$tl:start=init"|) and croak;
#    print "AAA: reported trace level: ", trace_level(), "\n";
#
#    my $profile = Devel::NYTProf::Data->new( { filename => $file, quiet => 1 } );
#    ok(defined $profile, "Direct call of constructor returned defined value");
#    isa_ok($profile, 'Devel::NYTProf::Data');
#    my @noneval_fileinfos = $profile->noneval_fileinfos();
#    is(scalar(@noneval_fileinfos), 1, "got 1 noneval_fineinfo");
#    ok($profile->collapse_evals_in($noneval_fileinfos[0]),
#        "collapse_evals_in() returned true value; requested trace_level $tl"); 
#}

done_testing();
