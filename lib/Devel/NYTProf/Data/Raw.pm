package Devel::NYTProf::Data::Raw;

use warnings;
use strict;

our $VERSION = '2.06';

use base 'Exporter';
our @EXPORT_OK = qw(
     for_chunks
);

use Devel::NYTProf::Core;

sub for_chunks (&%) {
    my($cb, %opts) = @_;
    Devel::NYTProf::Data::load_profile_data_from_file(
	$opts{filename} || 'nytprof.out',
	$cb, $opts{sequence_numbers},
    );
}

1;

__END__

=head1 NAME

Devel::NYTProf::Data::Raw - Reader of Devel::NYTProf data files

=head1 SYNOPSIS

  use Devel::NYTProf::Data::Raw qw(for_chunks);
  for_chunks {
      my $tag = shift;
      print "$tag\n";
      # examine @_
      ....
  }

  # quickly dump content of a file
  use Data::Dump;
  for_chunks(\&dd);

=head1 DESCRIPTION

This module provide a low level interface for reading Devel::NYTProf
data files.  Currently the module only provide a single function:

=over

=item for_chunks( \&callback, %opts )

This function will read the F<nytprof.out> file and invoke the
callback function for each chunk in the file.  The first argument
passed to the callback is the chunk tag.  The rest of the arguments
passed depend on the tag.  See L</"Chunks"> for the details.

The return value of the callback function is ignored.  The
for_chunks() function will croak if the file isn't readable.

The behaviour of the function can be modified by passing key/value
pairs after the callback.  Currently recognized are:

=over

=item filename => $path

The path to the data file to read.  Defaults to F<nytprof.out>.

=item sequence_numbers => $bool

If TRUE pass the chunk sequence number as the first argument (ahead of
the chunk tag) to the callback function.  This is mostly useful for
testing the internal workings of this module, as this should just be a
counter that starts at 0 and increments by 1 for each call to the
callback function.

=back

=back

=head2 Chunks

The F<nytprof.out> file contains a sequence of tagged chunks that are
streamed out as the profiled program runs.  This documents how the
chunks appear when presented to the callback function of the
for_chunks() function for the version 2.0 and 2.1 version of the file format.

=over

=item VERSION => $major, $minor

The first chunk in the file declare what version of the file format
this is.

=item COMMENT => $text

This chunk is just some textual content that can be ignored.

=item ATTRIBUTE => $key, $value

This chunk is repeated at the beginning of the file and used to declare
various facts about the profiling run.

=item START_DEFLATE

This chunk just say that from now on all chunks have been compressed
in the file.

=item PID_START => $pid, $parent_pid (v2.0)

=item PID_START => $pid, $parent_pid, $start_time (v2.1)

Still a mystery to me.

=item NEW_FID => $fid, $eval_fid, $eval_line, $flags, $size, $mtime, $name

Files are represented by integers called $fid and this chunk declare
the mapping between these numbers and file names.

=item TIME_BLOCK => $eval_fid, $eval_line, $ticks, $fid, $line, $block_line, $sub_line

=item TIME_LINE => $eval_fid, $eval_line, $ticks, $fid, $line

A TIME_BLOCK or TIME_LINE chunk is output each time the execution of
the program leaves a line.

=item DISCOUNT

Still a mystery to me.

=item SUB_LINE_RANGE => $fid, $beg, $end, $name

At the end of the run the profiler will output chunks that report on
the subroutines encountered.

=item SUB_CALLERS => $fid, $line, $count, $incl_time, $excl_time, $ucpu_time, $scpu_time, $reci_time, $rec_depth, $name

At the end of the run the profiler will output chunks that report on
where subroutines were called from.

=item SRC_LINE => $fid, $line, $text

Not used (???)

=item PID_END => $pid (v2.0)

=item PID_END => $pid, $end_time (v2.1)

Still a mystery to me.

=back

=head1 SEE ALSO

L<Devel::NYTProf>

=head1 AUTHOR

B<Gisle Aas>

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2008 by Adam Kaplan and The New York Times Company.
 Copyright (C) 2008 by Tim Bunce, Ireland.
 Copyright (C) 2008 by Gisle Aas

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
