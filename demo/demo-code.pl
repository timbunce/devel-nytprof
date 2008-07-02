use strict;
use Benchmark;
use File::Find;

sub add {
    $a = $a + 1;
    foo();
}

sub inc {
    ++$a;
    foo();
}

sub foo {
    1;
    1;
    for (1..1000) {
        ++$a;
        ++$a;
    }
    1;
}

timethese( shift || 1000, {
    add => \&add,
    bar => \&inc,
});

sub wanted {
    return 1;
}

find( \&wanted, '.');
