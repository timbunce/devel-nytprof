$a = 2;

sub A { }
sub B { }
sub C { --$a }

$a = 2;
while ( C() ) {
    A();
}

$a = 2;
while ( C() ) {
    A();
}
continue {
    B();
}
