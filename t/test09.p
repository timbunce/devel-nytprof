sub foo {
    eval "shift;
          shift;
          bar();";
}

sub bar {
    eval 'for ($a=0; $a < 10_000; ++$a) { ++$b }';
}

foo();
foo();
bar();
