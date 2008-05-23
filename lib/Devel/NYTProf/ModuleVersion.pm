# vim: ts=2 sw=2 sts=0 noexpandtab:
##########################################################
## This script is part of the Devel::NYTProf distribution
##
## Copyright, contact and other information can be found
## at the bottom of this file, or by going to:
## http://search.cpan.org/~akaplan/Devel-NYTProf
##
###########################################################
# Devel::NYTProf::ModuleVersion
#
# WHAT IS THE POINT OF THIS MODULE!?
#
# Basically the distribution version number should be kept
# in Devel/NYTProf.pm as is normally the case.  However,
# since Devel/NYTProf/Reader.pm also uses the NYTProf lib
# - and must load it at runtime - it needs to know the
# distribution version. The easy way to do that would be to
# put a $VERSION in Reader.pm which always matches NYTProfs
# $VERSION.  Thats fine, but its just plain annoying to have
# to increment two version numbers.
#
# Additionally, if the two $VERSIONs ever do NOT match,
# the distribution will fail at runtime (at the XS Loader)
#
###########################################################
## $Id$
###########################################################
package Devel::NYTProf::ModuleVersion;

BEGIN {
	our $VERSION = '1.14'; # increment with XS changes too
}

1;

