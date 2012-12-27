package Ex01::Subcall;

sub a {
    goto &b;
}
sub b {
    sleep 1; # time here not includes in a() inclusive time
}
a();

1;
