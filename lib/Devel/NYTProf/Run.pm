package Devel::NYTProf::Run;

# vim: ts=8 sw=4 expandtab:
##########################################################
# This script is part of the Devel::NYTProf distribution
#
# Copyright, contact and other information can be found
# at the bottom of this file, or by going to:
# http://search.cpan.org/dist/Devel-NYTProf/
#
###########################################################
# $Id: Util.pm 809 2009-07-07 13:24:31Z tim.bunce $
###########################################################

=head1 NAME

Devel::NYTProf::Run - Invoke NYTProf on a piece of code and return the profile

=head1 SYNOPSIS

=head1 DESCRIPTION

This module is experimental and subject to change.

=cut

use warnings;
use strict;

use base qw(Exporter);

use Carp;
use Config qw(%Config);
use Devel::NYTProf::Data;

our @EXPORT_OK = qw(
    profile_this
);


my $this_perl = $^X;
$this_perl .= $Config{_exe} if $^O ne 'VMS' and $this_perl !~ m/$Config{_exe}$/i;


# croaks on failure to execute
# carps, not croak, if process has non-zero exit status
# Devel::NYTProf::Data->new may croak, e.g., if data trucated
sub profile_this {
    my %opt = @_;

    my $out_file = $opt{out_file} || 'nytprof.out';

    my @perl = ($this_perl, '-d:NYTProf');
    warn sprintf "profile_this using %s with NYTPROF=%s\n",
            join(" ", @perl), $ENV{NYTPROF} || ''
        if 0;

    if (my $src_file = $opt{src_file}) {
        system(@perl, $src_file) == 0
            or carp "@perl $src_file exited with an error status";
    }
    elsif (my $src_code = $opt{src_code}) {
        open my $fh, "| @perl"
            or croak "Can't open pipe to @perl";
        print $fh $src_code;
        close $fh 
            or carp "@perl exited with an error status";
    }
    else {
        croak "Neither src_file or src_code was provided";
    }

    my $profile = Devel::NYTProf::Data->new( { filename => $out_file } );

    unlink $out_file;

    return $profile;
}

1;
