requires 'List::Util' => 0;
requires 'File::Which' => '1.09';
requires 'XSLoader' => 0;
requires 'Getopt::Long' => 0;
requires 'JSON::MaybeXS' => 0;

on 'test' => sub {
    requires 'Test::More' => '0.84';
    requires 'Test::Differences' => '0.60';
    requires 'Capture::Tiny' => 0;
    requires 'Sub::Name' => '0.11';
    requires 'Test::Pod' => 0;
    requires 'Test::Pod::Coverage' => 0;
    requires 'Test::Portability::Files' => 0;
};
