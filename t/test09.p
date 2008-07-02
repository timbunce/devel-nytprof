sub foo {
    eval "1;
          2;
          bar();";
}

sub bar {
    eval "3;";
}

foo();
foo();
bar();
