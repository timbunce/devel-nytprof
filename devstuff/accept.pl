use strict;
use Socket;
use Carp;

my $port = 9999;

socket(Server, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die "socket: $!";
setsockopt(Server, SOL_SOCKET, SO_REUSEADDR,
                                    pack("l", 1))   || die "setsockopt: $!";
bind(Server, sockaddr_in($port, INADDR_ANY))        || die "bind: $!";
listen(Server,SOMAXCONN)                            || die "listen: $!";


sub do_accept {
    accept(Client,Server);
}
sub run {
    do_accept;
}

warn "server started on $port";
run;
warn "server ending on $port";
exit 0;
