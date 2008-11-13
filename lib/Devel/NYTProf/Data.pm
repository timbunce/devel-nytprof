# vim: ts=8 sw=4 expandtab:
##########################################################
# This script is part of the Devel::NYTProf distribution
#
# Copyright, contact and other information can be found
# at the bottom of this file, or by going to:
# http://search.cpan.org/dist/Devel-NYTProf/
#
###########################################################
# $Id$
###########################################################
package Devel::NYTProf::Data;

=head1 NAME

Devel::NYTProf::Data - L<Devel::NYTProf> data loading and manipulation

=head1 SYNOPSIS

  use Devel::NYTProf::Data;

  $profile = Devel::NYTProf::Data->new( { filename => 'nytprof.out' } );

  $profile->dump_profile_data();

=head1 DESCRIPTION

Reads a profile data file written by L<Devel::NYTProf>, aggregates the
contents, and returns the results as a blessed data structure.

Access to the data should be via methods in this class to avoid breaking
encapsulation (and thus breaking your code when the data structures change in
future versions).

XXX Currently the documentation is out of date as this module is evolving
rapidly.

=head1 METHODS

=cut


use warnings;
use strict;

use Carp;
use Cwd qw(getcwd);
use Scalar::Util qw(blessed);

use Devel::NYTProf::Core;
use Devel::NYTProf::FileInfo;
use Devel::NYTProf::SubInfo;
use Devel::NYTProf::Util qw(make_path_strip_editor strip_prefix_from_paths get_abs_paths_alternation_regex);

our $VERSION = '2.07';

my $trace = (($ENV{NYTPROF}||'') =~ m/\b trace=(\d+) /x) && $1; # XXX a hack

=head2 new

  $profile = Devel::NYTProf::Data->new( { filename => 'nytprof.out' } );

Reads the specified file containing profile data written by L<Devel::NYTProf>,
aggregates the contents, and returns the results as a blessed data structure.

=cut


sub new {
    my $class = shift;
    my $args = shift || { filename => 'nytprof.out' };

    my $file = $args->{filename}
        or croak "No filename specified";

    print "Reading $file\n" unless $args->{quiet};

    my $profile = load_profile_data_from_file($file);
    bless $profile => $class;
    #use Data::Dumper; warn Dumper($profile->{fid_fileinfo});

    my $fid_fileinfo = $profile->{fid_fileinfo};
    my $sub_subinfo  = $profile->{sub_subinfo};
    my $sub_caller   = $profile->{sub_caller};

    # add profile ref so fidinfo & subinfo objects
    # XXX circular ref, add weaken
    $_ and $_->[7] = $profile for @$fid_fileinfo;
    $_->[7] = $profile for values %$sub_subinfo;

    # bless sub_subinfo data
    (my $sub_class = $class) =~ s/\w+$/SubInfo/;
    $_ and bless $_ => $sub_class for values %$sub_subinfo;

    # XXX merge evals - should become a method optionally called here
    # (which uses other methods to do the work and those methods
    # should also be called by Devel::NYTProf::SubInfo::callers())
    my %anon_eval_subs_merged;
    while (my ($subname, $subinfo) = each %$sub_subinfo) {

        # add subname into sub_subinfo
        $subinfo->[6] = $subname;
        if ($subname =~ s/(::__ANON__\[\(\w*eval) \d+\)/$1 0)/) {

            # sub names like "PPI::Node::__ANON__[(eval 286)[PPI/Node.pm:642]:4]"
            # aren't very useful, so we merge them by changing the eval to 0
            my $oldname = $subinfo->[6];
            delete $sub_subinfo->{$oldname};    # delete old name
            if (my $newinfo = $sub_subinfo->{$subname}) {
                $newinfo->merge_in($subinfo);
                warn "merged sub_info $oldname into $subname\n" if $trace;
            }
            else {

                # is first to change, so just move ref to new name
                $sub_subinfo->{$subname} = $subinfo;
                $subinfo->[6] = $subname;
                warn "renamed sub_info $oldname into $subname\n" if $trace;
            }

            # delete sub_caller info and merge into new name
            my $old_caller_info = delete $sub_caller->{$oldname};

            # { 'pkg::sub' => { fid => { line => [ count, incl_time ] } } } */
            if (my $newinfo = $sub_caller->{$subname}) {

                # iterate over old and merge info new
                while (my ($fid, $line_hash) = each %$old_caller_info) {
                    my $new_line_hash = $newinfo->{$fid};
                    if (!$new_line_hash) {
                        $newinfo->{$fid} = $line_hash;
                        warn "renamed sub_caller $oldname into $subname\n" if $trace;
                        next;
                    }
                    warn "merged sub_caller $oldname into $subname\n" if $trace;

                    # merge lines in %$line_hash into %$new_line_hash
                    while (my ($line, $line_info) = each %$line_hash) {
                        my $new_line_info = $new_line_hash->{$line};
                        if (!$new_line_info) {
                            $new_line_hash->{$line} = $line_info;
                            next;
                        }

                        # merge @$line_info into @$new_line_info
                        $new_line_info->[0] += $line_info->[0];
                        $new_line_info->[1] += $line_info->[1];
                    }

                }
            }
            else {
                $sub_caller->{$subname} = $old_caller_info;
            }
        }
    }
    $profile->_clear_caches;

    return $profile;
}

sub _caches       { return shift->{caches} ||= {} }
sub _clear_caches { return delete shift->{caches} }

sub subname_subinfo_map {
    return { %{ shift->{sub_subinfo} } }; # shallow copy
}

sub all_fileinfos {
    my @all = @{shift->{fid_fileinfo}};
    shift @all;    # drop fid 0
    return @all;
}


sub fileinfo_of {
    my $self = shift;
    my $arg  = shift;
    if (not defined $arg) {
        carp "Can't resolve fid of undef value";
        return undef;
    }

    # check if already a file info object
    return $arg if ref $arg and $arg->isa('Devel::NYTProf::FileInfo');

    my $fid = $self->resolve_fid($arg);
    if (not $fid) {
        carp "Can't resolve fid of '$arg'";
        return undef;
    }

    return $self->{fid_fileinfo}[$fid];
}


# map of { eval_fid => base_fid, ... }
sub eval_fid_2_base_fid_map {
    my ($self, $flatten_evals) = @_;
    $flatten_evals ||= 0;

    my $caches = $self->_caches;
    my $cache_key = "eval_fid_2_base_fid_map:$flatten_evals";
    return $caches->{$cache_key} if $caches->{$cache_key};

    my $fid_fileinfo = $self->{fid_fileinfo} || [];
    my $eval_fid_map = {};

    for my $fi (@$fid_fileinfo) {
        my $base_fi = $fi && $fi->eval_fi
            or next;

        while ($flatten_evals and my $b_eval_fi = $base_fi->eval_fi) {
            $base_fi = $b_eval_fi;
        }
        $eval_fid_map->{ $fi->fid } = $base_fi->fid;
    }

    $caches->{$cache_key} = $eval_fid_map;
    return $eval_fid_map;
}


sub fid_sub_calls_map {
    my $self = shift;
    my $sub_caller = $self->{sub_caller} || {};
    my $fid_sub_calls_map = {};
    while ( my ($subname, $fid_hash) = each %$sub_caller ) {
        for my $fid (keys %$fid_hash) {
            push @{ $fid_sub_calls_map->{$fid} }, $subname;
        }
    }
    return $fid_sub_calls_map;
}


sub inc {

    # XXX should return inc from profile data, when it's there
    return @INC;
}

=head2 dump_profile_data

  $profile->dump_profile_data;
  $profile->dump_profile_data( {
      filehandle => \*STDOUT,
      separator  => "",
  } );

Writes the profile data in a reasonably human friendly format to the sepcified
C<filehandle> (default STDOUT).

For non-trivial profiles the output can be very large. As a guide, there'll be
at least one line of output for each line of code executed, plus one for each
place a subroutine was called from, plus one per subroutine.

The default format is a Data::Dumper style whitespace-indented tree.
The types of data present can depend on the options used when profiling.

  {
      attribute => {
          basetime => 1207228764
          ticks_per_sec => 1000000
          xs_version => 1.13
      }
      fid_fileinfo => [
          1: [
              0: test01.p
              1: 
              2: 
              3: 1
              4: 0
              5: 0
              6: 0
          ]
      ]
      fid_line_time => [
          1: [
              2: [ 4e-06 2 ]
              3: [ 1.2e-05 2 ]
              7: [ 4.6e-05 4 ]
              11: [ 2e-06 1 ]
              16: [ 1.2e-05 1 ]
          ]
      ]
      sub_caller => {
          main::bar => {
              1 => {
                  12 => 1 # main::bar was called by fid 1, line 12, 1 time.
                  16 => 1
                  3 => 2
              }
          }
          main::foo => {
              1 => {
                  11 => 1
              }
          }
      }
      sub_subinfo => {
          main::bar => [ 1 6 8 762 2e-06 ]
          main::foo => [ 1 1 4 793 1.5e-06 ]
      }
  }

If C<separator> is true then instead of whitespace, each item of data is
indented with the I<path> through the structure with C<separator> used to
separarate the elements of the path.

  attribute	basetime	1207228260
  attribute	ticks_per_sec	1000000
  attribute	xs_version	1.13
  fid_fileinfo	1	test01.p
  fid_line_time	1	2	[ 4e-06 2 ]
  fid_line_time	1	3	[ 1.1e-05 2 ]
  fid_line_time	1	7	[ 4.4e-05 4 ]
  fid_line_time	1	11	[ 2e-06 1 ]
  fid_line_time	1	16	[ 1e-05 1 ]
  sub_caller	main::bar	1	12	1
  sub_caller	main::bar	1	16	1
  sub_caller	main::bar	1	3	2
  sub_caller	main::foo	1	11	1
  sub_subinfo	main::bar	[ 1 6 8 762 2e-06 ]
  sub_subinfo	main::foo	[ 1 1 4 793 1.5e-06 ]

This format is especially useful for grep'ing and diff'ing.

=cut


sub dump_profile_data {
    my $self       = shift;
    my $args       = shift;
    my $separator  = $args->{separator} || '';
    my $filehandle = $args->{filehandle} || \*STDOUT;
    my $startnode  = $args->{startnode} || $self;       # undocumented
    croak "Invalid startnode" unless ref $startnode;
    $self->_clear_caches;
    _dump_elements($startnode, $separator, $filehandle, []);
}

sub _dump_elements {
    my ($r, $separator, $fh, $path) = @_;
    my $pad = "    ";
    my $padN;

    my $is_hash = (UNIVERSAL::isa($r, 'HASH'));
    my ($start, $end, $colon, $keys) =
          ($is_hash)
        ? ('{', '}', ' => ', [sort keys %$r])
        : ('[', ']', ': ', [0 .. @$r - 1]);

    if ($separator) {
        ($start, $end, $colon) = (undef, undef, $separator);
        $padN = join $separator, @$path, '';
    }
    else {
        $padN = $pad x (@$path + 1);
    }

    my $format = {sub_subinfo => {compact => 1},};

    print $fh "$start\n" if $start;
    $path = [@$path, undef];
    my $key1 = $path->[0] || $keys->[0];
    for my $key (@$keys) {

        my $value = ($is_hash) ? $r->{$key} : $r->[$key];

        # skip undef elements in array
        next if !defined($value) && !$is_hash;

        $value = $value->_values_for_dump
            if blessed $value && $value->can('_values_for_dump');

        next if $key eq 'fid_srclines';

        # special case some common cases to be more compact:
        #		fid_*_time   [fid][line] = [N,N]
        #		sub_subinfo {subname} = [fid,startline,endline,calls,incl_time]
        my $as_compact = $format->{$key1}{compact};
        if (not defined $as_compact) {    # so guess...
            $as_compact =
                (UNIVERSAL::isa($value, 'ARRAY') && @$value <= 9 && !grep { ref or !defined }
                    @$value);
        }

        # print the value intro
        print $fh "$padN$key$colon"
            unless ref $value && !$as_compact;

        if ($as_compact) {
            no warnings qw(uninitialized);
            printf $fh "[ %s ]\n", join(" ", map { defined($_) ? $_ : 'undef' } @$value);
        }
        elsif (ref $value) {
            $path->[-1] = $key;
            _dump_elements($value, $separator, $fh, $path);
        }
        else {
            print $fh "$value\n";
        }
    }
    printf $fh "%s$end\n", ($pad x (@$path - 1)) if $end;
}


sub get_profile_levels {
    return shift->{profile_modes};
}

sub get_fid_line_data {
    my ($self, $level) = @_;
    $level ||= 'line';
    my $fid_line_data = $self->{"fid_${level}_time"};
    return $fid_line_data;
}


=head2 remove_internal_data_of

  $profile->remove_internal_data_of( $fileinfo_or_fid );

Removes from the profile all information relating to the internals of the specified file.
Data for calls made from outside the file to subroutines defined within it, are kept.

=cut


sub remove_internal_data_of {
    my $self     = shift;
    my $fileinfo = $self->fileinfo_of(shift);
    my $fid      = $fileinfo->fid;

    # remove any timing data for inside this file
    for my $level (qw(line block sub)) {
        my $fid_line_data = $self->get_fid_line_data($level)
            or next;
        $fid_line_data->[$fid] = undef;
    }

    # remove all subs defined in this file
    if (my $sub_subinfo = $self->{sub_subinfo}) {
        while (my ($subname, $subinfo) = each %$sub_subinfo) {
            delete $sub_subinfo->{$subname} if (($subinfo->fid||0) == $fid);
        }
    }

    $fileinfo->delete_subs_called_info;
}


=head2 normalize_variables

  $profile->normalize_variables;

Traverses the profile data structure and normalizes highly variable data, such
as the time, in order that the data can more easily be compared. This is used,
for example, by the test suite.

The data normalized is:

=over

=item *

profile timing data: set to 0

=item *

subroutines: timings are set to 0

=item *

attributes, like basetime, xs_version, etc., are set to 0

=item *

filenames: path prefixes matching absolute paths in @INC are changed to "/.../"

=item *

filenames: eval sequence numbers, like "(re_eval 2)" are changed to 0

=item *

calls remove_internal_data_of() for files loaded from absolute paths in @INC

=back

=cut


sub normalize_variables {
    my $self       = shift;

    for my $attr (qw(
        basetime xs_version perl_version clock_id ticks_per_sec nv_size
        profiler_duration profiler_end_time profiler_start_time
        total_stmts_duration
        total_stmts_measured total_stmts_discounted
    )) {
        $self->{attribute}{$attr} = 0;
    }

    my $eval_regex = qr/ \( ((?:re_)?) eval \s \d+ \) /x;

    my $abs_path_regex = $^O eq "MSWin32" ? qr,^\w:/, : qr,^/,;
    my $inc = [ $self->inc, '.' ];
    my @abs_inc = grep { $_ =~ $abs_path_regex } $self->inc;
    my $is_lib_regex = get_abs_paths_alternation_regex(\@abs_inc);
    my $editor = make_path_strip_editor([ $self->inc, '.' ], qr{^|\[}, '/.../');

    for my $fi ($self->all_fileinfos) {

        # normalize eval sequence numbers in 'file' names to 0
        $fi->[0] =~ s/$eval_regex/(${1}eval 0)/g;

        # strip out internal details of library modules
        # (the definition of which is quite vague at the moment)
        $self->remove_internal_data_of($fi)
            if $fi->filename =~ $is_lib_regex;
    }

    # normalize line data
    for my $level (qw(line block sub)) {
        my $fid_line_data = $self->get_fid_line_data($level) || [];

        # zero the statement timing data
        for my $of_fid (@$fid_line_data) {
            _zero_array_elem($of_fid, 0) if $of_fid;
        }
    }

    # zero subroutine inclusive time
    my $sub_subinfo = $self->{sub_subinfo};
    for (values %$sub_subinfo) {
        $_->[4] = $_->[5] = $_->[9] = 0;
    }

    # zero per-call-location subroutine inclusive time
    # { 'pkg::sub' => { fid => { line => [ count, incl, excl, ucpu, scpu, reci, recdepth ] } } }
    my $sub_caller = $self->{sub_caller} || {};
    for (map { values %$_ } map { values %$_ } values %$sub_caller) {
        $_->[1] = $_->[2] = $_->[3] = $_->[4] = $_->[5] = 0;
    }

    $self->make_filenames_relative($inc, '/.../');

    for my $info ($self->{sub_subinfo}, $self->{sub_caller}) {

        # normalize eval sequence numbers in sub names to 0
        for my $subname (keys %$info) {
            (my $newname = $subname) =~ s/$eval_regex/(${1}eval 0)/g;
            next if $newname eq $subname;

            # XXX should merge instead
            warn "Discarded previous $newname info" if $info->{$newname};
            $info->{$newname} = delete $info->{$subname};
        }
    }

    return;
}


# not currently used, guts may be refactored into new methods later
sub _migrate_sub_callers_from_eval_fids {
    my $self = shift;

    # migrate sub calls made from evals to be calls from the base fid
    #
    # map of { eval_fid => base_fid, ... }
    my $eval_fid_map = $self->eval_fid_2_base_fid_map;
    # map of { fid => { subs called from fid... }, ... }
    my $fid_sub_calls_map = $self->fid_sub_calls_map;
    #
    while ( my ($eval_fid, $base_fid) = each %$eval_fid_map ) {
        my $subnames = $fid_sub_calls_map->{$eval_fid}
            or next; # no subs called from this eval fid

        # drill thru string-evals-within-string-evals
        $base_fid = $eval_fid_map->{$base_fid}
            while $eval_fid_map->{$base_fid};

        my $line_of_eval = $self->fileinfo_of($eval_fid)->eval_line;
        warn "Migrating sub calls from eval fid $eval_fid to fid $base_fid line $line_of_eval: @$subnames\n"
            if $trace;

        my $sub_caller = $self->{sub_caller};
        for my $subname (@$subnames) {

            my $eval_calls = delete $sub_caller->{$subname}{$eval_fid}
                or die "panic";
            my $base_calls =        $sub_caller->{$subname}{$base_fid} ||= {};

            warn "merged $subname calls from fid $eval_fid to $base_fid\n"
                if $trace;
            while ( my ($line_in_eval, $eval_line_calls) = each %$eval_calls ) {
                my $e = $eval_calls->{$line_in_eval};
                my $b = $base_calls->{$line_of_eval} ||= [ (0) x @$e ];
                $b->[$_] += $e->[$_] for (0..@$e-1);
            }
        }
    }
    $self->_clear_caches;
}


sub make_filenames_relative {
    my ($self, $roots, $replacement) = @_;
    $roots ||= ['.'];    # e.g. [ @INC, '.' ]

    warn "making filenames relative to @$roots\n"
        if $trace;

    my $editor = make_path_strip_editor($roots, qr{^|\[}, $replacement);

    # strip prefix from start of string and also when embeded
    # e.g., "(eval 42)[/foo/bar/...]"
    for my $fi ($self->all_fileinfos) {
        $editor->($fi->[0]); # XXX breaks encapsulation
    }

    # edit sub names, e.g., "__ANON__[/foo/bar/...:42]"
    for my $info ($self->{sub_subinfo}, $self->{sub_caller}) {
        for my $subname (keys %$info) {
            $editor->(my $newname = $subname)
                or next;
            next if $newname eq $subname;
            warn "Discarded previous $newname info" if $info->{$newname};
            my $value = delete $info->{$subname};
            $info->{$newname} = $value;
            # update subname attribute of SubInfo XXX breaks encapsulation
            $value->[6] = $newname if UNIVERSAL::can($value, 'subname');
        }
    }
}


sub _zero_array_elem {
    my ($ary_of_line_data, $index) = @_;
    for my $line_data (@$ary_of_line_data) {
        next unless $line_data;
        $line_data->[$index] = 0;

        # if line was a string eval
        # then recurse to zero the times within the eval lines
        if (my $eval_lines = $line_data->[2]) {
            _zero_array_elem($eval_lines, $index);    # recurse
        }
    }
}


sub _filename_to_fid {
    my $self = shift;
    my $caches = $self->_caches;
    return $caches->{_filename_to_fid_cache} ||= do {
        my $fid_fileinfo = $self->{fid_fileinfo} || [];
        my $filename_to_fid = {};
        for my $fid (1 .. @$fid_fileinfo - 1) {
            my $filename = $fid_fileinfo->[$fid][0];
            $filename_to_fid->{$filename} = $fid;
        }
        $filename_to_fid;
    };
}


=head2 subs_defined_in_file

  $subs_defined_hash = $profile->subs_defined_in_file( $file, $include_lines );

Returns a reference to a hash containing information about subroutines defined
in a source file.  The $file argument can be an integer file id (fid) or a file
path.

Returns undef if the profile contains no C<sub_subinfo> data for the $file.

The keys of the returned hash are fully qualified subroutine names and the
corresponding value is a hash reference containing L<Devel::NYTProf::SubInfo>
objects.

If $include_lines is true then the hash also contains integer keys
corresponding to the first line of the subroutine. The corresponding value is a
reference to an array. The array contains a hash ref for each of the
subroutines defined on that line, typically just one.

=cut

sub subs_defined_in_file {
    my ($self, $fid, $incl_lines) = @_;
    $fid = $self->resolve_fid($fid);
    $incl_lines ||= 0;
    $incl_lines = 0 if $fid == 0;
    my $caches = $self->_caches;

    my $cache_key = "subs_defined_in_file:$fid:$incl_lines";
    return $caches->{$cache_key} if $caches->{$cache_key};

    my $fi = $self->fileinfo_of($fid)
        or return;
    my %subs = %{ $fi->subs || {} }; # shallow copy

    if ($incl_lines) {    # add in the first-line-number keys
        croak "Can't include line numbers without a fid" unless $fid;
        for (values %subs) {
            next unless defined(my $first_line = $_->first_line);
            push @{$subs{$first_line}}, $_;
        }
    }

    $caches->{$cache_key} = \%subs;
    return $caches->{$cache_key};
}


=head2 subname_at_file_line

  @subname = $profile->subname_at_file_line($file, $line_number);
  $subname = $profile->subname_at_file_line($file, $line_number);

=cut


sub subname_at_file_line {
    my ($self, $fid, $line) = @_;

    my $subs = $self->subs_defined_in_file($fid, 0);

    # XXX could be done more efficiently
    my @subname;
    for my $sub_info (values %$subs) {
        next
            if $sub_info->first_line > $line
            or $sub_info->last_line < $line;
        push @subname, $sub_info->subname;
    }
    @subname = sort { length($a) <=> length($b) } @subname;
    return @subname if wantarray;
    carp
        "Multiple subs at $fid line $line (@subname) but subname_at_file_line called in scalar context"
        if @subname > 1;
    return $subname[0];
}


sub fid_filename {
    my ($self, $fid) = @_;

    my $fileinfo = $self->{fid_fileinfo}->[$fid]
        or return undef;

    while ($fileinfo->[1]) {    # is an eval

        # eg string eval
        # eg [ "(eval 6)[/usr/local/perl58-i/lib/5.8.6/Benchmark.pm:634]", 2, 634 ]
        warn sprintf "fid_filename: fid %d -> %d for %s\n", $fid, $fileinfo->[1], $fileinfo->[0]
            if $trace;

        # follow next link in chain
        my $outer_fid = $fileinfo->[1];
        $fileinfo = $self->{fid_fileinfo}->[$outer_fid];
    }

    return $fileinfo->[0];
}


=head2 file_line_range_of_sub

  ($file, $fid, $first, $last) = $profile->file_line_range_of_sub("main::foo");

Returns the filename, fid, and first and last line numbers for the specified
subroutine (which must be fully qualified with a package name).

Returns an empty list if the subroutine name is not in the profile data.

The $fid return is the 'original' fid associated with the file the subroutine was created in.

The $file returned is the source file that defined the subroutine.

Where is a subroutine is defined within a string eval, for example, the fid
will be the pseudo-fid for the eval, and the $file will be the filename that
executed the eval.

Subroutines that are implemented in XS have a line range of 0,0 and currently
don't have an associated file.

=cut


sub file_line_range_of_sub {
    my ($self, $sub) = @_;

    my $sub_subinfo = $self->{sub_subinfo}{$sub}
        or return;    # no such sub
    my ($fid, $first, $last) = @$sub_subinfo;

    my $fileinfo = $fid && $self->{fid_fileinfo}->[$fid];
    while ($fileinfo->[1]) {    # file is an eval

        # eg string eval
        # eg [ "(eval 6)[/usr/local/perl58-i/lib/5.8.6/Benchmark.pm:634]", 2, 634 ]
        warn sprintf "file_line_range_of_sub: %s: fid %d -> %d for %s\n", $sub, $fid, $fileinfo->[1], $fileinfo->[0]
            if $trace;
        $first = $last = $fileinfo->[2] if 1;    # XXX control via param?

        # follow next link in chain
        my $outer_fid = $fileinfo->[1];
        $fileinfo = $self->{fid_fileinfo}->[$outer_fid];
    }

    return ($fileinfo->[0], $fid, $first, $last);
}


=head2 resolve_fid

  $fid = $profile->resolve_fid( $file );

Returns the integer I<file id> that corresponds to $file.

If $file can't be found and $file looks like a positive integer then it's
presumed to already be a fid and is returned. This is used to enable other
methods to work with fid or file arguments.

If $file can't be found but it uniquely matches the suffix of one of the files
then that corresponding fid is returned.

=cut


sub resolve_fid {
    my ($self, $file) = @_;
    Carp::confess("No file specified") unless defined $file;
    my $resolve_fid_cache = $self->_filename_to_fid;

    # exact match
    return $resolve_fid_cache->{$file}
        if exists $resolve_fid_cache->{$file};

    # looks like a fid already
    return $file
        if $file =~ m/^\d+$/;

    # XXX hack needed to because of how _map_new_to_old deals
    # with .pmc files because of how ::Reporter works
    return $self->resolve_fid($file) if $file =~ s/\.pmc$/.pm/;

    # unfound absolute path, so we're sure we won't find it
    return undef    # XXX carp?
        if $file =~ m/^\//;

    # prepend '/' and grep for trailing matches - if just one then use that
    my $match = qr{/\Q$file\E$};
    my @matches = grep {m/$match/} keys %$resolve_fid_cache;
    return $self->resolve_fid($matches[0])
        if @matches == 1;
    carp "Can't resolve '$file' to a unique file id (matches @matches)"
        if @matches >= 2;

    return undef;
}


=head2 line_calls_for_file

  $line_calls_hash = $profile->line_calls_for_file( $file );

Returns a reference to a hash containing information about subroutine calls
made at individual lines within a source file. The $file
argument can be an integer file id (fid) or a file path. Returns undef if the
profile contains no C<sub_caller> data for the $file.

The keys of the returned hash are line numbers. The values are references to
hashes with fully qualified subroutine names as keys. Each hash value is an
reference to an array containing an integer call count (how many times the sub
was called from that line of that file) and an inclusive time (how much time
was spent inside the sub when it was called from that line of that file).

For example, if the following was line 42 of a file C<foo.pl>:

  ++$wiggle if foo(24) == bar(42);

that line was executed once, and foo and bar were imported from pkg1, then
$profile->line_calls_for_file( 'foo.pl' ) would return something like:

  {
      42 => {
	  'pkg1::foo' => [ 1, 0.02093 ],
	  'pkg1::bar' => [ 1, 0.00154 ],
      },
  }

=cut

sub line_calls_for_file {
    my ($self, $fid, $include_evals) = @_;
    my $orig_fi = $self->fileinfo_of($fid);

    # shallow copy
    my $line_calls = { %{ $orig_fi->sub_call_lines } };
    return $line_calls unless $include_evals;

    for my $fi (@{ $orig_fi->has_evals(1) || [] }) {
        # { line => { subname => [...] }, ... }
        my $sub_call_lines = $fi->sub_call_lines;

        # $outer_line is the line of the eval
        # XXX outer(1) is a little inefficient, could refactor the loop to
        # separate top-level evals from nested evals and use the outer_line
        # from the top level evals
        my (undef, $outer_line) = $fi->outer(1); # outermost

        while (my ($line, $sub_calls_hash) = each %$sub_call_lines) {

            my $ci_for_subs = $line_calls->{$outer_line || $line} ||= {};

            while (my ($subname, $callinfo) = each %$sub_calls_hash) {

                my $ci = $ci_for_subs->{$subname} ||= [];
                if (!@$ci) {    # typical case
                    @$ci = @$callinfo;
                }
                else {          # e.g., multiple calls inside the same string eval
                    #warn "merging calls to $subname from fid $caller_fid line $caller_line ($outer_line || $line)";
                    $ci->[$_] += $callinfo->[$_] for 0..5;
                    $ci->[6]   = $callinfo->[6] if $callinfo->[6] > $ci->[6]; # NYTP_SCi_REC_DEPTH
                }
            }
        }
    }
    return $line_calls;
}


sub package_fids {
    my ($self, $package) = @_;
    my @fids;
    #warn "package_fids '$package'";
    return @fids if wantarray;
    warn "Package 'package' has items defined in multiple fids: @fids\n"
        if @fids > 1;
    return $fids[0];
}


sub _dumper {
    require Data::Dumper;
    return Data::Dumper::Dumper(@_);
}

1;

__END__

=head1 PROFILE DATA STRUTURE

XXX

=head1 SEE ALSO

L<Devel::NYTProf>

=head1 AUTHOR

B<Adam Kaplan>, C<< <akaplan at nytimes.com> >>
B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>
B<Steve Peters>, C<< <steve at fisharerojo.org> >>

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2008 by Adam Kaplan and The New York Times Company.
 Copyright (C) 2008 by Tim Bunce, Ireland.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
