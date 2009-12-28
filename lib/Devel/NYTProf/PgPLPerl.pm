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

#require DynaLoader;
#warn DynaLoader::dl_find_symbol(0, "error_context_stack");

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

=head2 PL/Perl Function Names Are Missing

The names of functions defined using CREATE FUNCTION don't show up in
NYTProf because they're compiled as anonymous subs using a string eval.
There's no easy way to determine the PL/Perl function name because it's only
known to the postgres internals.

(There might be a way using C<DynaLoader::dl_find_symbol(0, "error_context_stack")>
but I've not had time to dig sufficiently deeply into that yet.)

=head2 Explicit call to finish_profile needed

Postgres <= 8.4 doesn't execute END blocks when it shuts down, so NYTProf
doesn't get a chance to terminate the profile cleanly. To get a usable profile
you need to explicitly call finish_profile() in your plperl code.

I've submitted a bug report asking for END blocks to be run at shutdown:
http://archives.postgresql.org/pgsql-bugs/2009-09/threads.php#00289
and I'm working on a patch to fix that and make other improvements to plperl.

=head2 Can't use plperl and plperlu at the same time

Postgres uses separate Perl interpreters for the plperl and plperlu languages.
NYTProf is not multiplicity safe so if you call functions implemented in the
plperl and plperlu languages in the same session, while using NYTProf, you're
likely to get garbage or worse.

=head1 SEE ALSO

L<Devel::NYTProf>

=head1 AUTHOR

B<Tim Bunce>, L<http://www.tim.bunce.name> and L<http://blog.timbunce.org>

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2009 by Tim Bunce.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
