# test sub name resolution
use Socket;

# call XS sub directly
Socket::pack_sockaddr_un("foo");

# call XS sub imported into main
# (should still be reported as a call to Socket::pack_sockaddr_un)
pack_sockaddr_un("foo");

# call XS sub as a method (ignore the invalid argument)
Socket->pack_sockaddr_un();

# call XS sub as a method via subclass (ignore the invalid argument)
@Subclass::ISA = qw(Socket);
Subclass->pack_sockaddr_un();


