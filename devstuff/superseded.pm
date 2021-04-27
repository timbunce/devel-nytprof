# 2021-03-31: packages_at_depth_subinfo() not found in distro
# [
#   undef,  # depth 0
#   {       # depth 1
#       "main::" => [ [ subinfo1, subinfo2 ] ],    # 2 subs in 1 pkg
#       "Foo::"  => [ [ subinfo3 ], [ subinfo4 ] ] # 2 subs in 2 pkg
#   }
#   {       # depth 2
#       "Foo::Bar::" => [ [ subinfo3 ] ]           # 1 sub in 1 pkg
#       "Foo::Baz::" => [ [ subinfo4 ] ]           # 1 sub in 1 pkg
#   }
# ]
#
sub packages_at_depth_subinfo {
    my $self = shift;
    my ($opts) = @_;

    my $merged = $opts->{merge_subinfos};
    my $all_pkgs = $self->package_subinfo_map($merged) || {};

    my @packages_at_depth = ({});
    while ( my ($fullpkgname, $subinfos) = each %$all_pkgs ) {

        $subinfos = [ grep { $_->calls } @$subinfos ]
            if not $opts->{include_unused_subs};

        next unless @$subinfos;

        my @parts = split /::/, $fullpkgname; # drops empty trailing part

        # accumulate @$subinfos for the full package name
        # and also for each successive truncation of the package name
        for (my $depth; $depth = @parts; pop @parts) {
            my $pkgname = join('::', @parts, '');

            my $store = ($merged) ? $subinfos->[0] : $subinfos;

            # { "Foo::" => [ [sub1,sub2], [sub3,sub4] ] } # subs from 2 packages
            my $pkgdepthinfo = $packages_at_depth[$depth] ||= {};
            push @{ $pkgdepthinfo->{$pkgname} }, $store;

            last if not $opts->{rollup_packages};
        }
    }
    # fill in any undef holes at depths with no subs
    $_ ||= {} for @packages_at_depth;

    return \@packages_at_depth;
}


# 2021-03-31: package_fids() not exercised anywhere in distro
sub package_fids {
    my ($self, $package) = @_;
    my @fids;
    #warn "package_fids '$package'";
    return @fids if wantarray;
    warn "Package 'package' has items defined in multiple fids: @fids\n"
        if @fids > 1;
    return $fids[0];
}

