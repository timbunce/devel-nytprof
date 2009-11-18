package Devel::NYTProf::FileInfo;    # fid_fileinfo

use strict;

use Devel::NYTProf::Util qw(strip_prefix_from_paths);

use Devel::NYTProf::Constants qw(
    NYTP_FIDf_HAS_SRC NYTP_FIDf_SAVE_SRC NYTP_FIDf_IS_FAKE

    NYTP_FIDi_FILENAME NYTP_FIDi_EVAL_FID NYTP_FIDi_EVAL_LINE NYTP_FIDi_FID
    NYTP_FIDi_FLAGS NYTP_FIDi_FILESIZE NYTP_FIDi_FILEMTIME NYTP_FIDi_PROFILE
    NYTP_FIDi_EVAL_FI NYTP_FIDi_HAS_EVALS NYTP_FIDi_SUBS_DEFINED NYTP_FIDi_SUBS_CALLED
    NYTP_FIDf_IS_PMC

    NYTP_SCi_CALL_COUNT NYTP_SCi_INCL_RTIME NYTP_SCi_EXCL_RTIME
    NYTP_SCi_INCL_UTIME NYTP_SCi_INCL_STIME NYTP_SCi_RECI_RTIME
    NYTP_SCi_CALLING_SUB
);


sub filename  { shift->[NYTP_FIDi_FILENAME()] }
sub eval_fid  { shift->[NYTP_FIDi_EVAL_FID()] }
sub eval_line { shift->[NYTP_FIDi_EVAL_LINE()] }
sub fid       { shift->[NYTP_FIDi_FID()] }
sub flags     { shift->[NYTP_FIDi_FLAGS()] }
sub size      { shift->[NYTP_FIDi_FILESIZE()] }
sub mtime     { shift->[NYTP_FIDi_FILEMTIME()] }
sub profile   { shift->[NYTP_FIDi_PROFILE()] }

# if an eval then return fileinfo obj for the fid that executed the eval
sub eval_fi   { shift->[NYTP_FIDi_EVAL_FI()] }

# ref to array of fileinfo's for each string eval in the file, else undef
sub has_evals {
    my ($self, $include_nested) = @_;

    my $eval_fis = $self->[NYTP_FIDi_HAS_EVALS()]
        or return undef;
    return $eval_fis if !$include_nested;

    my @eval_fis = @$eval_fis;
    # walk down tree of nested evals, adding them to @fi
    for (my $i=0; my $fi = $eval_fis[$i]; ++$i) {
        push @eval_fis, @{ $fi->has_evals || [] };
    }

    return \@eval_fis;
}

# return a ref to a hash of { subname => subinfo, ... }
sub subs      { shift->[NYTP_FIDi_SUBS_DEFINED()] }

# return a ref to a hash of { line => { subname => [...] }, ... }
sub sub_call_lines  { shift->[NYTP_FIDi_SUBS_CALLED()] }


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
        # XXX this old mechanism should be deprecated soon
        if (my $eval_lines = $_->[2]) {
            # line contains a string eval
            $excl_time += $_->[0] for values %$eval_lines;
        }
    }
    return $excl_time;
}


sub number_of_statements_executed {
    my ($self) = @_;
    my $line_time_data = $self->line_time_data;
    use Data::Dumper; warn Data::Dumper::Dumper($line_time_data);
    my $stmts = 0;
    $stmts += $_->[1]||0 for @$line_time_data;
    return $stmts;
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


sub is_perl_std_lib {
    my $self = shift;
    my $filename = $self->filename;
    my $attributes = $self->profile->attributes;
    for (@{$attributes}{qw(PRIVLIB_EXP ARCHLIB_EXP)}) {
        next unless $_;
        return 1 if $filename =~ /\Q$_/;
    }
    return 0;
}


# should return the filename that the application used
# when loading the file
sub filename_without_inc {
    my $self = shift;
    my $f    = [$self->filename];
    strip_prefix_from_paths([$self->profile->inc], $f);
    return $f->[0];
}


sub abs_filename {
    my $self = shift;

    my $filename = $self->filename;

    # strip of autosplit annotation, if any
    $filename =~ s/ \(autosplit into .*//;

    # if it's a .pmc then assume that's the file we want to look at
    # (because the main use for .pmc's are related to perl6)
    $filename .= "c" if $self->is_pmc;

    # search profile @INC if filename is not absolute
    my @files = ($filename);
    if ($filename !~ m/^\//) {
        my @inc = $self->profile->inc;
        @files = map { "$_/$filename" } @inc;
    }

    for my $file (@files) {
        return $file if -f $file;
    }

    # returning the still-relative filename is better than returning an undef
    return $filename;
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

    my $filename = $self->abs_filename;
    if (open my $fh, "<", $filename) {
        return [ <$fh> ];
    }

    if ($self->flags & NYTP_FIDf_IS_FAKE) {
        return [ "# fid$fid: NYTP_FIDf_IS_FAKE - e.g., unknown caller of an eval.\n" ];
    }

    return undef;
}


sub normalize_for_test {
    my $self = shift;

    # normalize eval sequence numbers in 'file' names to 0
    $self->[NYTP_FIDi_FILENAME] =~ s/ \( ((?:re_)?) eval \s \d+ \) /(${1}eval 0)/xg;

    # normalize flags to avoid failures due to savesrc and perl version
    $self->[NYTP_FIDi_FLAGS] &= ~(NYTP_FIDf_HAS_SRC|NYTP_FIDf_SAVE_SRC);

    for my $sc (map { values %$_ } values %{ $self->sub_call_lines }) {
        $sc->[NYTP_SCi_INCL_RTIME] =
        $sc->[NYTP_SCi_EXCL_RTIME] =
        $sc->[NYTP_SCi_INCL_UTIME] =
        $sc->[NYTP_SCi_INCL_STIME] =
        $sc->[NYTP_SCi_RECI_RTIME] = 0;
    }

}


sub dump {      
    my ($self, $separator, $fh, $path, $prefix, $opts) = @_;

    my @values = @{$self}[
        NYTP_FIDi_FILENAME, NYTP_FIDi_EVAL_FID, NYTP_FIDi_EVAL_LINE, NYTP_FIDi_FID,
        NYTP_FIDi_FLAGS, NYTP_FIDi_FILESIZE, NYTP_FIDi_FILEMTIME
    ];
    $values[0] = $self->filename_without_inc;

    printf $fh "%s[ %s ]\n", $prefix, join(" ", map { defined($_) ? $_ : 'undef' } @values);

    if (not $opts->{skip_internal_details}) {
        my $subs = $self->subs;
        for my $subname (sort keys %$subs) {
            my $si = $subs->{$subname};

            printf $fh "%s%s%s%s%s%s-%s\n", 
                $prefix, 'sub', $separator,
                $si->subname(' and '),  $separator,
                $si->first_line, $si->last_line;
        }

        # { line => { subname => [...] }, ... }
        my $sub_call_lines = $self->sub_call_lines;
        for my $line (sort { $a <=> $b } keys %$sub_call_lines) {
            my $subs_called = $sub_call_lines->{$line};

            for my $subname (sort keys %$subs_called) {
                my @sc = @{$subs_called->{$subname}};
                $sc[NYTP_SCi_CALLING_SUB] = join "|", keys %{ $sc[NYTP_SCi_CALLING_SUB] };

                printf $fh "%s%s%s%s%s%s%s[ %s ]\n", 
                    $prefix, 'call', $separator,
                    $line,  $separator, $subname, $separator,
                    join(" ", map { defined($_) ? $_ : 'undef' } @sc)
            }
        }

        # string evals, group by the line the eval is on
        my %eval_lines;
        for my $eval_fi (@{ $self->has_evals(0) || [] }) {
            push @{ $eval_lines{ $eval_fi->eval_line } }, $eval_fi;
        }
        for my $line (sort { $a <=> $b } keys %eval_lines) {
            my $eval_fis = $eval_lines{$line};

            my @has_evals = map { @{ $_->has_evals(1)||[] } } @$eval_fis;

            printf $fh "%s%s%s%d%s[ %s %s ]\n", 
                $prefix, 'eval', $separator,
                $eval_fis->[0]->eval_line, $separator,
                scalar @$eval_fis, # count of evals executed on this line
                scalar @has_evals, # count of nested evals they executed
        }

    }

}   

1;
