package Devel::NYTProf::FileInfo;    # fid_fileinfo

use strict;

use Devel::NYTProf::Util qw(strip_prefix_from_paths);

use Devel::NYTProf::Constants qw(
    NYTP_FIDf_HAS_SRC NYTP_FIDf_SAVE_SRC NYTP_FIDf_IS_FAKE NYTP_FIDf_IS_PMC

    NYTP_FIDi_FILENAME NYTP_FIDi_EVAL_FID NYTP_FIDi_EVAL_LINE NYTP_FIDi_FID
    NYTP_FIDi_FLAGS NYTP_FIDi_FILESIZE NYTP_FIDi_FILEMTIME NYTP_FIDi_PROFILE
    NYTP_FIDi_EVAL_FI NYTP_FIDi_HAS_EVALS NYTP_FIDi_SUBS_DEFINED NYTP_FIDi_SUBS_CALLED
    NYTP_FIDi_elements

    NYTP_SCi_CALL_COUNT NYTP_SCi_INCL_RTIME NYTP_SCi_EXCL_RTIME NYTP_SCi_RECI_RTIME
    NYTP_SCi_CALLING_SUB
);

# extra constants for private elements
use constant {
    NYTP_FIDi_meta            => NYTP_FIDi_elements + 1,
    NYTP_FIDi_sum_stmts_count => NYTP_FIDi_elements + 2,
    NYTP_FIDi_sum_stmts_times => NYTP_FIDi_elements + 3,
};

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
sub is_eval   { shift->[NYTP_FIDi_EVAL_FI()] ? 1 : 0 }

# general purpose hash - mainly a hack to help kill of Reader.pm
sub meta      { shift->[NYTP_FIDi_meta()] ||= {} }

# ref to array of fileinfo's for each string eval in the file, else undef
sub has_evals {
    my ($self, $include_nested) = @_;

    my $eval_fis = $self->[NYTP_FIDi_HAS_EVALS()]
        or return;
    return @$eval_fis if !$include_nested;

    my @eval_fis = @$eval_fis;
    # walk down tree of nested evals, adding them to @fi
    for (my $i=0; my $fi = $eval_fis[$i]; ++$i) {
        push @eval_fis, $fi->has_evals(0);
    }

    return @eval_fis;
}


# return a ref to a hash of { subname => subinfo, ... }
sub subs      { shift->[NYTP_FIDi_SUBS_DEFINED()] }


=head2 sub_call_lines

  $hash = $fi->sub_call_lines;

Returns a reference to a hash containing information about subroutine calls
made at individual lines within the source file.
Returns undef if no subroutine calling information is available.

The keys of the returned hash are line numbers. The values are references to
hashes with fully qualified subroutine names as keys. Each hash value is an
reference to an array containing an integer call count (how many times the sub
was called from that line of that file) and an inclusive time (how much time
was spent inside the sub when it was called from that line of that file).

For example, if the following was line 42 of a file C<foo.pl>:

  ++$wiggle if foo(24) == bar(42);

that line was executed once, and foo and bar were imported from pkg1, then
sub_call_lines() would return something like:

  {
      42 => {
	  'pkg1::foo' => [ 1, 0.02093 ],
	  'pkg1::bar' => [ 1, 0.00154 ],
      },
  }

=cut

sub sub_call_lines  { shift->[NYTP_FIDi_SUBS_CALLED()] }


=head2 evals_by_line

  # { line => { fid_of_eval_at_line => $fi, ... }, ... }
  $hash = $fi->evals_by_line;

Returns a reference to a hash containing information about string evals
executed at individual lines within a source file.

The keys of the returned hash are line numbers. The values are references to
hashes with file id integers as keys and FileInfo objects as values.

=cut

sub evals_by_line {
    my ($self) = @_;

	# find all fids that have have this fid as an eval_fid
	# { line => { fid_of_eval_at_line => $fi, ... } }

	my %evals_by_line;
	my $fid = $self->fid;
    for my $fi ($self->profile->all_fileinfos) {
        next unless (($fi->eval_fid || 0) == $fid);
		$evals_by_line{ $fi->eval_line }->{ $fi->fid } = $fi;
    }

	return \%evals_by_line;
}


sub line_time_data {
    my ($self, $levels) = @_;
    $levels ||= [ 'line' ];
    # XXX this can be optimized once the fidinfo contains directs refs to the data
    my $profile = $self->profile;
    my $fid = $self->fid;
    for my $level (@$levels) {
        my $fid_ary = $profile->get_fid_line_data($level);
        return $fid_ary->[$fid] if $fid_ary && $fid_ary->[$fid];
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


sub sum_of_stmts_count {
    my ($self) = @_;

    my $ref = \$self->[NYTP_FIDi_sum_stmts_count()];
    $$ref = $self->_sum_of_line_time_data(1)
        if not defined $$ref;

    return $$ref;
}

sub sum_of_stmts_time {
    my ($self) = @_;

    my $ref = \$self->[NYTP_FIDi_sum_stmts_times()];
    $$ref = $self->_sum_of_line_time_data(0)
        if not defined $$ref;

    return $$ref;
}

sub _sum_of_line_time_data {
    my ($self, $idx) = @_;
    my $line_time_data = $self->line_time_data([qw(sub block line)]);
    my $sum = 0;
    $sum += $_->[$idx]||0 for @$line_time_data;
    return $sum;
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

# has source code stored within the profile data file
sub has_savesrc {
    my $self = shift;
    return $self->profile->{fid_srclines}[ $self->fid ];
}

sub srclines_array {
    my $self = shift;

    if (my $srclines = $self->has_savesrc) {
        my $copy = [ @$srclines ]; # shallow clone
        shift @$copy; # line 0 not used
        return $copy;
    }

    my $filename = $self->abs_filename;
    if (open my $fh, "<", $filename) {
        return [ <$fh> ];
    }

    if ($self->flags & NYTP_FIDf_IS_FAKE) {
        my $fid = $self->fid;
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
        $sc->[NYTP_SCi_RECI_RTIME] = 0;
    }

}


sub summary {
	my ($fi) = @_;
    return sprintf "fid%d: %s",
		$fi->fid, $fi->filename_without_inc;
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
        for my $eval_fi ($self->has_evals(0)) {
            push @{ $eval_lines{ $eval_fi->eval_line } }, $eval_fi;
        }
        for my $line (sort { $a <=> $b } keys %eval_lines) {
            my $eval_fis = $eval_lines{$line};

            my @has_evals = map { $_->has_evals(1) } @$eval_fis;

            printf $fh "%s%s%s%d%s[ %s %s ]\n", 
                $prefix, 'eval', $separator,
                $eval_fis->[0]->eval_line, $separator,
                scalar @$eval_fis, # count of evals executed on this line
                scalar @has_evals, # count of nested evals they executed
        }

    }

}   

1;
