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
package Devel::NYTProf::Apache;

our $VERSION = 0.01;

BEGIN {

    # Load Devel::NYTProf before loading any other modules
    # in order that $^P settings apply to the compilation
    # of those modules.

    if (!$ENV{NYTPROF}) {
	    $ENV{NYTPROF} = "file=/tmp/nytprof.$$.out";
	    warn "Defaulting NYTPROF env var to '$ENV{NYTPROF}'";
    }

    require Devel::NYTProf;
}

use strict;

use constant MP2 => (exists $ENV{MOD_PERL_API_VERSION} &&
                     $ENV{MOD_PERL_API_VERSION} == 2) ? 1 : 0;

# arrange for the profile to be enabled in each child
# and cleanly finished when the child exits
if (MP2) {
	require mod_perl2;
	require Apache2::ServerUtil;
	my $s = Apache2::ServerUtil->server;
	$s->push_handlers(PerlChildInitHandler => sub { DB::enable_profile });
	$s->push_handlers(PerlChildExitHandler => sub { DB::_finish });
}
else {
	require Apache;
	if (Apache->can('push_handlers')) {
	    Apache->push_handlers(PerlChildInitHandler => sub { DB::enable_profile });
	    Apache->push_handlers(PerlChildExitHandler => sub { DB::_finish });
	}
	else {
	    Carp::carp("Apache.pm was not loaded");
	}
}

1;

__END__

=head1 NAME

Devel::NYTProf::Apache - Profile mod_perl applications with Devel::NYTProf

=head1 SYNOPSIS

    # in you Apache config file with mod_perl installed
    PerlPassEnv NYTPROF
    PerlModule Devel::NYTProf::Apache

=head1 DESCRIPTION

This module allows mod_perl applciations to be profiled using
C<Devel::NYTProf>. 

=head1 NOTES

For proper functioning of C<Devel::NYTProf>, the NYTPROF environment
variable should be set.  See L<Devel::NYTProf/"ENVIRONMENT VARIABLES"> for 
more details on the settings effected by this environment variable.
Certain settings are important for C<mod_perl> users.

=over 4

=item file=N

Tells C<Devel::NYTProf> where to save your profile data.  The module defaults
to '/tmp/nytprof.$$.out' which may not be what you want.

=back

=head1 SEE ALSO

L<Devel::NYTProf>

=head1 AUTHOR

B<Adam Kaplan>, C<< <akaplan at nytimes.com> >>
B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>
B<Steve Peters>, C<< <steve at fisharerojo.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Adam Kaplan and The New York Times Company.
Copyright (C) 2008 by Steve Peters.
Copyright (C) 2008 by Tim Bunce.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
