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
package Devel::NYTProf::Core;


use XSLoader;

our $VERSION = '2.02'; # increment with XS changes too

XSLoader::load('Devel::NYTProf', $VERSION);

if (my $NYTPROF = $ENV{NYTPROF}) {
	for my $optval (split /:/, $NYTPROF) {
		my ($opt, $val) = split /=/, $optval, 2;
		DB::set_option( $opt, $val );
	}
}

1;

__END__

=head1 NAME

Devel::NYTProf::Core - load internals of Devel::NYTProf

=head1 DESCRIPTION

This module is not meant to be used directly.
See L<Devel::NYTProf>, L<Devel::NYTProf::Data>, and L<Devel::NYTProf::Reader>.

=head1 AUTHOR

B<Adam Kaplan>, C<< <akaplan at nytimes.com> >>
B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>
B<Steve Peters>, C<< <steve at fisharerojo.org> >>

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2008 by Adam Kaplan and The New York Times Company.
  Copyright (C) 2008 by Tim Bunce.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

# vim: ts=2 sw=2 sts=0 noexpandtab:
