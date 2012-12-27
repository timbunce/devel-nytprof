

our $o;

for my $i (1..100_000) {

    my $named2 = \&bar; sub bar { return 1; 1+$l }  # non-closure
    my $named1 = \&foo; sub foo { return 1; 1+$o }  # non-closure
    my $anon1  =        sub     { return 1; 1+$o }; # non-closure
    my $anon2  =        sub     { return 1; 1+$l }; # closure

    $named2->();
    $named1->(); # faster because of cpu cache of opcode logic?
    $anon1->();
    $anon2->();

    1; # loop
}
