# test to see that 

# example from the overload docs (with slight changes)
{
package two_face; # Scalars with separate string and numeric values.

use overload
    '""' => \&str,            # ref to named sub
    '0+' => sub {shift->[0]}, # ref to anon sub
    '&{}' => "code",          # name of method
    fallback => 1;

sub new {
    my $p = shift;
    bless [@_], $p
}
sub str {
    shift->[0]
}
sub code {
    sub { 1 }
}

}

my $seven = new two_face ("vii", 7);
printf "seven=$seven, seven=%d, eight=%d\n", $seven, $seven+1;
print "seven contains ‘i’\n" if $seven =~ /i/;
$seven->();
