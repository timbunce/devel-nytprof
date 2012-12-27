package Ex01::Slowops;

@a = (1..1000);

open my $fh, ">", $file = "deleteme.txt";
print $fh "$_\n" for @a;
close $fh;
unlink $file;

$a = "a" x 1000;
$a =~ m/((a{0,5}){0,5})*[c]/;
$a =~ s/((a{0,5}){0,5})/1/;

$b = "N\x{100}";
chop $b;
s/ (?: [A-Z] | [\d] )+ (?= [\s] ) //x;
s/ (?: [A-Z] | [\d] )+ (?= [\s] ) //x;

sub dummy {}

1;
