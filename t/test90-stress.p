# Assorted stress tests
# We're happy if we run this without dieing...

if (eval { require Readonly }) {
    # Check for #   "Invalid tie at .../Readonly.pm line 278"
    # which was noticed first around r266 (when Readonly::XS is not installed).
    eval q{
        Readonly::Scalar  my $sca => 42;
        Readonly::Array   my @arr => qw(A B C);
        Readonly::Hash    my %has => (A => 1, B => 2);
        1;
    } or die;
}
