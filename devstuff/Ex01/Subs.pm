package Ex01::Subs;

@a = (1..1000);

sub empty {
}
empty()   for @a;
empty(@a) for @a;


sub args {
    my @args = @_;
}
args(@a)  for @a;

call_a(@a) for @a;
sub call_a {
    my @args = @_;
    call_b(@args);
}
sub call_b {
    my @args = @_;
}

sub fib {                  # recursion
    my $n = shift;
    return $n if $n < 2;
    fib($n-1) + fib($n-2); # time recursing not shown
}
fib(10);

1;
