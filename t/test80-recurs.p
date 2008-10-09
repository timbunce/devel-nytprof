sub recurs {
    my $depth = shift;
    sleep 1;
    recurs($depth-1) if $depth > 1;
}

recurs(2); # recurs gets called twice
    
