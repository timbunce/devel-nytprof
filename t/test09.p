sub foo {
    eval "1;
          2;
          bar();";
}

sub bar {
    eval 'for ($a=0; $a < 10_000; ++$a) { ++$b }';
}

foo();
foo();
bar();
