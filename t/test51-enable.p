# test using enable_profile() to write multiple profile files

sub foo { 1 }
foo();

DB::disable_profile();
foo();

# switch to new file and (re)enable profiling
DB::enable_profile("nytprof-test51-b.out");
foo();

# switch to new file while already enabled
DB::enable_profile("nytprof-test51-c.out");
foo();

# This can be removed once we have a better test harness
-f $_ or die "$_ should exist"
    for ("nytprof-test51-b.out", "nytprof-test51-c.out");
BEGIN { unlink "nytprof-test51-b.out", "nytprof-test51-c.out" }
