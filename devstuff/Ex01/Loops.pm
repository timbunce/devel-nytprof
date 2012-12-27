package Ex01::Loops;

@a = (1..1000);

for my $a (@a) {             # without continue
    1;
    1; # note A
}

for my $a (@a) { # note A    # with continue
    1;
    1;
}
continue {
    1;
    1;
}

# note A: cost of preparing next iteration appears here

1;
