package Devel::NYTProf::SubInfo;    # sub_subinfo

use List::Util qw(sum);

sub fid        { $_[0]->[0] ||= $_[0]->profile->package_fids($_[0]->package) }
sub first_line { shift->[1] }
sub last_line  { shift->[2] }
sub calls      { shift->[3] }
sub incl_time  { shift->[4] }
sub excl_time  { shift->[5] }
sub subname    { shift->[6] }
sub profile    { shift->[7] }
sub package    { (my $pkg = shift->subname) =~ s/(.*)::.*/$1/; return $pkg }
sub recur_max_depth { shift->[8] }
sub recur_incl_time { shift->[9] }

sub is_xsub {
    my $self = shift;

    # XXX should test == 0 but some xsubs still have undef first_line etc
    return (!$self->first_line && !$self->last_line);
}

sub fileinfo {
    my $self = shift;
    my $fid  = $self->fid;
    if (!$fid) {
        return undef;    # sub not have a known fid
    }
    $self->profile->fileinfo_of($fid);
}

sub merge_in {
    my $self    = shift;
    my $newinfo = shift;
    $self->[3] += $newinfo->[3];    # calls
    $self->[4] += $newinfo->[4];    # calls
    return;
}

sub _values_for_dump {
    my $self   = shift;
    my @values = @{$self}[0 .. 5, 8, 9 ];
    return \@values;
}

sub callers {
    my $self = shift;

    # { fid => { line => [ count, incl_time ] } }
    my $callers = $self->profile->{sub_caller}->{$self->subname}
        or return undef;

    # XXX should 'collapse' data for calls from eval fids
    # (with an option to not collapse)
    return $callers;
}

sub caller_fids {
    my ($self, $merge_evals) = @_;
    my $callers = $self->callers($merge_evals) || {};
    my @fids = keys %$callers;
    return @fids;    # count in scalar context
}

sub caller_count {
    my ($self, $merge_evals) = @_;
    my $callers = $self->callers($merge_evals) || {};

    # count of the number of distinct locations sub is called from
    return sum(map { scalar keys %$_ } values %$callers);
}

sub caller_places {
    my ($self, $merge_evals) = @_;
    my $callers = $self->callers
        or return 0;

    # scalar: count of the number of distinct locations sub is called from
    # list: array of [ fid, line, @... ]
    my @callers;
    warn "caller_places in list context not implemented/tested yet";
    while (my ($fid, $lines) = each %$callers) {
        push @callers, map { [$fid, $_, @{$lines->{$_}}] } keys %$lines;
    }
    return \@callers;
}

1;
