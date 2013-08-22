
sub func1 {
	func2(1);
	func3();
	func2(0);
}

sub func2 {
	print "in func2\n";
	if ($_[0] == 1) {
		func4();
	} else {
		for ($i = 0; $i < 5000; $i++) {
			rand();
		}
	}
}

sub func3 {
	print "in func3\n";
	for ($i = 0; $i < 200000; $i++) {
		rand();
	}
}

sub func4 {
	print "in func4\n";
	for ($i = 0; $i < 200000; $i++) {
		rand();
	}
}

func1();
