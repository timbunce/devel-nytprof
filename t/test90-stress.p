# Assorted stress tests
# We're happy if we run this without dieing...

my $is_developer = (-d '.svn');

if ($is_developer && eval { require Readonly }) {
    # Check for #   "Invalid tie at .../Readonly.pm line 278"
    # which was noticed first around r266 (when Readonly::XS is not installed).
    # Looks like this is due to the workaround we use for perl <5.8.8 DB::DB
    # interacting with the fact that Readonly uses caller() to explicitly
    # check where it's being called from. For example:
    #   my $whence = (caller 2)[3];    # Check if naughty user is trying to tie directly.
    #   Readonly::croak "Invalid tie"  unless $whence && $whence =~ /^Readonly::(?:Scalar1?|Readonly)$/;
    eval q{
        Readonly::Scalar  my $sca => 42;
        Readonly::Array   my @arr => qw(A B C);
        Readonly::Hash    my %has => (A => 1, B => 2);
        1;
    } or die;
}
