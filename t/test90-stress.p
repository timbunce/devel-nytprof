# Assorted stress tests
# We're happy if we run this without dieing...

my $is_developer = (-d '.svn');

check_readonly() if $is_developer;

sub check_readonly {
    unless (eval { require Readonly }) {
        warn "readonly test skipped - Readonly module not installed\n";
        return;
    }
    # Check for #   "Invalid tie at .../Readonly.pm line 278"
    # which was noticed first around r266 (when Readonly::XS is not installed).
    # Looks like it only affects perl <5.8.8. It's not related to
    # the DB::DB workaround because it happens with use_db_sub=0 as well.
    # Readonly uses caller() to explicitly check where it's being called from:
    #   my $whence = (caller 2)[3];    # Check if naughty user is trying to tie directly.
    #   Readonly::croak "Invalid tie"  unless $whence && $whence =~ /^Readonly::(?:Scalar1?|Readonly)$/;
    eval q{
        Readonly::Scalar  my $sca => 42;
        Readonly::Array   my @arr => qw(A B C);
        Readonly::Hash    my %has => (A => 1, B => 2);
        1;
    } or die;
    warn "ok - readonly\n";
}
