#!perl -w

# profile NYTProf & nytprofhtml

print "generating an nytprof.out file\n";
# some random code to generate a reasonably interesting profile
# with a reasonable number of source files and source lines
system(q{perl -d:NYTProf -S perlcritic . || true}) == 0 or exit 1;

my $tmp = "nytprof.out.tmp";
rename "nytprof.out", $tmp or die "Can't rename nytprof.out: $!\n";

print "profiling nytprofhtml processing that nytprof.out file\n";
system(qq{time perl -d:NYTProf -S nytprofhtml --file=$tmp}) == 0
    or exit 1;
unlink $tmp;

print "run nytprofhtml on the nytprofhtml profile\n";
system(qq{nytprofhtml --open}) == 0
    or exit 1;
