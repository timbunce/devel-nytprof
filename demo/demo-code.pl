use strict 0.1;   # use UNIVERSAL::VERSION
use Benchmark;
use File::Find;

my $count = shift || 100;
my $do_io = shift || (not -t STDIN);

sub add {
    $a = $a + 1;
    foo();
}

sub foo {
    1;
    for (1..1000) {
        ++$a;
        ++$a;
    }
    1;
}

BEGIN { add() }
BEGIN { add() }

sub inc {
    1;
    # call foo and then execute a slow expression *in the same statement*
    # With all line profilers except NYTProf, the time for that expression gets
    # assigned to the previous statement, i.e., the last statement executed in foo()!
    foo() && 'aaaaaaaaaaa' =~ /((a{0,5}){0,5})*[c]/;
    1;
}

timethese( $count, {
    add => \&add,
    bar => \&inc,
});

END {
    warn "ENDING\n";
    add()
}


# --- recursion ---

sub fib {
    my $n = shift;
    return $n if $n < 2;
    fib($n-1) + fib($n-2);
}
fib(7);

# --- File::Find ---

sub wanted {
    return 1;
}

find( \&wanted, '.');


# --- while with slow conditional ---

if ($do_io) {
    print "Enter text. Enter empty line to end.\n" if -t STDIN;
    # time waiting for the second and subsequent inputs
    # should get assigned to the condition statement
    # not the last statement executed in the loop
    while (<>) {
        chomp;
        last if not $_;
        1;
    }
}
