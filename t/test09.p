sub foo {
    eval "1;
          2;
          bar();";
}

sub bar {
    eval "1 while (1..10_000)";
}

foo();
foo();
bar();
