# execute 1 million iterations of a 3 statement + condition loop
my $i = shift || 1_000_000;
while (--$i) {
    1;
    ++$a;
    1;
}
