# test using enable_profile() to write multiple profile files

my $file_b = "nytprof-test51-b.out";
my $file_c = "nytprof-test51-c.out";
unlink $file_b, $file_c;

eval "sub sub$_ { 1 }" for (1..10);

sub1(); # profiled

DB::disable_profile();

sub2(); # not profiled

# switch to new file and (re)enable profiling
# the new file includes accumulated fid and subs-called data
DB::enable_profile($file_b);

sub3(); # profiled

DB::finish_profile();
die "$file_b should exist" unless -s $file_b;

sub4(); # not profiled

# enable to new file
DB::enable_profile($file_c);

sub5(); # profiled but file will be overwritten by enable_profile() below

DB::finish_profile();

sub6(); # not profiled

DB::enable_profile(); # enable to current file

sub7(); # profiled

DB::finish_profile();

# This can be removed once we have a better test harness
-f $_ or die "$_ should exist" for ($file_b, $file_c);
