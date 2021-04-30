#!perl -w

use Test::More;
plan skip_all => "NYTPROF_AUTHOR_TESTING only" unless $ENV{NYTPROF_AUTHOR_TESTING};

eval "use Test::Pod 1.00";
plan skip_all => "Test::Pod 1.00 required for testing POD" if $@;

all_pod_files_ok();

1;
