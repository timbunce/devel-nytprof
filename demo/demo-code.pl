use strict;
use Benchmark;
use File::Find;

my $count = shift || 100;
my $do_io = shift || 0;


sub add {
    $a = $a + 1;
    foo();
}

sub inc {
    ++$a;
    # call foo and then execute a slow expression *in the same statement*
    # With all line profilers except NYTProf, the time for that expression gets
    # assigned to the previous statement, i.e., the last statement executed in foo()!
    foo() && 'aaaaaaaaaaa' =~ /((a{0,5}){0,5})*[c]/;
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

END {
    warn "END!\n";
    add()
}

timethese( $count, {
    add => \&add,
    bar => \&inc,
});


# --- recursion ---

sub fib {
    my $n = shift;
    return $n if $n < 2;
    fib($n-1) + fib($n-2);
}
fib(7);


# --- while with slow conditional ---

if ($do_io) {
    print "Enter text. Enter empty line to end.\n";
    # With all line profilers before NYTProf, the time waiting for the
    # second and subsequent inputs gets assigned to the previous statement,
    # i.e., the last statement executed in the loop!
    while (<>) {
        chomp;
        last if not $_;
        1;
    }
}

# --- File::Find ---

sub wanted {
    return 1;
}

find( \&wanted, '.');
