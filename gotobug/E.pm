package E;

sub as_heavy {
  my $c = (caller(1))[3];
  if ($c =~ /eval/) { require Carp; Carp::confess($c); }
  exit 0;
}

sub export_tags {
  as_heavy();
}

1;
