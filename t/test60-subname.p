# test sub name resolution
use Socket;

# call XS sub directly
Socket::inet_aton("127.1");

# call XS sub imported into main
# (should still be reported as a call to Socket::inet_aton)
inet_aton("127.1");

# call XS sub as a method (ignore the invalid argument)
Socket->inet_aton();

# call XS sub as a method via subclass (ignore the invalid argument)
@Subclass::ISA = qw(Socket);
Subclass->inet_aton();


