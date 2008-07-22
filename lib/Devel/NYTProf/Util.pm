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
package Devel::NYTProf::Util;

=head1 NAME

Devel::NYTProf::Util - general utility functions for L<Devel::NYTProf>

=head1 SYNOPSIS

  use Devel::NYTProf::Util qw(strip_prefix_from_paths);

=head1 DESCRIPTION

Contains general utility functions for L<Devel::NYTProf>

B<Note:> The documentation for this module is currently incomplete and out of date.

=head1 FUNCTIONS

=cut

use warnings;
use strict;

use base qw'Exporter';

use Carp;
use Cwd qw(getcwd);
use List::Util qw(sum);
use UNIVERSAL qw( isa can VERSION );

our $VERSION = '2.01';

our @EXPORT_OK = qw(
	fmt_float
	fmt_incl_excl_time
	strip_prefix_from_paths
	calculate_median_absolute_deviation
	get_alternation_regex
	get_abs_paths_alternation_regex
	html_safe_filename
);


sub get_alternation_regex {
	my ($strings, $suffix_regex) = @_;
	$suffix_regex = '' unless defined $suffix_regex;

	# sort longest string first
	my @strings = sort { length $b <=> length $a } @$strings;

	# build string regex for each string
	my $regex = join "|", map { quotemeta($_) . $suffix_regex } @strings;

	return qr/(?:$regex)/;
}


sub get_abs_paths_alternation_regex {
	my ($inc, $cwd) = @_;
	my @inc = @$inc or croak "No paths";

	# rewrite relative directories to be absolute
  # the logic here should match that in get_file_id()
  for (@inc) {
    next if m{^\/};   # already absolute
    $_ =~ s/^\.\///;  # remove a leading './'
		$cwd ||= getcwd();
    $_ = ($_ eq '.') ? $cwd : "$cwd/$_";
  }

	return get_alternation_regex(\@inc, '/?');
}

# edit @$paths in-place to remove specified absolute path prefixes
sub strip_prefix_from_paths {
	my ($inc_ref, $paths, $anchor) = @_;
	$anchor = '^' if not defined $anchor;

	my @inc = @$inc_ref
		or return;
	return if not defined $paths;

	my $inc_regex = get_abs_paths_alternation_regex(\@inc);

	# anchor at start, capture anchor, soak up any /'s at end
	$inc_regex = qr{($anchor)$inc_regex};

	# strip off prefix using regex, skip any empty/undef paths
	if (UNIVERSAL::isa($paths, 'ARRAY')) {
		for my $path (@$paths) {
			if (ref $path) { # recurse to process deeper data
				strip_prefix_from_paths($inc_ref, $path, $anchor);
			}
			elsif ($path) {
				$path =~ s{$inc_regex}{};
			}
		}
	}
	elsif (UNIVERSAL::isa($paths,'HASH')) {
		for my $orig (keys %$paths) {
			(my $new = $orig) =~ s{$inc_regex}{$1}
				or next;
			my $value = delete $paths->{$orig};
			warn "Stripping prefix from $orig overwrites existing $new"
				if defined $paths->{$new};
			$paths->{$new} = $value;
		}
	}
	else {
		croak "Can't strip_prefix_from_paths of $paths";
	}

	return;
}


# eg normalize the width/precision so that the tables look good.
sub fmt_float {
  my ($val, $precision) = @_;
  if ($val < 0.00001 and $val > 0) {
    $val = sprintf("%.0e", $val);
  }
  elsif ($val != int($val)) {
		$precision ||= 5;
    $val = sprintf("%.${precision}f", $val);
  }
  return $val;
}


sub fmt_incl_excl_time {
	my ($incl, $excl) = @_;
	my $diff = $incl - $excl;
	return fmt_float($incl)."s" unless $diff;
	return sprintf "%ss (%s+%s)", fmt_float($incl+$excl), fmt_float($excl), fmt_float($incl-$excl);
}


## Given a ref to an array of numeric values
## returns median distance from the median value, and the median value.
## See http://en.wikipedia.org/wiki/Median_absolute_deviation
sub calculate_median_absolute_deviation {
	my $values_ref = shift;
	my ($ignore_zeros) = @_;

	my @values = ($ignore_zeros) ? grep { $_ } @$values_ref : @$values_ref;
	my $median_value = [ sort { $a <=> $b } @values ]->[ @values / 2 ];

	return [ 0, 0 ] if not defined $median_value; # no data

	my @devi = map { abs($_ - $median_value) } @values;
	my $median_devi = [ sort { $a <=> $b } @devi ]->[ @devi / 2 ];

	return [ $median_devi, $median_value ];
}


sub html_safe_filename {
	my ($fname) = @_;
	$fname =~ s{ ^[/\\] }{}x;    # remove leading / or \
	$fname =~ s{  [/\\] }{-}xg;  # replace / and \ with html safe -
	return $fname;
}

1;

__END__

=head1 SEE ALSO

L<Devel::NYTProf> and L<Devel::NYTProf::Data>

=head1 AUTHOR

B<Adam Kaplan>, C<< <akaplan at nytimes.com> >>
B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>
B<Steve Peters>, C<< <steve at fisharerojo.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008 by Tim Bunce, Ireland.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

# vim: ts=2 sw=2 sts=0 noexpandtab:
