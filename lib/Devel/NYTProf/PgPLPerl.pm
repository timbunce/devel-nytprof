# vim: ts=8 sw=4 expandtab:
##########################################################
# This script is part of the Devel::NYTProf distribution
#
# Copyright, contact and other information can be found
# at the bottom of this file, or by going to:
# http://search.cpan.org/dist/Devel-NYTProf/
#
###########################################################
# $Id: Apache.pm 676 2009-01-28 21:55:40Z tim.bunce $
###########################################################
package Devel::NYTProf::PgPLPerl;

#BEGIN { $ENV{NYTPROF}="trace=5:blocks=0:stmts=0:use_db_sub=0" }

use Devel::NYTProf::Core;

DB::set_option("endatexit", 1);
DB::set_option("savesrc", 1);

# hack to make DB::finish_profile available within PL/Perl
use Safe;
my $orig_share_from = \&Safe::share_from;
*Safe::share_from = sub {
	my $obj = shift;
	$obj->$orig_share_from('DB', [ 'finish_profile' ]);
	return $obj->$orig_share_from(@_);
};

require Devel::NYTProf; # init profiler

1;

__END__

=head1 NAME

Devel::NYTProf::PgPLPerl - Profile PostgreSQL PL/Perl functions with Devel::NYTProf

=head1 SYNOPSIS

Edit the vars.pm file in the perl installation being used by postgres
to add the following lines just below the last subroutine:

    # load NYTProf if running inside PostgreSQL
    require Devel::NYTProf::PgPLPerl if defined &SPI::bootstrap;

=head1 DESCRIPTION

This module allows PL/Perl functions inside PostgreSQL database to be profiled with
C<Devel::NYTProf>. 

=head1 LIMITATIONS

The perl functions defined with the C<plperl> language (not C<plperlu>) don't
show up clearly because they're compiled using a string eval within a L<Safe>
compartment. I'm planning to either hack in use of L<Subname> or else disable Safe.

=head1 SEE ALSO

L<Devel::NYTProf>

=head1 AUTHOR

B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2008 by Tim Bunce.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
