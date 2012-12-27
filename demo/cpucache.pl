

my $subref = sub { return };

for my $i (1..100_000) {

    some_expensive_sub();

    $subref->();
    $subref->(); # identical but faster!

    1; # loop
}

sub some_expensive_sub{

    my @x = (1000..1010);
    m/x/ for @x;

}
