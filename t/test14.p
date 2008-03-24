BEGIN {
  use AutoSplit;
  mkdir('./auto');
  autosplit('test14', './auto', 1, 0, 0);
}

use test14;
test14::foo();
test14::bar();
