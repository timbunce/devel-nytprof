package Devel::NYTProf::Constants;

use strict;

use Devel::NYTProf::Core;

use base 'Exporter';

my $symbol_table = do { no strict; \%{"Devel::NYTProf::Constants::"} };

our @EXPORT_OK = grep { /^NYTP_/ } keys %$symbol_table;

#warn "Constants: ".join(" ", sort @EXPORT_OK);

1;
