package Devel::NYTProf::SubInfo;    # sub_subinfo

use strict;
use warnings;
use Carp;

use Devel::NYTProf::Constants qw(
    NYTP_SIi_FID NYTP_SIi_FIRST_LINE NYTP_SIi_LAST_LINE
    NYTP_SIi_CALL_COUNT NYTP_SIi_INCL_RTIME NYTP_SIi_EXCL_RTIME
    NYTP_SIi_SUB_NAME NYTP_SIi_PROFILE
    NYTP_SIi_REC_DEPTH NYTP_SIi_RECI_RTIME NYTP_SIi_CALLED_BY

    NYTP_SCi_INCL_RTIME NYTP_SCi_EXCL_RTIME NYTP_SCi_RECI_RTIME
    NYTP_SCi_CALLING_SUB
);

use List::Util qw(sum min max);

sub fid        { $_[0]->[NYTP_SIi_FID] || croak "No fid for $_[0][6]" }

sub first_line { shift->[NYTP_SIi_FIRST_LINE] }

sub last_line  { shift->[NYTP_SIi_LAST_LINE] }

sub calls      { shift->[NYTP_SIi_CALL_COUNT] }

sub incl_time  { shift->[NYTP_SIi_INCL_RTIME] }

sub excl_time  { shift->[NYTP_SIi_EXCL_RTIME] }

sub subname    {
    my $subname = shift->[NYTP_SIi_SUB_NAME];
    return $subname if not ref $subname;
    # the subname of a merged sub is a ref to an array of the merged subnames
    # XXX could be ref to an array of the merged subinfos
    # XXX or better to add a separate accessor instead of abusing subname like this
    return $subname if not defined(my $join = shift);
    return join $join, @$subname;
}

sub subname_without_package {
    my $subname = shift->[NYTP_SIi_SUB_NAME];
    $subname =~ s/.*:://;
    return $subname;
}

sub profile    { shift->[NYTP_SIi_PROFILE] }

sub package    { (my $pkg = shift->subname) =~ s/^(.*)::.*/$1/; return $pkg }

sub recur_max_depth { shift->[NYTP_SIi_REC_DEPTH] }

sub recur_incl_time { shift->[NYTP_SIi_RECI_RTIME] }

# { fid => { line => [ count, incl_time ] } }
sub caller_fid_line_places {
    my ($self, $merge_evals) = @_;
    carp "caller_fid_line_places doesn't merge evals yet" if $merge_evals;
    return $self->[NYTP_SIi_CALLED_BY];
}

sub called_by_subnames {
    my ($self) = @_;
    my $callers = $self->caller_fid_line_places || {};

    my %subnames;
    for my $sc (map { values %$_ } values %$callers) {
        my $caller_subnames = $sc->[NYTP_SCi_CALLING_SUB];
        @subnames{ keys %$caller_subnames } = (); # viv keys
    }

    return \%subnames;
}

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

sub _min {
    my ($a, $b) = @_;
    $a = $b if not defined $a;
    $b = $a if not defined $b;
    # either both are defined or both are undefined here
    return undef unless defined $a;
    return min($a, $b);
}

sub _max {
    my ($a, $b) = @_;
    $a = $b if not defined $a;
    $b = $a if not defined $b;
    # either both are defined or both are undefined here
    return undef unless defined $a;
    return max($a, $b);
}

# merge details of another sub into this one
# there are very few cases where this is sane thing to do
# it's meant for merging things like anon-subs in evals
# e.g., "PPI::Node::__ANON__[(eval 286)[PPI/Node.pm:642]:4]"
sub merge_in {
    my $self = shift;
    my $new = shift;

    # see also "case NYTP_TAG_SUB_CALLERS:" in load_profile_data_from_stream()

    $self->[NYTP_SIi_FIRST_LINE]  = _min($self->[NYTP_SIi_FIRST_LINE], $new->[NYTP_SIi_FIRST_LINE]);
    $self->[NYTP_SIi_LAST_LINE]   = _max($self->[NYTP_SIi_LAST_LINE],  $new->[NYTP_SIi_LAST_LINE]);

    $self->[NYTP_SIi_CALL_COUNT] += $new->[NYTP_SIi_CALL_COUNT];
    $self->[NYTP_SIi_INCL_RTIME] += $new->[NYTP_SIi_INCL_RTIME];
    $self->[NYTP_SIi_EXCL_RTIME] += $new->[NYTP_SIi_EXCL_RTIME];
    $self->[NYTP_SIi_SUB_NAME]    = [ $self->[NYTP_SIi_SUB_NAME] ]
        if not ref $self->[NYTP_SIi_SUB_NAME];
    push @{$self->[NYTP_SIi_SUB_NAME]}, $new->[NYTP_SIi_SUB_NAME];
    $self->[NYTP_SIi_REC_DEPTH]   = max($self->[NYTP_SIi_REC_DEPTH], $new->[NYTP_SIi_REC_DEPTH]);
    # adding reci_rtime is correct only if one sub doesn't call the other
    $self->[NYTP_SIi_RECI_RTIME] += $new->[NYTP_SIi_RECI_RTIME]; # XXX

    # { fid => { line => [ count, incl_time, ... ] } }
    my $dst_called_by = $self->[NYTP_SIi_CALLED_BY] ||= {};
    my $src_called_by = $new ->[NYTP_SIi_CALLED_BY] ||  {};

    my $trace = 0;
    my $subname = $self->subname(' and ');

    # iterate over src and merge into dst
    while (my ($fid, $src_line_hash) = each %$src_called_by) {
        my $dst_line_hash = $dst_called_by->{$fid};
        if (!$dst_line_hash) {
            $dst_called_by->{$fid} = $src_line_hash;
            warn "renamed sub caller $self->[NYTP_SIi_SUB_NAME] into $subname\n" if $trace;
            next;
        }
        warn "merged sub caller $self->[NYTP_SIi_SUB_NAME] into $subname\n" if $trace;

        # merge lines in %$src_line_hash into %$dst_line_hash
        while (my ($line, $src_line_info) = each %$src_line_hash) {
            my $dst_line_info = $dst_line_hash->{$line};
            if (!$dst_line_info) {
                $dst_line_hash->{$line} = $src_line_info;
                next;
            }

            # merge @$src_line_info into @$dst_line_info
            $dst_line_info->[$_] += $src_line_info->[$_] for (
                NYTP_SCi_INCL_RTIME, NYTP_SCi_EXCL_RTIME,
            );
            # ug, we can't really combine recursive incl_time, but this is better than undef
            $dst_line_info->[NYTP_SCi_RECI_RTIME] = max($dst_line_info->[NYTP_SCi_RECI_RTIME],
                                                        $src_line_info->[NYTP_SCi_RECI_RTIME]);

            my $src_cs = $src_line_info->[NYTP_SCi_CALLING_SUB]||={};
            my $dst_cs = $dst_line_info->[NYTP_SCi_CALLING_SUB]||={};
            $dst_cs->{$_} = $src_cs->{$_} for keys %$src_cs;

            #push @{$src_line_info}, "merged"; # flag hack, for debug
        }
    }

    return;
}

sub caller_fids {
    my ($self, $merge_evals) = @_;
    my $callers = $self->caller_fid_line_places($merge_evals) || {};
    my @fids = keys %$callers;
    return @fids;    # count in scalar context
}

sub caller_count { return scalar shift->caller_places; } # XXX deprecate later

# array of [ $fid, $line, $sub_call_info ], ...
sub caller_places {
    my ($self, $merge_evals) = @_;
    my $callers = $self->caller_fid_line_places || {};

    my @callers;
    for my $fid (sort { $a <=> $b } keys %$callers) {
        my $lines_hash = $callers->{$fid};
        for my $line (sort { $a <=> $b } keys %$lines_hash) {
            push @callers, [ $fid, $line, $lines_hash->{$line} ];
        }
    }

    return @callers; # scalar: number of distinct calling locations
}

sub normalize_for_test {
    my $self = shift;
    my $profile = $self->profile;

    # zero subroutine inclusive time
    $self->[NYTP_SIi_INCL_RTIME] = 0;
    $self->[NYTP_SIi_EXCL_RTIME] = 0;
    $self->[NYTP_SIi_RECI_RTIME] = 0;

    # { fid => { line => [ count, incl, excl, ucpu, scpu, reci, recdepth ] } }
    my $callers = $self->caller_fid_line_places || {};

    # delete calls from modules shipped with perl that some tests use
    # (because the line numbers vary between perl versions)
    for my $fid (keys %$callers) {
        next if not $fid;
        my $fileinfo = $profile->fileinfo_of($fid) or next;
        next if $fileinfo->filename !~ /(AutoLoader|Exporter)\.pm$/;
        delete $callers->{$fid};
    }

    # zero per-call-location subroutine inclusive time
    for my $sc (map { values %$_ } values %$callers) {
        $sc->[NYTP_SCi_INCL_RTIME] =
        $sc->[NYTP_SCi_EXCL_RTIME] =
        $sc->[NYTP_SCi_RECI_RTIME] = 0;
    }
}

sub dump {
    my ($self, $separator, $fh, $path, $prefix) = @_;

    my @values = @{$self}[
        NYTP_SIi_FID, NYTP_SIi_FIRST_LINE, NYTP_SIi_LAST_LINE,
        NYTP_SIi_CALL_COUNT, NYTP_SIi_INCL_RTIME, NYTP_SIi_EXCL_RTIME,
        NYTP_SIi_REC_DEPTH, NYTP_SIi_RECI_RTIME
    ];
    printf $fh "%s[ %s ]\n",
        $prefix, join(" ", map { defined($_) ? $_ : 'undef' } @values);

    my @caller_places = $self->caller_places;
    for my $cp (@caller_places) {
        my ($fid, $line, $sc) = @$cp;
        my @sc = @$sc;
        $sc[NYTP_SCi_CALLING_SUB] = join "|", keys %{ $sc[NYTP_SCi_CALLING_SUB] };
        printf $fh "%s%s%s%d%s%d%s[ %s ]\n",
            $prefix,
            'called_by', $separator,
            $fid,  $separator,
            $line, $separator,
            join(" ", map { defined($_) ? $_ : 'undef' } @sc);
    }
}

1;
