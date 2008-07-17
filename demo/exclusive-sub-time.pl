# for testing exclusive time calculations
# use with NYTPROF=trace=3
sub a {
    sleep 2;
    b();
}
sub b {
    sleep 5;
    c();
}
sub c {
    sleep 3;
}
a();
