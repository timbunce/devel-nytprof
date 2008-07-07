# vim: ts=2 sw=2 sts=0 noexpandtab:
##########################################################
# This script is part of the Devel::NYTProf distribution
#
# Copyright, contact and other information can be found
# at the bottom of this file, or by going to:
# http://search.cpan.org/~akaplan/Devel-NYTProf
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

=head1 METHODS

=cut

use warnings;
use strict;

use Carp;
use Cwd qw(getcwd);

use Devel::NYTProf::Core;
use Devel::NYTProf::Util qw(strip_prefix_from_paths);

my $trace = 0;

=head2 new

	$profile = Devel::NYTProf::Data->new( { filename => 'nytprof.out' } );
  
Reads the specified file containing profile data written by L<Devel::NYTProf>,
aggregates the contents, and returns the results as a blessed data structure.

=cut

sub new {
	my $class = shift;
	my $args = shift || { filename => 'nytprof.out' };

	croak "No file specified (@{[ %$args ]})" unless $args->{filename};
	
	my @files;
	if(defined $args->{allowfork}) {
		@files = glob($args->{filename} . "*");
	} else {
		push @files, $args->{filename};
	}
	my $profile;

	for my $file (@files) {
		$profile = Devel::NYTProf::Data::load_profile_data_from_file($file);
	}
	bless $profile => $class;

	return $profile;
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
        1: test01.p
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
	my $self = shift;
	my $args = shift;
	my $separator  = $args->{separator} || '';
	my $filehandle = $args->{filehandle} || \*STDOUT;
	my $startnode  = $args->{startnode} || $self; # undocumented
	croak "Invalid startnode" unless ref $startnode;
	_dump_elements($startnode, $separator, $filehandle, []);
}

sub _dump_elements {
	my ($r, $separator, $fh, $path) = @_;
	my $pad = "    ";
	my $padN;

	my $is_hash = (UNIVERSAL::isa($r, 'HASH'));
	my ($start, $end, $colon, $keys) = ($is_hash)
		? ('{', '}', ' => ', [ sort keys %$r ])
		: ('[', ']', ': ',   [ 0..@$r-1 ]);

	if ($separator) {
		($start, $end, $colon) = (undef, undef, $separator);
		$padN = join $separator, @$path,'';
	}
	else {
		$padN = $pad x (@$path+1);
	}

	my $format = {
		sub_subinfo => { compact => 1 },
	};

	print $fh "$start\n" if $start;
	$path = [ @$path, undef ];
	my $key1 = $path->[0] || $keys->[0];
	for my $key (@$keys) {

		my $value = ($is_hash) ? $r->{$key} : $r->[$key];

		# skip undef elements in array
		next if !defined($value) && !$is_hash;

		# special case some common cases to be more compact:
		#		fid_*_time   [fid][line] = [N,N]
		#		sub_subinfo {subname} = [fid,startline,endline,calls,incl_time]
		my $as_compact = $format->{$key1}{compact};
		if (not defined $as_compact) { # so guess...
			$as_compact = (ref $value eq 'ARRAY' && @$value <= 9
										&& !grep { ref or !defined } @$value);
		}

		# print the value intro
		print $fh "$padN$key$colon"
			unless ref $value && !$as_compact;

		if ($as_compact) {
			no warnings qw(uninitialized);
			printf $fh "[ %s ]\n", join(" ", map { defined($_) ? $_ : 'undef' } @$value );
		}
		elsif (ref $value) {
			$path->[-1] = $key;
			_dump_elements($value, $separator, $fh, $path);
		}
		else {
			print $fh "$value\n";
		}
	}
	printf $fh "%s$end\n", ($pad x (@$path-1)) if $end;
}


=head2 normalize_variables

  $profile->normalize_variables;

Traverses the profile data structure and normalizes highly variable data, such
as the time, in order that the data can more easily be compared. This is used,
for example, by the test suite.

The data normalized is:

 - profile timing data: set to 0
 - basetime attribute: set to 0
 - xs_version attribute: set to 0
 - perl_version attribute: set to 0
 - subroutines: inclusive time set to 0
 - filenames: path prefixes matching absolute paths in @INC are removed
 - filenames: eval sequence numbers, like "(re_eval 2)" are changed to 0

=cut

sub normalize_variables {
	my $self = shift;

	$self->{attribute}{basetime} = 0;
	$self->{attribute}{xs_version} = 0;
	$self->{attribute}{perl_version} = 0;

	for (keys %$self) {

		# fid_line_times => [fid][line][time,...]
		next unless /^fid_\w+_time$/;

		# iterate over the fids that have data
		my $fid_lines = $self->{$_} || [];
		for my $of_fid (@$fid_lines) {
			_zero_array_elem($of_fid, 0) if $of_fid;
		}
	}

	my $sub_subinfo = $self->{sub_subinfo};
	$_->[4] = 0 for values %$sub_subinfo;

	# { 'pkg::sub' => { fid => { line => [ count, incl_time ] } } }
	my $sub_caller = $self->{sub_caller} || {};
	$_->[1]=0 for map { values %$_ } map { values %$_ } values %$sub_caller;

	my $inc = [ @INC, '.' ];

	$self->make_fid_filenames_relative( $inc );

	# normalize sub names like
	#		AutoLoader::__ANON__[/lib/perl5/5.8.6/AutoLoader.pm:96]
	strip_prefix_from_paths($inc, $self->{sub_caller},   '\[');
	strip_prefix_from_paths($inc, $self->{sub_subinfo}, '\[');

	# normalize eval numbers to 0
	# XXX would be nicer to only do this for 'non-local' fids
	for my $info (@{ $self->{fid_fileinfo} }) {
		next unless $info && ref $info;
		$info->[0] =~ s/ \( ((?:re_)?) eval \s \d+ \) /(${1}eval 0)/xg;
	}

	return;
}


sub make_fid_filenames_relative {
	my ($self, $roots) = @_;
	$roots ||= [ '.' ]; # e.g. [ @INC, '.' ]
	strip_prefix_from_paths($roots, $self->{fid_fileinfo}, undef);
}



sub _zero_array_elem {
	my ($ary_of_line_data, $index) = @_;
	for my $line_data (@$ary_of_line_data) {
		next unless $line_data;
		$line_data->[$index] = 0;
		# if line was a string eval
		# then recurse to zero the times within the eval lines
		if (my $eval_lines = $line_data->[2]) {
			_zero_array_elem($eval_lines, $index); # recurse
		}
	}
}


sub _filename_to_fid {
	my $self = shift;
	return $self->{_filename_to_fid_cache} ||= do {
		my $fid_fileinfo = $self->{fid_fileinfo} || [];
		my $filename_to_fid = {};
		for my $fid (1..@$fid_fileinfo-1) {
			my $filename = $fid_fileinfo->[$fid];
			$filename = $filename->[0] if ref $filename; # string eval
			$filename_to_fid->{$filename} = $fid;
		}
		$filename_to_fid;
	};
}


=head2 subs_defined_in_file

  $subs_defined_hash = $profile->subs_defined_in_file( $file, $include_lines );

Returns a reference to a hash containing information about subroutines defined
in a source file.  The $file argument can be an integer file id (fid) or a file path.
Returns undef if the profile contains no C<sub_caller> data for the $file.

The keys are fully qualifies subroutine names and the corresponding value is a
hash reference containing information about the subroutine.

If $include_lines is true then the hash also contains integer keys
corresponding to the first line of the subroutine. The corresponding value is a
reference to an array. The array contains a hash ref for each of the
subroutines defined on that line.

For example, if the file 'foo.pl' defines one subroutine, called pkg1::foo, on
lines 42 thru 49, then $profile->subs_defined_in_file( 'foo.pl', 1 ) would return:

	{
		'pkg1::foo' => {
			subname => 'pkg1::foo',
			fid => 7,
			first_line => 42,
			last_line => 49,
			calls => 726,
			incl_time => 2e-03,
			callers => { ... },
		},
		42 => [ <ref to same hash as above> ]
	}

The C<callers> item is a ref to a hash that describes locations from which the
subroutine was called. For example:

  callers => {
		3 => {       # calls from fid 3
				12 => 1, # sub was called from fid 3, line 12, 1 time.
				16 => 1,
				3 => 2,
		},
		8 => { ... }
	}

=cut

sub subs_defined_in_file {
	my ($self, $fid, $incl_lines) = @_;

	$fid = $self->resolve_fid($fid);
	my $sub_subinfo = $self->{sub_subinfo}
		or return;

	my %subs;
	while ( my ($sub, $subinfo) = each %$sub_subinfo) {
		my ($subfid, $first, $last, $calls, $incl_time) = @$subinfo;
		next if !$subfid || $subfid != $fid;
		$subs{ $sub } = {
			subname => $sub,
			fid => $subfid,
			first_line => $first,
			last_line => $last,
			incl_time => $incl_time || 0,
			calls => $calls || 0,
			callers => $self->{sub_caller}->{$sub},
		};
	}

	if ($incl_lines) { # add in the first-line-number keys
		for (values %subs) {
			next unless defined(my $first_line = $_->{first_line});
			push @{ $subs{ $first_line } }, $_;
		}
	}

	return \%subs;
}


=head2 subname_at_file_line

    @subname = $profile->subname_at_file_line($file, $line_number);
    $subname = $profile->subname_at_file_line($file, $line_number);

=cut

sub subname_at_file_line {
	my ($self, $fid, $line) = @_;
	# XXX could be done more efficiently
	my $subs = $self->subs_defined_in_file($fid, 0);
	my @subname;
	for my $sub_info (values %$subs) {
		next if $sub_info->{first_line} > $line
				 or $sub_info->{last_line}  < $line;
		push @subname, $sub_info->{subname};
	}
	@subname = sort { length($a) <=> length($b) } @subname;
	return @subname if wantarray;
	carp "Multiple subs at $fid line $line (@subname) but subname_at_file_line called in scalar context"
		if @subname > 1;
	return $subname[0];
}


sub fid_filename {
	my ($self, $fid) = @_;

	my $fileinfo = $self->{fid_fileinfo}->[$fid]
		or return undef;

	while ($fileinfo->[1]) { # is an eval
		# eg string eval
		# eg [ "(eval 6)[/usr/local/perl58-i/lib/5.8.6/Benchmark.pm:634]", 2, 634 ]
		warn sprintf "fid_fileinfo: fid %d -> %d for %s\n",
			$fid, $fileinfo->[1], $fileinfo->[0] if $trace;
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
			or return; # no such sub
	my ($fid, $first, $last) = @$sub_subinfo;

	my $fileinfo = $fid && $self->{fid_fileinfo}->[$fid];
	while ($fileinfo->[1]) { # file is an eval
		# eg string eval
		# eg [ "(eval 6)[/usr/local/perl58-i/lib/5.8.6/Benchmark.pm:634]", 2, 634 ]
		warn sprintf "%s: fid %d -> %d for %s\n",
			$sub, $fid, $fileinfo->[1], $fileinfo->[0] if $trace;
		$first = $last = $fileinfo->[2] if 1; # XXX control via param?
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
	my $resolve_fid_cache = $self->_filename_to_fid;

	# exact match
	return $resolve_fid_cache->{$file}
		if exists $resolve_fid_cache->{$file};

	# looks like a fid already
	return $file
		if $file =~ m/^\d+$/;

	# unfound absolute path, so we're sure we won't find it
	return undef	# XXX carp?
		if $file =~ m/^\//;

	# prepend '/' and grep for trailing matches - if just one then use that
	my $match = qr{/\Q$file\E$};
	my @matches = grep { m/$match/ } keys %$resolve_fid_cache;
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
	my ($self, $fid) = @_;

	$fid = $self->resolve_fid($fid);
	my $sub_caller = $self->{sub_caller}
		or return;

	my $line_calls = {};
	while ( my ($sub, $fid_hash) = each %$sub_caller) {
		my $line_calls_hash = $fid_hash->{$fid}
			or next;

		while ( my ($line, $calls) = each %$line_calls_hash) {
			$line_calls->{$line}{$sub} = $calls;
		}

	}
	return $line_calls;
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

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

# vim: ts=2 sw=2 sts=0 noexpandtab:
