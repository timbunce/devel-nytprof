package Devel::NYTProf::FileInfo;    # fid_fileinfo

use strict;

use Devel::NYTProf::Util qw(strip_prefix_from_paths);

use Devel::NYTProf::Constants qw(
    NYTP_FIDi_FILENAME NYTP_FIDi_EVAL_FID NYTP_FIDi_EVAL_LINE NYTP_FIDi_FID
    NYTP_FIDi_FLAGS NYTP_FIDi_FILESIZE NYTP_FIDi_FILEMTIME NYTP_FIDi_PROFILE
    NYTP_FIDi_EVAL_FI NYTP_FIDi_SUBS_DEFINED NYTP_FIDi_HAS_EVALS
    NYTP_FIDf_IS_PMC
);

sub filename  { shift->[NYTP_FIDi_FILENAME()] }
sub eval_fid  { shift->[NYTP_FIDi_EVAL_FID()] }
sub eval_line { shift->[NYTP_FIDi_EVAL_LINE()] }
sub fid       { shift->[NYTP_FIDi_FID()] }
sub flags     { shift->[NYTP_FIDi_FLAGS()] }
sub size      { shift->[NYTP_FIDi_FILESIZE()] }
sub mtime     { shift->[NYTP_FIDi_FILEMTIME()] }
sub profile   { shift->[NYTP_FIDi_PROFILE()] }

# if fid is an eval then return fileinfo obj for the fid that executed the eval
sub eval_fi   { $_[0]->[NYTP_FIDi_EVAL_FI()] }

# ref to array of fileinfo's for each string eval in the file, else undef
sub has_evals { $_[0]->[NYTP_FIDi_HAS_EVALS()] }

# return a ref to a hash of { subname => subinfo, ... }
sub subs      { $_[0]->[NYTP_FIDi_SUBS_DEFINED()] }


sub _values_for_dump {
    my $self   = shift;
    my @values = @{$self}[
        NYTP_FIDi_FILENAME, NYTP_FIDi_EVAL_FID, NYTP_FIDi_EVAL_LINE, NYTP_FIDi_FID,
        NYTP_FIDi_FLAGS, NYTP_FIDi_FILESIZE, NYTP_FIDi_FILEMTIME
    ];
    $values[0] = $self->filename_without_inc;
    #push @values, $self->has_evals ? "evals:".join(",", map { $_->fid } @{$self->has_evals}) : "";
    return \@values;
}

sub line_time_data {
    my ($self, $levels) = @_;
    $levels ||= [ 'line' ];
    # XXX this can be optimized once the fidinfo contains directs refs to the data
    my $profile = $self->profile;
    my $fid = $self->fid;
    for my $level (@$levels) {
        my $line_data = $profile->get_fid_line_data($level)->[$fid];
        return $line_data if $line_data;
    }
    return undef;
}

sub excl_time { # total exclusive time for fid
    my $self = shift;
    my $line_data = $self->line_time_data([qw(sub block line)])
        || return undef;
    my $excl_time = 0;
    for (@$line_data) {
        next unless $_;
        $excl_time += $_->[0];
        if (my $eval_lines = $_->[2]) {
            # line contains a string eval
            $excl_time += $_->[0] for values %$eval_lines;
        }
    }
    return $excl_time;
}

sub outer {
    my ($self, $recurse) = @_;
    my $fi  = $self->eval_fi
        or return;
    my $prev = $self;

    while ($recurse and my $eval_fi = $fi->eval_fi) {
        $prev = $fi;
        $fi = $eval_fi;
    }
    return $fi unless wantarray;
    return ($fi, $prev->eval_line);
}


sub is_pmc {
    return (shift->flags & NYTP_FIDf_IS_PMC());
}


# should return the filename that the application used
# when loading the file
sub filename_without_inc {
    my $self = shift;
    my $f    = [$self->filename];
    strip_prefix_from_paths([$self->profile->inc], $f);
    return $f->[0];
}

sub delete_subs_called_info {
    my $self = shift;
    my $profile = $self->profile;
    my $sub_caller = $profile->{sub_caller}
        or return;
    my $fid = $self->fid;
    # remove sub_caller info for calls made *from within* this file
    delete $_->{$fid} for values %$sub_caller;
    return;
}

sub srclines_array {
    my $self = shift;
    my $profile = $self->profile;
    #warn Dumper($profile->{fid_srclines});
    my $fid = $self->fid;
    if (my $srclines = $profile->{fid_srclines}[ $fid ]) {
        my $copy = [ @$srclines ]; # shallow clone
        shift @$copy; # line 0 not used
        return $copy;
    }
    # open file
    my $filename = $self->filename;
    # if it's a .pmc then assume that's the file we want to look at
    # (because the main use for .pmc's are related to perl6)
    $filename .= "c" if $self->is_pmc;
    open my $fh, "<", $filename
        or return undef;
    return [ <$fh> ];
}

1;
