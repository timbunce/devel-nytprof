# Testing various types of eval calls. Some are processed differently internally

sub foo {
  print "in sub foo\n";
}

sub bar {
  print "in sub bar\n";
}

sub baz {
  print "in sub baz\n";
  eval { foo();  # counts as two executions
         foo(); }; # counts as one execution
  eval { x(); # counts as two executions, fails out of eval
         x(); }; # 0 executions. never gets here
}

eval "foo();";  # one vanilla execution, one eval execution
eval { bar(); };  # two executions
baz();
