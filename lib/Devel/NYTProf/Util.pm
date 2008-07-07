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

=head1 FUNCTIONS

=cut

use warnings;
use strict;

use base qw'Exporter';

use Carp;
use Cwd qw(getcwd);

our @EXPORT_OK = qw(
	strip_prefix_from_paths
	fmt_float
);


# edit @$paths in-place to remove specified absolute path prefixes

sub strip_prefix_from_paths {
	my ($inc_ref, $paths, $anchor) = @_;
	$anchor = '^' if not defined $anchor;

	my @inc = @$inc_ref
		or return;
	return if not defined $paths;

	# rewrite relative directories to be absolute
  # the logic here should match that in get_file_id()
  my $cwd;
  for (@inc) {
    next if m{^\/};   # already absolute
    $_ =~ s/^\.\///;  # remove a leading './'
		$cwd ||= getcwd();
    $_ = ($_ eq '.') ? $cwd : "$cwd/$_";
  }

	# sort longest paths first
	@inc = sort { length $b <=> length $a } @inc;

	# build string regex for each path
	my $inc_regex = join "|", map { quotemeta $_ } @inc;

	# convert to regex object, anchor at start, soak up any /'s at end
	$inc_regex = qr{($anchor)(?:$inc_regex)/*};

	# strip off prefix using regex, skip any empty/undef paths
	if (ref $paths eq 'ARRAY') {
		for my $path (@$paths) {
			if (ref $path) { # recurse to process deeper data
				strip_prefix_from_paths($inc_ref, $path, $anchor);
			}
			elsif ($path) {
				$path =~ s{$inc_regex}{};
			}
		}
	}
	elsif (ref $paths eq 'HASH') {
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


1;

__END__

=head1 SEE ALSO

L<Devel::NYTProf>

=head1 AUTHOR

B<Adam Kaplan>, C<< <akaplan at nytimes.com> >>
B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>
B<Steve Peters>, C<< <steve at fisharerojo.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Tim Bunce, Ireland.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

# vim: ts=2 sw=2 sts=0 noexpandtab:
