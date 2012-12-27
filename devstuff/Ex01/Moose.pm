package Ex02::Moose;

use Moose;

has foo => ( is=>'rw', default => sub { 42 } );

$a = Ex02::Moose->new;
$a->foo;
$a->foo(24);

1;
