package Devel::NYTProf::SubInfo;    # sub_subinfo

use strict;
use warnings;
use Carp;

use Devel::NYTProf::Constants qw(
    NYTP_SIi_FID NYTP_SIi_FIRST_LINE NYTP_SIi_LAST_LINE
    NYTP_SIi_CALL_COUNT NYTP_SIi_INCL_RTIME NYTP_SIi_EXCL_RTIME
    NYTP_SIi_SUB_NAME NYTP_SIi_PROFILE
    NYTP_SIi_REC_DEPTH NYTP_SIi_RECI_RTIME
);

use List::Util qw(sum min max);

sub fid        { $_[0]->[NYTP_SIi_FID] || croak "No fid for $_[0][6]" }
sub first_line { shift->[NYTP_SIi_FIRST_LINE] }
sub last_line  { shift->[NYTP_SIi_LAST_LINE] }
sub calls      { shift->[NYTP_SIi_CALL_COUNT] }
sub incl_time  { shift->[NYTP_SIi_INCL_RTIME] }
sub excl_time  { shift->[NYTP_SIi_EXCL_RTIME] }
sub subname    { shift->[NYTP_SIi_SUB_NAME] }
sub profile    { shift->[NYTP_SIi_PROFILE] }
sub package    { (my $pkg = shift->subname) =~ s/^(.*)::.*/$1/; return $pkg }
sub recur_max_depth { shift->[NYTP_SIi_REC_DEPTH] }
sub recur_incl_time { shift->[NYTP_SIi_RECI_RTIME] }

sub is_xsub {
    my $self = shift;

    # XXX should test == 0 but some xsubs still have undef first_line etc
    my $first = $self->first_line;
    return undef if not defined $first;
    return 1     if $first == 0 && $self->last_line == 0;
    return 0;
}

sub fileinfo {
    my $self = shift;
    my $fid  = $self->fid;
    if (!$fid) {
        return undef;    # sub not have a known fid
    }
    $self->profile->fileinfo_of($fid);
}

sub clone {             # shallow
    my $self = shift;
    return bless [ @$self ] => ref $self;
}

# merge details of another sub into this one
# there are few cases where this is sane thing to do
# it's meant for merging things like anon-subs in evals
# e.g., "PPI::Node::__ANON__[(eval 286)[PPI/Node.pm:642]:4]"
sub merge_in {
    my $self    = shift;
    my $new = shift;
    $self->[NYTP_SIi_FIRST_LINE] = min($self->[NYTP_SIi_FIRST_LINE], $new->[NYTP_SIi_FIRST_LINE]);
    $self->[NYTP_SIi_LAST_LINE]  = max($self->[NYTP_SIi_LAST_LINE],  $new->[NYTP_SIi_LAST_LINE]);
    $self->[NYTP_SIi_CALL_COUNT] += $new->[NYTP_SIi_CALL_COUNT];
    $self->[NYTP_SIi_INCL_RTIME] += $new->[NYTP_SIi_INCL_RTIME];
    $self->[NYTP_SIi_EXCL_RTIME] += $new->[NYTP_SIi_EXCL_RTIME];
    $self->[NYTP_SIi_SUB_NAME] = [ $self->[NYTP_SIi_SUB_NAME] ]
        if not ref $self->[NYTP_SIi_SUB_NAME];
    push @{$self->[NYTP_SIi_SUB_NAME]}, $new->[NYTP_SIi_SUB_NAME];
    $self->[NYTP_SIi_REC_DEPTH] = max($self->[NYTP_SIi_REC_DEPTH], $new->[NYTP_SIi_REC_DEPTH]);
    $self->[9] = max($self->[NYTP_SIi_RECI_RTIME], $new->[NYTP_SIi_RECI_RTIME]); # ug, plausible
    return;
}

sub _values_for_dump {
    my $self   = shift;
    my @values = @{$self}[
        NYTP_SIi_FID, NYTP_SIi_FIRST_LINE, NYTP_SIi_LAST_LINE,
        NYTP_SIi_CALL_COUNT, NYTP_SIi_INCL_RTIME, NYTP_SIi_EXCL_RTIME,
        NYTP_SIi_REC_DEPTH, NYTP_SIi_RECI_RTIME
    ];
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
